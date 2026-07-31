# VibeCat Event Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless half of VibeCat — a `vibecat-hook` binary that AI CLIs invoke, a Unix-socket server that receives its events, and the session model that decides what the island will eventually display.

**Architecture:** Three SwiftPM targets with no external dependencies. `VibeCatCore` holds pure value types: the shared event vocabulary, an NDJSON codec, the session store and its state-priority rule, and per-CLI adapters. `VibeCatTransport` wraps POSIX `AF_UNIX` sockets in a blocking client (for the hook) and a threaded server (for the app). `vibecat-hook` is a tiny executable that reads a CLI's JSON event on stdin, forwards it, optionally waits for a reply, and **always fails open**.

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing (`import Testing`), POSIX sockets via `Darwin`/`Glibc`. No third-party packages.

This plan produces working, testable software on its own: after Task 12 you can run a real Claude Code hook against a running server and see a session appear, answer a permission prompt, and confirm the hook fails open when the server is down. No UI is involved.

**Source spec:** [`2026-07-31-vibecat-design.md`](../specs/2026-07-31-vibecat-design.md) §2, §3, §4, §13, §16, §17

## Global Constraints

- **Swift 6**, SwiftPM, **no external dependencies** of any kind.
- Apple platform floor: **macOS 14.0**. The hook target must also compile on Linux and FreeBSD — guard every platform import with `#if canImport(Darwin)`.
- **Fail-open is mandatory.** A crashed or absent app must never block a terminal. Default hook deadline **300 ms**; on any error, timeout, or missing socket the hook exits `0` and produces no reply.
- Socket path: `~/Library/Application Support/VibeCat/vibecat.sock`, file mode **`0600`**, owner only.
- Wire format: **newline-delimited JSON**, envelope version field `v: 1`.
- State priority is exactly `waiting > failed > running > idle`.
- **No AI usage, quota, or token accounting** anywhere in the codebase.
- Every type crossing a target boundary is `Sendable`.

---

### Task 1: Package skeleton and the shared event vocabulary

**Files:**
- Create: `Package.swift`
- Create: `Sources/VibeCatCore/VibeEvent.swift`
- Test: `Tests/VibeCatCoreTests/VibeEventTests.swift`
- Create: a placeholder source file in every other declared target — SwiftPM fails
  the build on an empty target. A comment-only `.swift` file for each library, and
  for `Sources/VibeCatHook/main.swift` the single line `// wired up in Task 13`.
  Later tasks replace these; Task 13 overwrites `main.swift` and deletes
  `Sources/VibeCatHookKit/Placeholder.swift`.

**Interfaces:**
- Consumes: nothing
- Produces: `Kind`, `Choice`, `Origin`, `TaskItem`, `AgentItem`, `VibeEvent`, `Reply` — all `Codable & Sendable & Equatable`, all `public`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/VibeEventTests.swift`:

```swift
import Testing
@testable import VibeCatCore

@Test func kindCoversEveryWireValue() {
    #expect(Set(Kind.allCases.map(\.rawValue)) ==
            ["idle", "running", "done", "permission", "question", "failed"])
}

@Test func eventDefaultsAreSafe() {
    let e = VibeEvent(id: "a", cli: "claude-code", kind: .running,
                      session: "s1", cwd: "/tmp/api")
    #expect(e.v == 1)
    #expect(e.multi == false)
    #expect(e.wantsReply == false)
    #expect(e.choices == nil)
    #expect(e.origin == Origin())
}

@Test func taskItemUsesShortWireKeys() throws {
    let json = #"{"t":"Audit auth flow","s":"doing"}"#
    let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
    #expect(item.title == "Audit auth flow")
    #expect(item.status == .doing)
}

@Test func agentItemUsesShortWireKeys() throws {
    let json = #"{"n":"Explore","t":"8s","m":"Sonnet 4.6 · High","sub":"Grep: handleRequest"}"#
    let a = try JSONDecoder().decode(AgentItem.self, from: Data(json.utf8))
    #expect(a.name == "Explore")
    #expect(a.elapsed == "8s")
    #expect(a.model == "Sonnet 4.6 · High")
    #expect(a.activity == "Grep: handleRequest")
    #expect(a.finished == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeEventTests`
Expected: FAIL — `error: no such module 'VibeCatCore'` (the package does not exist yet).

- [ ] **Step 3: Create the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeCat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VibeCatCore", targets: ["VibeCatCore"]),
        .library(name: "VibeCatTransport", targets: ["VibeCatTransport"]),
        .executable(name: "vibecat-hook", targets: ["VibeCatHook"]),
    ],
    targets: [
        .target(name: "VibeCatCore"),
        .target(name: "VibeCatTransport", dependencies: ["VibeCatCore"]),
        // The hook's logic lives in a library so tests can import it. An
        // executable target with a main.swift cannot be @testable imported
        // reliably, so the executable is kept to nothing but wiring.
        .target(name: "VibeCatHookKit", dependencies: ["VibeCatCore", "VibeCatTransport"]),
        // main.swift imports all three directly, so all three are declared —
        // a transitive dependency is not guaranteed to be importable.
        .executableTarget(name: "VibeCatHook",
                          dependencies: ["VibeCatHookKit", "VibeCatCore", "VibeCatTransport"]),
        .testTarget(name: "VibeCatCoreTests", dependencies: ["VibeCatCore"]),
        .testTarget(name: "VibeCatTransportTests",
                    dependencies: ["VibeCatTransport", "VibeCatCore", "VibeCatHookKit"]),
    ]
)
```

- [ ] **Step 4: Write the event vocabulary**

Create `Sources/VibeCatCore/VibeEvent.swift`:

```swift
import Foundation

/// The shared vocabulary every adapter maps its CLI's own event names onto,
/// so the core never learns a vendor's terminology.
public enum Kind: String, Codable, Sendable, CaseIterable {
    case idle, running, done, permission, question, failed
}

public struct Choice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Where the agent is running. Captured by the hook from its own environment —
/// never read from a GUI app.
public struct Origin: Codable, Sendable, Equatable {
    public var app: String?
    public var termSession: String?
    public var vscodePid: String?

    public init(app: String? = nil, termSession: String? = nil, vscodePid: String? = nil) {
        self.app = app
        self.termSession = termSession
        self.vscodePid = vscodePid
    }
}

public struct TaskItem: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case open, doing, done }

    public var title: String
    public var status: Status

    public init(title: String, status: Status) {
        self.title = title
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case title = "t"
        case status = "s"
    }
}

public struct AgentItem: Codable, Sendable, Equatable {
    public var name: String
    public var elapsed: String
    public var model: String
    public var activity: String?
    public var finished: Bool

    public init(name: String, elapsed: String, model: String,
                activity: String? = nil, finished: Bool = false) {
        self.name = name
        self.elapsed = elapsed
        self.model = model
        self.activity = activity
        self.finished = finished
    }

    enum CodingKeys: String, CodingKey {
        case name = "n"
        case elapsed = "t"
        case model = "m"
        case activity = "sub"
        case finished = "done"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        elapsed = try c.decode(String.self, forKey: .elapsed)
        model = try c.decode(String.self, forKey: .model)
        activity = try c.decodeIfPresent(String.self, forKey: .activity)
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
    }
}

public struct VibeEvent: Codable, Sendable, Equatable {
    public var v: Int
    public var id: String
    public var cli: String
    public var kind: Kind
    public var session: String
    public var cwd: String
    public var worktree: String?
    public var model: String?
    public var effort: String?
    public var title: String?
    public var body: String?
    public var choices: [Choice]?
    public var multi: Bool
    public var wantsReply: Bool
    public var tasks: [TaskItem]?
    public var agents: [AgentItem]?
    public var origin: Origin

    public init(v: Int = 1, id: String, cli: String, kind: Kind,
                session: String, cwd: String,
                worktree: String? = nil, model: String? = nil, effort: String? = nil,
                title: String? = nil, body: String? = nil,
                choices: [Choice]? = nil, multi: Bool = false, wantsReply: Bool = false,
                tasks: [TaskItem]? = nil, agents: [AgentItem]? = nil,
                origin: Origin = Origin()) {
        self.v = v
        self.id = id
        self.cli = cli
        self.kind = kind
        self.session = session
        self.cwd = cwd
        self.worktree = worktree
        self.model = model
        self.effort = effort
        self.title = title
        self.body = body
        self.choices = choices
        self.multi = multi
        self.wantsReply = wantsReply
        self.tasks = tasks
        self.agents = agents
        self.origin = origin
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        id = try c.decode(String.self, forKey: .id)
        cli = try c.decode(String.self, forKey: .cli)
        kind = try c.decode(Kind.self, forKey: .kind)
        session = try c.decode(String.self, forKey: .session)
        cwd = try c.decode(String.self, forKey: .cwd)
        worktree = try c.decodeIfPresent(String.self, forKey: .worktree)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        effort = try c.decodeIfPresent(String.self, forKey: .effort)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        choices = try c.decodeIfPresent([Choice].self, forKey: .choices)
        multi = try c.decodeIfPresent(Bool.self, forKey: .multi) ?? false
        wantsReply = try c.decodeIfPresent(Bool.self, forKey: .wantsReply) ?? false
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks)
        agents = try c.decodeIfPresent([AgentItem].self, forKey: .agents)
        origin = try c.decodeIfPresent(Origin.self, forKey: .origin) ?? Origin()
    }
}

public struct Reply: Codable, Sendable, Equatable {
    public var id: String
    public var choice: String?
    public var choices: [String]?
    public var text: String?

    public init(id: String, choice: String? = nil,
                choices: [String]? = nil, text: String? = nil) {
        self.id = id
        self.choice = choice
        self.choices = choices
        self.text = text
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter VibeEventTests`
Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/VibeCatCore/VibeEvent.swift Tests/VibeCatCoreTests/VibeEventTests.swift
git commit -m "feat(core): add the shared event vocabulary"
```

---

### Task 2: NDJSON wire codec

**Files:**
- Create: `Sources/VibeCatCore/WireCodec.swift`
- Test: `Tests/VibeCatCoreTests/WireCodecTests.swift`

**Interfaces:**
- Consumes: `VibeEvent`, `Reply` (Task 1)
- Produces: `enum WireCodec` with
  `static func encode<T: Encodable>(_ value: T) throws -> Data` (JSON + trailing `\n`),
  `static func decode<T: Decodable>(_ type: T.Type, from: Data) throws -> T`,
  `static func splitLines(_ buffer: inout Data) -> [Data]`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/WireCodecTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatCore

@Test func encodeAppendsExactlyOneNewline() throws {
    let e = VibeEvent(id: "a", cli: "claude-code", kind: .running, session: "s", cwd: "/tmp")
    let data = try WireCodec.encode(e)
    #expect(data.last == UInt8(ascii: "\n"))
    #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
}

@Test func eventSurvivesARoundTrip() throws {
    let e = VibeEvent(
        id: "uuid", cli: "claude-code", kind: .permission,
        session: "abc123", cwd: "/Users/me/dev/api",
        worktree: "auth-hardening", model: "Opus 4.8", effort: "high",
        title: "Bash command", body: "rm -rf build/",
        choices: [Choice(id: "allow", label: "Allow once"),
                  Choice(id: "deny", label: "Deny")],
        multi: false, wantsReply: true,
        tasks: [TaskItem(title: "Audit auth flow", status: .doing)],
        agents: [AgentItem(name: "Explore", elapsed: "8s", model: "Sonnet 4.6 · High",
                           activity: "Grep: handleRequest")],
        origin: Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0:UUID"))

    let back = try WireCodec.decode(VibeEvent.self, from: WireCodec.encode(e))
    #expect(back == e)
}

@Test func replySurvivesARoundTrip() throws {
    let r = Reply(id: "uuid", choices: ["a", "b"])
    let back = try WireCodec.decode(Reply.self, from: WireCodec.encode(r))
    #expect(back == r)
}

@Test func splitLinesReturnsCompleteLinesAndKeepsTheRemainder() {
    var buf = Data(#"{"a":1}"#.utf8) + Data("\n".utf8)
             + Data(#"{"b":2}"#.utf8) + Data("\n".utf8)
             + Data(#"{"partial"#.utf8)
    let lines = WireCodec.splitLines(&buf)
    #expect(lines.count == 2)
    #expect(String(decoding: lines[0], as: UTF8.self) == #"{"a":1}"#)
    #expect(String(decoding: buf, as: UTF8.self) == #"{"partial"#)
}

@Test func splitLinesOnAnEmptyBufferReturnsNothing() {
    var buf = Data()
    #expect(WireCodec.splitLines(&buf).isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WireCodecTests`
Expected: FAIL — `cannot find 'WireCodec' in scope`.

- [ ] **Step 3: Write the codec**

Create `Sources/VibeCatCore/WireCodec.swift`:

```swift
import Foundation

/// Newline-delimited JSON. One message per line, so a reader can frame a stream
/// without a length prefix and a human can read the traffic in a log.
public enum WireCodec {
    static let newline = UInt8(ascii: "\n")

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        // Sorted keys make encoded output stable, which makes tests and logs readable.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(newline)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let line = data.last == newline ? data.dropLast() : data[...]
        return try JSONDecoder().decode(type, from: Data(line))
    }

    /// Pulls every complete line out of `buffer`, leaving any partial tail behind
    /// for the next read. Blank lines are skipped: every caller decodes what this
    /// returns, and an empty line would only ever be a decode error.
    public static func splitLines(_ buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let idx = buffer.firstIndex(of: newline) {
            let line = Data(buffer[buffer.startIndex..<idx])
            buffer = Data(buffer[buffer.index(after: idx)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WireCodecTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/WireCodec.swift Tests/VibeCatCoreTests/WireCodecTests.swift
git commit -m "feat(core): add the newline-delimited JSON wire codec"
```

---

### Task 3: Session state and the priority rule

**Files:**
- Create: `Sources/VibeCatCore/SessionState.swift`
- Test: `Tests/VibeCatCoreTests/SessionStateTests.swift`

**Interfaces:**
- Consumes: `Kind` (Task 1)
- Produces: `enum SessionState: String, Codable, Sendable, CaseIterable` with cases
  `idle, running, waiting, failed`; `var urgency: Int`;
  `static func mostUrgent(_ states: [SessionState]) -> SessionState?`;
  `init(kind: Kind)`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/SessionStateTests.swift`:

```swift
import Testing
@testable import VibeCatCore

@Test func waitingOutranksFailed() {
    // A waiting agent is idling on you right now; a failed one has already stopped.
    #expect(SessionState.mostUrgent([.failed, .waiting]) == .waiting)
}

@Test func theWholeOrderingHolds() {
    #expect(SessionState.mostUrgent([.idle, .running, .failed, .waiting]) == .waiting)
    #expect(SessionState.mostUrgent([.idle, .running, .failed]) == .failed)
    #expect(SessionState.mostUrgent([.idle, .running]) == .running)
    #expect(SessionState.mostUrgent([.idle]) == .idle)
}

@Test func mostUrgentOfNothingIsNil() {
    #expect(SessionState.mostUrgent([]) == nil)
}

@Test func kindsMapOntoStates() {
    #expect(SessionState(kind: .permission) == .waiting)
    #expect(SessionState(kind: .question)   == .waiting)
    #expect(SessionState(kind: .running)    == .running)
    #expect(SessionState(kind: .failed)     == .failed)
    #expect(SessionState(kind: .done)       == .idle)
    #expect(SessionState(kind: .idle)       == .idle)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionStateTests`
Expected: FAIL — `cannot find 'SessionState' in scope`.

- [ ] **Step 3: Write the state type**

Create `Sources/VibeCatCore/SessionState.swift`:

```swift
public enum SessionState: String, Codable, Sendable, CaseIterable {
    case idle, running, waiting, failed

    /// Lower is more urgent. `waiting` beats `failed` because a waiting agent is
    /// idling on you right now, while a failed one has already stopped.
    public var urgency: Int {
        switch self {
        case .waiting: 0
        case .failed:  1
        case .running: 2
        case .idle:    3
        }
    }

    public static func mostUrgent(_ states: [SessionState]) -> SessionState? {
        states.min { $0.urgency < $1.urgency }
    }

    public init(kind: Kind) {
        switch kind {
        case .permission, .question: self = .waiting
        case .running:               self = .running
        case .failed:                self = .failed
        case .done, .idle:           self = .idle
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionStateTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/SessionState.swift Tests/VibeCatCoreTests/SessionStateTests.swift
git commit -m "feat(core): add session state and the worst-state-wins rule"
```

---

### Task 4: The Session model

**Files:**
- Create: `Sources/VibeCatCore/Session.swift`
- Test: `Tests/VibeCatCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `VibeEvent`, `Origin`, `TaskItem`, `AgentItem` (Task 1), `SessionState` (Task 3)
- Produces: `struct SessionKey: Hashable, Sendable` with `cli: String`, `session: String`;
  `struct Session: Identifiable, Sendable, Equatable` with `id: SessionKey`, `project: String`,
  `state`, `activity`, `lastUserMessage`, `tasks`, `agents`, `origin`, `startedAt`, `updatedAt`,
  and `init(event:now:)` plus `mutating func merge(_ event: VibeEvent, now: Date)`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/SessionTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, cwd: String = "/Users/me/dev/api",
                   title: String? = nil, body: String? = nil) -> VibeEvent {
    VibeEvent(id: "e", cli: "claude-code", kind: kind,
              session: "s1", cwd: cwd, title: title, body: body)
}

@Test func projectIsTheLastPathComponentOfCwd() {
    let s = Session(event: event(.running), now: t0)
    #expect(s.project == "api")
}

@Test func identityIsCliPlusSessionId() {
    let s = Session(event: event(.running), now: t0)
    #expect(s.id == SessionKey(cli: "claude-code", session: "s1"))
}

@Test func mergeAdvancesStateAndTimestamp() {
    var s = Session(event: event(.running), now: t0)
    s.merge(event(.permission), now: t0.addingTimeInterval(30))
    #expect(s.state == .waiting)
    #expect(s.updatedAt == t0.addingTimeInterval(30))
    #expect(s.startedAt == t0)          // start time is never rewritten
}

@Test func activityCombinesTitleAndBody() {
    let s = Session(event: event(.permission, title: "Asking to run", body: "rm -rf build/"),
                    now: t0)
    #expect(s.activity == "Asking to run rm -rf build/")
}

@Test func mergeKeepsTasksWhenAnEventOmitsThem() {
    var e = event(.running)
    e.tasks = [TaskItem(title: "Audit auth flow", status: .doing)]
    var s = Session(event: e, now: t0)
    s.merge(event(.running), now: t0.addingTimeInterval(1))   // no tasks on this event
    #expect(s.tasks.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionTests`
Expected: FAIL — `cannot find 'Session' in scope`.

- [ ] **Step 3: Write the model**

Create `Sources/VibeCatCore/Session.swift`:

```swift
import Foundation

public struct SessionKey: Hashable, Sendable {
    public let cli: String
    public let session: String
    public init(cli: String, session: String) {
        self.cli = cli
        self.session = session
    }
}

public struct Session: Identifiable, Sendable, Equatable {
    public let id: SessionKey
    public var cli: String
    public var cwd: String
    public var project: String
    public var worktree: String?
    public var model: String?
    public var effort: String?
    public var state: SessionState
    public var activity: String?
    public var lastUserMessage: String?
    public var tasks: [TaskItem]
    public var agents: [AgentItem]
    public var origin: Origin
    public var startedAt: Date
    public var updatedAt: Date

    public init(event: VibeEvent, now: Date) {
        id = SessionKey(cli: event.cli, session: event.session)
        cli = event.cli
        cwd = event.cwd
        project = Session.project(from: event.cwd)
        worktree = event.worktree
        model = event.model
        effort = event.effort
        state = SessionState(kind: event.kind)
        activity = Session.activity(from: event)
        lastUserMessage = nil
        tasks = event.tasks ?? []
        agents = event.agents ?? []
        origin = event.origin
        startedAt = now
        updatedAt = now
    }

    /// An event carries only what changed, so anything it omits is left alone.
    public mutating func merge(_ event: VibeEvent, now: Date) {
        cwd = event.cwd
        project = Session.project(from: event.cwd)
        if let w = event.worktree { worktree = w }
        if let m = event.model { model = m }
        if let e = event.effort { effort = e }
        state = SessionState(kind: event.kind)
        if let a = Session.activity(from: event) { activity = a }
        if let t = event.tasks { tasks = t }
        if let g = event.agents { agents = g }
        origin = event.origin
        updatedAt = now
    }

    static func project(from cwd: String) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    static func activity(from event: VibeEvent) -> String? {
        switch (event.title, event.body) {
        case let (title?, body?): "\(title) \(body)"
        case let (title?, nil):   title
        case let (nil, body?):    body
        default:                  nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/Session.swift Tests/VibeCatCoreTests/SessionTests.swift
git commit -m "feat(core): add the session model"
```

---

### Task 5: SessionStore — upsert, aggregate, counts, pruning

**Files:**
- Create: `Sources/VibeCatCore/SessionStore.swift`
- Test: `Tests/VibeCatCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `Session`, `SessionKey` (Task 4), `SessionState` (Task 3), `VibeEvent` (Task 1)
- Produces: `struct SessionStore: Sendable, Equatable` with
  `var sessions: [Session]` (get-only), `init()`,
  `mutating func apply(_ event: VibeEvent, now: Date)`,
  `var aggregate: SessionState`, `var counts: [SessionState: Int]`,
  `mutating func prune(idleFor: TimeInterval, now: Date)`

`now` is always injected so tests are deterministic — never call `Date()` inside the store.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/SessionStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

private func event(_ kind: Kind, session: String, cli: String = "claude-code") -> VibeEvent {
    VibeEvent(id: "e-\(session)", cli: cli, kind: kind, session: session, cwd: "/dev/\(session)")
}

@Test func applyInsertsThenUpdatesInPlace() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.permission, session: "a"), now: t0.addingTimeInterval(5))
    #expect(store.sessions.count == 1)
    #expect(store.sessions[0].state == .waiting)
}

@Test func sameSessionIdOnDifferentCliIsADifferentSession() {
    var store = SessionStore()
    store.apply(event(.running, session: "a", cli: "claude-code"), now: t0)
    store.apply(event(.running, session: "a", cli: "codex"), now: t0)
    #expect(store.sessions.count == 2)
}

@Test func aggregateTakesTheMostUrgentSession() {
    var store = SessionStore()
    store.apply(event(.running, session: "a"), now: t0)
    store.apply(event(.failed, session: "b"), now: t0)
    store.apply(event(.permission, session: "c"), now: t0)
    #expect(store.aggregate == .waiting)
}

@Test func aggregateOfAnEmptyStoreIsIdle() {
    #expect(SessionStore().aggregate == .idle)
}

@Test func countsGroupByState() {
    var store = SessionStore()
    store.apply(event(.permission, session: "a"), now: t0)
    store.apply(event(.running, session: "b"), now: t0)
    store.apply(event(.running, session: "c"), now: t0)
    #expect(store.counts[.waiting] == 1)
    #expect(store.counts[.running] == 2)
    #expect(store.counts[.failed] == nil)
}

@Test func pruneDropsStaleIdleSessionsOnly() {
    var store = SessionStore()
    store.apply(event(.done, session: "old"), now: t0)
    store.apply(event(.permission, session: "waiting"), now: t0)
    store.apply(event(.running, session: "busy"), now: t0)

    store.prune(idleFor: 3600, now: t0.addingTimeInterval(7200))

    let ids = store.sessions.map(\.id.session).sorted()
    #expect(ids == ["busy", "waiting"])   // a stale session that still needs you is kept
}

@Test func pruneKeepsRecentIdleSessions() {
    var store = SessionStore()
    store.apply(event(.done, session: "recent"), now: t0)
    store.prune(idleFor: 3600, now: t0.addingTimeInterval(60))
    #expect(store.sessions.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionStoreTests`
Expected: FAIL — `cannot find 'SessionStore' in scope`.

- [ ] **Step 3: Write the store**

Create `Sources/VibeCatCore/SessionStore.swift`:

```swift
import Foundation

/// A value type on purpose: the app can hold one in an `@Observable` box and the
/// tests can drive it with no concurrency at all.
public struct SessionStore: Sendable, Equatable {
    public private(set) var sessions: [Session] = []

    public init() {}

    public mutating func apply(_ event: VibeEvent, now: Date) {
        let key = SessionKey(cli: event.cli, session: event.session)
        if let i = sessions.firstIndex(where: { $0.id == key }) {
            sessions[i].merge(event, now: now)
        } else {
            sessions.append(Session(event: event, now: now))
        }
    }

    /// The island reports the most urgent session, not the most common one.
    public var aggregate: SessionState {
        SessionState.mostUrgent(sessions.map(\.state)) ?? .idle
    }

    public var counts: [SessionState: Int] {
        Dictionary(grouping: sessions, by: \.state).mapValues(\.count)
    }

    /// Only sessions that are finished *and* stale go away. Anything still
    /// running, or still waiting on you, stays however old it is.
    public mutating func prune(idleFor: TimeInterval, now: Date) {
        sessions.removeAll { session in
            session.state == .idle && now.timeIntervalSince(session.updatedAt) > idleFor
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionStoreTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/SessionStore.swift Tests/VibeCatCoreTests/SessionStoreTests.swift
git commit -m "feat(core): add the session store with aggregate state and pruning"
```

---

### Task 6: SourceAdapter protocol and registry

**Files:**
- Create: `Sources/VibeCatCore/SourceAdapter.swift`
- Test: `Tests/VibeCatCoreTests/SourceRegistryTests.swift`

**Interfaces:**
- Consumes: `VibeEvent`, `Kind` (Task 1)
- Produces: `enum JumpStrategy: Sendable, Equatable` with `.terminalSession`,
  `.activateApp(bundleID: String)`, `.vscode`, `.none`;
  `protocol SourceAdapter: Sendable` with `var id: String`, `var displayName: String`,
  `var jumpStrategy: JumpStrategy`, `var reports: Set<Kind>`,
  `func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent?`;
  `struct SourceRegistry: Sendable` with `init(adapters:)`, `func adapter(for id: String) -> (any SourceAdapter)?`,
  `var ids: [String]`;
  `enum AdapterError: Error, Equatable` with `.missingField(String)`, `.unknownEvent(String)`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/SourceRegistryTests.swift`:

```swift
import Testing
@testable import VibeCatCore

private struct StubAdapter: SourceAdapter {
    let id = "stub"
    let displayName = "Stub"
    let jumpStrategy = JumpStrategy.activateApp(bundleID: "com.example.stub")
    let reports: Set<Kind> = [.running, .done]
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? { nil }
}

@Test func registryFindsAnAdapterById() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.adapter(for: "stub")?.displayName == "Stub")
}

@Test func registryReturnsNilForAnUnknownId() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.adapter(for: "nope") == nil)
}

@Test func registryListsItsIds() {
    let r = SourceRegistry(adapters: [StubAdapter()])
    #expect(r.ids == ["stub"])
}

@Test func jumpStrategyComparesByAssociatedValue() {
    #expect(JumpStrategy.activateApp(bundleID: "a") != .activateApp(bundleID: "b"))
    #expect(JumpStrategy.terminalSession == .terminalSession)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceRegistryTests`
Expected: FAIL — `cannot find type 'SourceAdapter' in scope`.

- [ ] **Step 3: Write the protocol and registry**

Create `Sources/VibeCatCore/SourceAdapter.swift`:

```swift
import Foundation

public enum JumpStrategy: Sendable, Equatable {
    case terminalSession
    case activateApp(bundleID: String)
    case vscode
    case none
}

public enum AdapterError: Error, Equatable {
    case missingField(String)
    case unknownEvent(String)
}

/// A source is configuration, not code: the differences between CLIs live in
/// `parse` and `jumpStrategy`, and nothing above this line learns their names.
public protocol SourceAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var jumpStrategy: JumpStrategy { get }
    /// Which kinds this source is allowed to raise. Settings narrows this.
    var reports: Set<Kind> { get }

    /// Returns nil when the raw payload is a well-formed event this adapter
    /// deliberately ignores.
    func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent?
}

public struct SourceRegistry: Sendable {
    private let byID: [String: any SourceAdapter]

    /// Later adapters win on a duplicate id, so a user's custom source can
    /// deliberately override a built-in preset. Never traps: a duplicate id is
    /// user input, and Settings can produce one.
    public init(adapters: [any SourceAdapter]) {
        byID = Dictionary(adapters.map { ($0.id, $0) },
                          uniquingKeysWith: { _, later in later })
    }

    public func adapter(for id: String) -> (any SourceAdapter)? { byID[id] }

    public var ids: [String] { byID.keys.sorted() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SourceRegistryTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/SourceAdapter.swift Tests/VibeCatCoreTests/SourceRegistryTests.swift
git commit -m "feat(core): add the source adapter protocol and registry"
```

---

### Task 7: Claude Code adapter

**Files:**
- Create: `Sources/VibeCatCore/Adapters/ClaudeCodeAdapter.swift`
- Test: `Tests/VibeCatCoreTests/ClaudeCodeAdapterTests.swift`

**Interfaces:**
- Consumes: `SourceAdapter`, `AdapterError`, `JumpStrategy` (Task 6), `VibeEvent`, `Kind`, `Choice`, `Origin` (Task 1)
- Produces: `struct ClaudeCodeAdapter: SourceAdapter` with `id == "claude-code"`

Claude Code passes its hook a JSON object on stdin containing at least
`hook_event_name`, `session_id` and `cwd`. `PreToolUse` adds `tool_name` and
`tool_input`; `Notification` adds `message`; `Stop` means the turn finished.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/ClaudeCodeAdapterTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatCore

private let adapter = ClaudeCodeAdapter()
private let origin = Origin(app: "com.googlecode.iterm2", termSession: "w0t1p0")

private func raw(_ json: String) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

@Test func preToolUseBecomesAPermissionThatWantsAReply() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
      """), origin: origin))

    #expect(e.cli == "claude-code")
    #expect(e.kind == .permission)
    #expect(e.session == "s1")
    #expect(e.title == "Bash")
    #expect(e.body == "rm -rf build/")
    #expect(e.wantsReply == true)
    #expect(e.multi == false)
    #expect(e.choices?.map(\.id) == ["allow", "always", "deny"])
    #expect(e.origin == origin)
}

@Test func stopBecomesDoneAndWantsNoReply() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Stop","session_id":"s1","cwd":"/Users/me/dev/api"}
      """), origin: origin))
    #expect(e.kind == .done)
    #expect(e.wantsReply == false)
}

@Test func notificationBecomesAQuestion() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Notification","session_id":"s1","cwd":"/dev/api",
       "message":"Claude needs your permission"}
      """), origin: origin))
    #expect(e.kind == .question)
    #expect(e.body == "Claude needs your permission")
}

@Test func modelAndEffortAreCarriedWhenPresent() throws {
    let e = try #require(try adapter.parse(raw("""
      {"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api",
       "model":"Opus 4.8","reasoning_effort":"high"}
      """), origin: origin))
    #expect(e.model == "Opus 4.8")
    #expect(e.effort == "high")
}

@Test func aMissingSessionIdIsAnError() {
    #expect(throws: AdapterError.missingField("session_id")) {
        _ = try adapter.parse(try raw(#"{"hook_event_name":"Stop","cwd":"/dev/api"}"#),
                              origin: origin)
    }
}

@Test func anUnhandledHookIsIgnoredRatherThanFatal() throws {
    let e = try adapter.parse(raw("""
      {"hook_event_name":"SessionStart","session_id":"s1","cwd":"/dev/api"}
      """), origin: origin)
    #expect(e == nil)
}

@Test func everyEventCarriesAUniqueId() throws {
    let a = try #require(try adapter.parse(raw(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/d"}"#), origin: origin))
    let b = try #require(try adapter.parse(raw(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/d"}"#), origin: origin))
    #expect(a.id != b.id)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeCodeAdapterTests`
Expected: FAIL — `cannot find 'ClaudeCodeAdapter' in scope`.

- [ ] **Step 3: Write the adapter**

Create `Sources/VibeCatCore/Adapters/ClaudeCodeAdapter.swift`:

```swift
import Foundation

public struct ClaudeCodeAdapter: SourceAdapter {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let jumpStrategy = JumpStrategy.terminalSession
    public let reports: Set<Kind> = [.running, .done, .permission, .question, .failed]

    public init() {}

    public func parse(_ raw: [String: Any], origin: Origin) throws -> VibeEvent? {
        guard let hook = raw["hook_event_name"] as? String else {
            throw AdapterError.missingField("hook_event_name")
        }
        guard let session = raw["session_id"] as? String else {
            throw AdapterError.missingField("session_id")
        }
        guard let cwd = raw["cwd"] as? String else {
            throw AdapterError.missingField("cwd")
        }

        var event = VibeEvent(
            id: UUID().uuidString,
            cli: id,
            kind: .running,
            session: session,
            cwd: cwd,
            model: raw["model"] as? String,
            effort: raw["reasoning_effort"] as? String,
            origin: origin)

        switch hook {
        case "PreToolUse":
            event.kind = .permission
            event.title = raw["tool_name"] as? String
            event.body = Self.command(from: raw["tool_input"])
            event.wantsReply = true
            event.choices = [
                Choice(id: "allow",  label: "Allow once"),
                Choice(id: "always", label: "Allow every \(raw["tool_name"] as? String ?? "tool") call this session"),
                Choice(id: "deny",   label: "Deny"),
            ]

        case "PostToolUse":
            // The tool has run and the agent is thinking again. Without this the
            // session would stay .waiting for the whole tool execution, and the
            // island would falsely say "needs you" through every tool call.
            event.kind = .running

        case "Notification":
            event.kind = .question
            event.body = raw["message"] as? String

        case "Stop":
            event.kind = .done

        case "SubagentStop":
            event.kind = .running

        default:
            // A hook we deliberately do not surface. Not an error.
            return nil
        }

        return event
    }

    /// `tool_input` is shaped differently per tool. Try the keys that carry the
    /// useful detail, then fall back to any string in the payload — a prompt that
    /// names a tool but shows nothing leaves the user approving blind.
    static func command(from toolInput: Any?) -> String? {
        guard let dict = toolInput as? [String: Any] else { return nil }
        let preferred = ["command", "file_path", "pattern", "url", "query",
                         "prompt", "notebook_path", "path"]
        for key in preferred {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        // Deterministic order so the same payload always renders the same way.
        return dict.keys.sorted()
            .compactMap { dict[$0] as? String }
            .first { !$0.isEmpty }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeCodeAdapterTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/Adapters/ClaudeCodeAdapter.swift Tests/VibeCatCoreTests/ClaudeCodeAdapterTests.swift
git commit -m "feat(core): add the Claude Code adapter"
```

---

### Task 8: Socket path resolution

**Files:**
- Create: `Sources/VibeCatCore/SocketPath.swift`
- Test: `Tests/VibeCatCoreTests/SocketPathTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum SocketPath` with
  `static var `default`: String`,
  `static func resolve(env: [String: String], home: String) -> String`
  (honours `VIBECAT_SOCKET` so tests and the hook can be pointed at a temp path)

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/SocketPathTests.swift`:

```swift
import Testing
@testable import VibeCatCore

@Test func defaultsToApplicationSupport() {
    let p = SocketPath.resolve(env: [:], home: "/Users/me")
    #expect(p == "/Users/me/Library/Application Support/VibeCat/vibecat.sock")
}

@Test func environmentOverrideWins() {
    let p = SocketPath.resolve(env: ["VIBECAT_SOCKET": "/tmp/x.sock"], home: "/Users/me")
    #expect(p == "/tmp/x.sock")
}

@Test func anEmptyOverrideIsIgnored() {
    let p = SocketPath.resolve(env: ["VIBECAT_SOCKET": ""], home: "/Users/me")
    #expect(p == "/Users/me/Library/Application Support/VibeCat/vibecat.sock")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SocketPathTests`
Expected: FAIL — `cannot find 'SocketPath' in scope`.

- [ ] **Step 3: Write it**

Create `Sources/VibeCatCore/SocketPath.swift`:

```swift
import Foundation

public enum SocketPath {
    public static let overrideKey = "VIBECAT_SOCKET"

    public static func resolve(env: [String: String], home: String) -> String {
        if let override = env[overrideKey], !override.isEmpty { return override }
        return "\(home)/Library/Application Support/VibeCat/vibecat.sock"
    }

    public static var `default`: String {
        resolve(env: ProcessInfo.processInfo.environment,
                home: NSHomeDirectory())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SocketPathTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/SocketPath.swift Tests/VibeCatCoreTests/SocketPathTests.swift
git commit -m "feat(core): resolve the socket path with an env override"
```

---

### Task 9: POSIX socket address helper

**Files:**
- Create: `Sources/VibeCatTransport/UnixAddress.swift`
- Test: `Tests/VibeCatTransportTests/UnixAddressTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `enum SocketError: Error, Equatable` with `.pathTooLong`, `.socketFailed(Int32)`,
  `.bindFailed(Int32)`, `.listenFailed(Int32)`, `.connectFailed(Int32)`, `.timedOut`;
  `enum UnixAddress` with `static func make(_ path: String) throws -> sockaddr_un`
  and `static func withSockaddr<R>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R`

`sockaddr_un.sun_path` is a fixed C array; Swift needs a memory rebind to write it. This is isolated in its own task because it is the one piece of the transport that is easy to get subtly wrong.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatTransportTests/UnixAddressTests.swift`:

```swift
import Testing
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import VibeCatTransport

@Test func addressRoundTripsThePath() throws {
    var addr = try UnixAddress.make("/tmp/vibecat-test.sock")
    // Hoisted deliberately: reading addr.sun_path inside the closure would
    // overlap the exclusive access withUnsafePointer(to: &…) already holds,
    // which Swift 6 rejects. Same reason UnixAddress.make hoists it.
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    let read = withUnsafePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
            String(cString: $0)
        }
    }
    #expect(read == "/tmp/vibecat-test.sock")
    #expect(addr.sun_family == sa_family_t(AF_UNIX))
}

@Test func anOverlongPathIsRejectedRatherThanTruncated() {
    let tooLong = "/tmp/" + String(repeating: "x", count: 200) + ".sock"
    #expect(throws: SocketError.pathTooLong) {
        _ = try UnixAddress.make(tooLong)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UnixAddressTests`
Expected: FAIL — `no such module 'VibeCatTransport'` or `cannot find 'UnixAddress'`.

- [ ] **Step 3: Write the helper**

Create `Sources/VibeCatTransport/UnixAddress.swift`:

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum SocketError: Error, Equatable {
    case pathTooLong
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case timedOut
}

public enum UnixAddress {
    public static func make(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        // Need room for the trailing NUL.
        guard bytes.count < capacity else { throw SocketError.pathTooLong }

        withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                for (i, byte) in bytes.enumerated() {
                    dst[i] = CChar(bitPattern: byte)
                }
                dst[bytes.count] = 0
            }
        }
        return addr
    }

    /// `connect` and `bind` want a `sockaddr *`; this does the rebind in one place.
    public static func withSockaddr<R>(_ addr: inout sockaddr_un,
                                       _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UnixAddressTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatTransport/UnixAddress.swift Tests/VibeCatTransportTests/UnixAddressTests.swift
git commit -m "feat(transport): add the AF_UNIX address helper"
```

---

### Task 10: SocketClient — send, wait, fail open

**Files:**
- Create: `Sources/VibeCatTransport/SocketClient.swift`
- Test: `Tests/VibeCatTransportTests/SocketClientTests.swift`

**Interfaces:**
- Consumes: `UnixAddress`, `SocketError` (Task 9)
- Produces: `struct SocketClient: Sendable` with
  `init(path: String, deadline: TimeInterval = 0.3)`,
  `func sendExpectingReply(_ line: Data) -> Data?`,
  `func send(_ line: Data)`

`sendExpectingReply` **never throws**. Every failure path returns `nil`, because a
crashed island must not be able to hang a terminal.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatTransportTests/SocketClientTests.swift`:

```swift
import Foundation
import Testing
@testable import VibeCatTransport

private func tempSocketPath(_ name: String) -> String {
    "/tmp/vibecat-\(name)-\(getpid()).sock"
}

@Test func missingSocketFailsOpenRatherThanThrowing() {
    let client = SocketClient(path: tempSocketPath("absent"), deadline: 0.1)
    #expect(client.sendExpectingReply(Data("{}\n".utf8)) == nil)
}

@Test func sendWithoutAReplyIsSafeWhenNobodyIsListening() {
    let client = SocketClient(path: tempSocketPath("absent2"), deadline: 0.1)
    client.send(Data("{}\n".utf8))   // must not crash or hang
}

@Test func aServerThatNeverAnswersHitsTheDeadline() async throws {
    let path = tempSocketPath("silent")
    let server = try SilentServer(path: path)
    defer { server.stop() }

    let started = Date()
    let client = SocketClient(path: path, deadline: 0.2)
    let reply = client.sendExpectingReply(Data("{}\n".utf8))

    #expect(reply == nil)
    #expect(Date().timeIntervalSince(started) < 1.0)   // gave up promptly
}
```

Add the test double in the same file:

```swift
/// Accepts a connection and then says nothing, to exercise the deadline.
private final class SilentServer: @unchecked Sendable {
    private let fd: Int32
    private let path: String
    private var running = true

    init(path: String) throws {
        self.path = path
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try UnixAddress.make(path)
        _ = UnixAddress.withSockaddr(&addr) { bind(fd, $0, $1) }
        listen(fd, 4)
        Thread.detachNewThread { [fd] in
            while self.running {
                let c = accept(fd, nil, nil)
                if c >= 0 { Thread.sleep(forTimeInterval: 2); close(c) }
            }
        }
    }

    func stop() {
        running = false
        close(fd)
        unlink(path)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SocketClientTests`
Expected: FAIL — `cannot find 'SocketClient' in scope`.

- [ ] **Step 3: Write the client**

Create `Sources/VibeCatTransport/SocketClient.swift`:

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The hook side of the socket. Deliberately blocking and deliberately
/// infallible: every error path returns nil so the calling CLI carries on.
public struct SocketClient: Sendable {
    public let path: String
    public let deadline: TimeInterval

    public init(path: String, deadline: TimeInterval = 0.3) {
        self.path = path
        self.deadline = deadline
    }

    public func send(_ line: Data) {
        guard let fd = connectSocket() else { return }
        defer { close(fd) }
        _ = writeAll(fd, line)
    }

    public func sendExpectingReply(_ line: Data) -> Data? {
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        guard writeAll(fd, line) else { return nil }
        return readLine(fd)
    }

    // MARK: - plumbing

    private func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        guard var addr = try? UnixAddress.make(path) else {
            close(fd)
            return nil
        }
        setTimeout(fd, SO_SNDTIMEO)
        setTimeout(fd, SO_RCVTIMEO)

        let rc = UnixAddress.withSockaddr(&addr) { connect(fd, $0, $1) }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private func setTimeout(_ fd: Int32, _ option: Int32) {
        var tv = timeval(tv_sec: Int(deadline),
                         tv_usec: Int32((deadline - floor(deadline)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var sent = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return false }
            while sent < data.count {
                let n = write(fd, base.advanced(by: sent), data.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Reads until the first newline or the socket timeout, whichever comes first.
    private func readLine(_ fd: Int32) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return buffer.isEmpty ? nil : buffer }
            buffer.append(contentsOf: chunk[0..<n])
            if let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return Data(buffer[buffer.startIndex..<idx])
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SocketClientTests`
Expected: PASS, 3 tests. The deadline test should finish in well under a second.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatTransport/SocketClient.swift Tests/VibeCatTransportTests/SocketClientTests.swift
git commit -m "feat(transport): add a fail-open socket client"
```

---

### Task 11: SocketServer — listen, dispatch, reply

**Files:**
- Create: `Sources/VibeCatTransport/SocketServer.swift`
- Test: `Tests/VibeCatTransportTests/SocketServerTests.swift`

**Interfaces:**
- Consumes: `UnixAddress`, `SocketError` (Task 9), `SocketClient` (Task 10), `WireCodec`, `VibeEvent`, `Reply` (Tasks 1–2)
- Produces: `final class SocketServer: @unchecked Sendable` with
  `init(path: String)`,
  `func start(handler: @escaping @Sendable (VibeEvent) -> Reply?) throws`,
  `func stop()`

The server creates its parent directory, removes any stale socket file, and
`chmod`s the socket to `0600`.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatTransportTests/SocketServerTests.swift`:

```swift
import Foundation
import Testing
import VibeCatCore
@testable import VibeCatTransport

private func tempPath(_ name: String) -> String {
    "/tmp/vibecat-srv-\(name)-\(getpid()).sock"
}

private func sampleEvent(wantsReply: Bool) -> VibeEvent {
    VibeEvent(id: "e1", cli: "claude-code", kind: .permission,
              session: "s1", cwd: "/dev/api", wantsReply: wantsReply)
}

@Test func serverDeliversAnEventToTheHandler() async throws {
    let path = tempPath("deliver")
    let server = SocketServer(path: path)
    let box = Box<VibeEvent?>(nil)
    try server.start { event in box.set(event); return nil }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    client.send(try WireCodec.encode(sampleEvent(wantsReply: false)))

    try await waitUntil { box.get() != nil }
    #expect(box.get()?.session == "s1")
}

@Test func serverWritesTheHandlersReplyBack() async throws {
    let path = tempPath("reply")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "allow") }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    let raw = try #require(client.sendExpectingReply(try WireCodec.encode(sampleEvent(wantsReply: true))))
    let reply = try WireCodec.decode(Reply.self, from: raw)

    #expect(reply.id == "e1")
    #expect(reply.choice == "allow")
}

@Test func theSocketFileIsOwnerOnly() throws {
    let path = tempPath("perms")
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    defer { server.stop() }

    let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber
    #expect(mode.int16Value == 0o600)
}

@Test func startingOverAStaleSocketFileSucceeds() throws {
    let path = tempPath("stale")
    FileManager.default.createFile(atPath: path, contents: Data())
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    server.stop()
}

// MARK: - helpers

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: T) { lock.lock(); value = new; lock.unlock() }
}

private func waitUntil(timeout: TimeInterval = 2,
                       _ condition: @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("condition never became true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SocketServerTests`
Expected: FAIL — `cannot find 'SocketServer' in scope`.

- [ ] **Step 3: Write the server**

Create `Sources/VibeCatTransport/SocketServer.swift`:

```swift
import Foundation
import VibeCatCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One thread accepts, one thread per connection reads a single line and
/// answers it. Connections are short-lived — a hook sends one event and leaves.
public final class SocketServer: @unchecked Sendable {
    public let path: String
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var running = false

    public init(path: String) {
        self.path = path
    }

    public func start(handler: @escaping @Sendable (VibeEvent) -> Reply?) throws {
        try prepareDirectory()
        unlink(path)                                  // clear any stale socket file

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.socketFailed(errno) }

        var addr = try UnixAddress.make(path)
        guard UnixAddress.withSockaddr(&addr, { bind(fd, $0, $1) }) == 0 else {
            let e = errno; close(fd); throw SocketError.bindFailed(e)
        }
        guard listen(fd, 16) == 0 else {
            let e = errno; close(fd); throw SocketError.listenFailed(e)
        }
        chmod(path, 0o600)                            // owner only

        lock.lock(); listenFD = fd; running = true; lock.unlock()

        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(fd: fd, handler: handler)
        }
    }

    public func stop() {
        lock.lock()
        running = false
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
        unlink(path)
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }; return running
    }

    private func prepareDirectory() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir,
                                                withIntermediateDirectories: true)
    }

    private func acceptLoop(fd: Int32, handler: @escaping @Sendable (VibeEvent) -> Reply?) {
        while isRunning {
            let conn = accept(fd, nil, nil)
            if conn < 0 {
                if isRunning && errno == EINTR { continue }
                return
            }
            Thread.detachNewThread { Self.serve(conn: conn, handler: handler) }
        }
    }

    private static func serve(conn: Int32, handler: @Sendable (VibeEvent) -> Reply?) {
        defer { close(conn) }
        guard let line = readLine(conn),
              let event = try? WireCodec.decode(VibeEvent.self, from: line) else { return }

        guard let reply = handler(event), event.wantsReply,
              let out = try? WireCodec.encode(reply) else { return }

        _ = out.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            var sent = 0
            while sent < out.count {
                let n = write(conn, base.advanced(by: sent), out.count - sent)
                if n <= 0 { break }
                sent += n
            }
            return sent
        }
    }

    private static func readLine(_ fd: Int32) -> Data? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return buffer.isEmpty ? nil : buffer }
            buffer.append(contentsOf: chunk[0..<n])
            if let idx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                return Data(buffer[buffer.startIndex..<idx])
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SocketServerTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatTransport/SocketServer.swift Tests/VibeCatTransportTests/SocketServerTests.swift
git commit -m "feat(transport): add the socket server with owner-only permissions"
```

---

### Task 12: Origin capture from the environment

**Files:**
- Create: `Sources/VibeCatCore/OriginReader.swift`
- Test: `Tests/VibeCatCoreTests/OriginReaderTests.swift`

**Interfaces:**
- Consumes: `Origin` (Task 1)
- Produces: `enum OriginReader` with `static func read(env: [String: String]) -> Origin`

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatCoreTests/OriginReaderTests.swift`:

```swift
import Testing
@testable import VibeCatCore

@Test func itermIsIdentifiedByItsBundleId() {
    let o = OriginReader.read(env: [
        "__CFBundleIdentifier": "com.googlecode.iterm2",
        "TERM_SESSION_ID": "w0t1p0:ABC",
    ])
    #expect(o.app == "com.googlecode.iterm2")
    #expect(o.termSession == "w0t1p0:ABC")
    #expect(o.vscodePid == nil)
}

@Test func termProgramIsUsedWhenNoBundleIdIsPresent() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "Apple_Terminal"])
    #expect(o.app == "com.apple.Terminal")
}

@Test func ghosttyIsRecognised() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "ghostty"])
    #expect(o.app == "com.mitchellh.ghostty")
}

@Test func vscodeCarriesItsPid() {
    let o = OriginReader.read(env: ["TERM_PROGRAM": "vscode", "VSCODE_PID": "4242"])
    #expect(o.app == "com.microsoft.VSCode")
    #expect(o.vscodePid == "4242")
}

@Test func anUnknownTerminalYieldsAnEmptyOrigin() {
    #expect(OriginReader.read(env: [:]) == Origin())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OriginReaderTests`
Expected: FAIL — `cannot find 'OriginReader' in scope`.

- [ ] **Step 3: Write it**

Create `Sources/VibeCatCore/OriginReader.swift`:

```swift
import Foundation

/// Reads where the agent is running from the hook process's own environment.
/// No event is ever read from a GUI app — the GUI is only ever a jump target.
public enum OriginReader {
    static let bundleIDsByTermProgram: [String: String] = [
        "iTerm.app":       "com.googlecode.iterm2",
        "Apple_Terminal":  "com.apple.Terminal",
        "ghostty":         "com.mitchellh.ghostty",
        "WezTerm":         "com.github.wez.wezterm",
        "Alacritty":       "org.alacritty",
        "vscode":          "com.microsoft.VSCode",
        "Hyper":           "co.zeit.hyper",
    ]

    public static func read(env: [String: String]) -> Origin {
        let app = env["__CFBundleIdentifier"]
            ?? env["TERM_PROGRAM"].flatMap { bundleIDsByTermProgram[$0] }

        return Origin(app: app,
                      termSession: env["TERM_SESSION_ID"],
                      vscodePid: env["VSCODE_PID"])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OriginReaderTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeCatCore/OriginReader.swift Tests/VibeCatCoreTests/OriginReaderTests.swift
git commit -m "feat(core): read session origin from the hook's environment"
```

---

### Task 13: The hook executable

**Files:**
- Create: `Sources/VibeCatHookKit/HookRunner.swift`
- **Overwrite:** `Sources/VibeCatHook/main.swift` — Task 1 leaves a one-line placeholder there so the executable target compiles; replace its whole contents
- Delete: `Sources/VibeCatHookKit/Placeholder.swift` — this task gives the target a real file
- Test: `Tests/VibeCatTransportTests/HookRunnerTests.swift`

**Interfaces:**
- Consumes: `ClaudeCodeAdapter` (Task 7), `OriginReader` (Task 12), `SocketPath` (Task 8), `SocketClient` (Task 10), `WireCodec` (Task 2), `SourceRegistry` (Task 6)
- Produces: `struct HookRunner` with
  `init(registry: SourceRegistry, client: SocketClient, env: [String: String])` and
  `func run(cli: String, stdin: Data) -> String?` — returns the string to print on
  stdout, or `nil` for "say nothing". **Never throws, never blocks past the deadline.**

Separating `HookRunner` into `VibeCatHookKit` is what makes the hook testable at
all — SwiftPM cannot reliably `@testable import` an executable target that has a
`main.swift`, so the executable is kept to nothing but wiring.

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatTransportTests/HookRunnerTests.swift`:

```swift
import Foundation
import Testing
import VibeCatCore
@testable import VibeCatHookKit
@testable import VibeCatTransport

private func tempPath(_ n: String) -> String { "/tmp/vibecat-hook-\(n)-\(getpid()).sock" }

private let registry = SourceRegistry(adapters: [ClaudeCodeAdapter()])
private let stopPayload = Data(#"{"hook_event_name":"Stop","session_id":"s1","cwd":"/dev/api"}"#.utf8)
private let permissionPayload = Data("""
  {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/dev/api",
   "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
  """.utf8)

@Test func withNoServerTheHookSaysNothingAndDoesNotHang() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent"), deadline: 0.1),
                            env: [:])
    let started = Date()
    #expect(runner.run(cli: "claude-code", stdin: permissionPayload) == nil)
    #expect(Date().timeIntervalSince(started) < 1.0)
}

@Test func garbageOnStdinIsIgnored() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent2"), deadline: 0.1),
                            env: [:])
    #expect(runner.run(cli: "claude-code", stdin: Data("not json".utf8)) == nil)
}

@Test func anUnknownCliIsIgnored() {
    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: tempPath("absent3"), deadline: 0.1),
                            env: [:])
    #expect(runner.run(cli: "nope", stdin: stopPayload) == nil)
}

@Test func anAllowReplyBecomesClaudeCodeDecisionJson() throws {
    let path = tempPath("allow")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "allow") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    let json = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
    let perm = json["hookSpecificOutput"] as! [String: Any]
    #expect(perm["permissionDecision"] as? String == "allow")
}

@Test func aDenyReplyBecomesADenyDecision() throws {
    let path = tempPath("deny")
    let server = SocketServer(path: path)
    try server.start { event in Reply(id: event.id, choice: "deny") }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    let out = try #require(runner.run(cli: "claude-code", stdin: permissionPayload))
    #expect(out.contains("\"permissionDecision\":\"deny\""))
}

@Test func anEventThatWantsNoReplyPrintsNothing() throws {
    let path = tempPath("noreply")
    let server = SocketServer(path: path)
    try server.start { _ in nil }
    defer { server.stop() }

    let runner = HookRunner(registry: registry,
                            client: SocketClient(path: path, deadline: 1.0),
                            env: [:])
    #expect(runner.run(cli: "claude-code", stdin: stopPayload) == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HookRunnerTests`
Expected: FAIL — `no such module 'VibeCatHookKit'` or `cannot find 'HookRunner'`.

- [ ] **Step 3: Write the runner**

Create `Sources/VibeCatHookKit/HookRunner.swift`:

```swift
import Foundation
import VibeCatCore
import VibeCatTransport

/// Everything the hook does except touching stdin, stdout and the process exit
/// code — which is what makes it testable.
public struct HookRunner {
    let registry: SourceRegistry
    let client: SocketClient
    let env: [String: String]

    public init(registry: SourceRegistry, client: SocketClient, env: [String: String]) {
        self.registry = registry
        self.client = client
        self.env = env
    }

    /// Returns what to print on stdout, or nil to stay silent.
    /// Any failure at all — bad JSON, unknown CLI, dead socket, slow reply —
    /// returns nil so the calling CLI carries on with its own default.
    public func run(cli: String, stdin: Data) -> String? {
        guard let adapter = registry.adapter(for: cli),
              let raw = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
              let event = try? adapter.parse(raw, origin: OriginReader.read(env: env)),
              let line = try? WireCodec.encode(event)
        else { return nil }

        guard event.wantsReply else {
            client.send(line)
            return nil
        }

        guard let data = client.sendExpectingReply(line),
              let reply = try? WireCodec.decode(Reply.self, from: data)
        else { return nil }

        return Self.stdout(for: cli, reply: reply)
    }

    /// Each CLI wants its answer in its own shape.
    static func stdout(for cli: String, reply: Reply) -> String? {
        switch cli {
        case "claude-code":
            guard let choice = reply.choice else { return nil }
            let decision = switch choice {
                case "allow", "always": "allow"
                case "deny":            "deny"
                default:                "ask"
            }
            let payload: [String: Any] = [
                "hookSpecificOutput": [
                    "hookEventName": "PreToolUse",
                    "permissionDecision": decision,
                    "permissionDecisionReason": "Answered in VibeCat",
                ],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                         options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return text
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Write the entry point**

Create `Sources/VibeCatHook/main.swift`:

```swift
import Foundation
import VibeCatCore
import VibeCatTransport
import VibeCatHookKit

// usage: vibecat-hook <cli-id>
let cli = CommandLine.arguments.dropFirst().first ?? "claude-code"
let env = ProcessInfo.processInfo.environment

let deadline = env["VIBECAT_TIMEOUT_MS"].flatMap(Double.init).map { $0 / 1000 } ?? 0.3

let runner = HookRunner(
    registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
    client: SocketClient(path: SocketPath.default, deadline: deadline),
    env: env)

let input = FileHandle.standardInput.readDataToEndOfFile()

if let out = runner.run(cli: cli, stdin: input) {
    print(out)
}

// Always zero. A hook that fails must never fail the agent's turn.
exit(0)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter HookRunnerTests`
Expected: PASS, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeCatHookKit Sources/VibeCatHook Tests/VibeCatTransportTests/HookRunnerTests.swift
git commit -m "feat(hook): add the hook runner and executable"
```

---

### Task 14: End-to-end pipeline test and a manual replay script

**Files:**
- Create: `Tests/VibeCatTransportTests/PipelineTests.swift`
- Create: `Scripts/replay.sh`
- Modify: `README.md` — add a "Running it" section

**Interfaces:**
- Consumes: everything above
- Produces: no new API; this task proves the parts fit together

- [ ] **Step 1: Write the failing test**

Create `Tests/VibeCatTransportTests/PipelineTests.swift`:

```swift
import Foundation
import Testing
import VibeCatCore
@testable import VibeCatHookKit
@testable import VibeCatTransport

private func tempPath(_ n: String) -> String { "/tmp/vibecat-e2e-\(n)-\(getpid()).sock" }

/// A hook event travels all the way into a session store and an answer travels
/// all the way back — the whole point of the pipeline, in one test.
@Test func aPermissionPromptReachesTheStoreAndIsAnswered() async throws {
    let path = tempPath("full")
    let store = StoreBox()

    let server = SocketServer(path: path)
    try server.start { event in
        store.apply(event, now: Date(timeIntervalSince1970: 1_000_000))
        return event.wantsReply ? Reply(id: event.id, choice: "allow") : nil
    }
    defer { server.stop() }

    let runner = HookRunner(
        registry: SourceRegistry(adapters: [ClaudeCodeAdapter()]),
        client: SocketClient(path: path, deadline: 1.0),
        env: ["__CFBundleIdentifier": "com.googlecode.iterm2",
              "TERM_SESSION_ID": "w0t1p0:ABC"])

    let out = runner.run(cli: "claude-code", stdin: Data("""
      {"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/Users/me/dev/api",
       "tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}
      """.utf8))

    #expect(out?.contains("\"permissionDecision\":\"allow\"") == true)

    let snapshot = store.snapshot()
    #expect(snapshot.sessions.count == 1)
    #expect(snapshot.aggregate == .waiting)
    #expect(snapshot.sessions[0].project == "api")
    #expect(snapshot.sessions[0].activity == "Bash rm -rf build/")
    #expect(snapshot.sessions[0].origin.termSession == "w0t1p0:ABC")
}

@Test func threeSessionsAggregateToTheMostUrgent() async throws {
    let path = tempPath("three")
    let store = StoreBox()
    let server = SocketServer(path: path)
    try server.start { event in
        store.apply(event, now: Date(timeIntervalSince1970: 1_000_000))
        return nil
    }
    defer { server.stop() }

    let client = SocketClient(path: path, deadline: 1.0)
    for (session, kind) in [("a", Kind.running), ("b", .running), ("c", .permission)] {
        client.send(try WireCodec.encode(
            VibeEvent(id: session, cli: "claude-code", kind: kind,
                      session: session, cwd: "/dev/\(session)")))
    }

    try await waitUntil { store.snapshot().sessions.count == 3 }
    let snapshot = store.snapshot()
    #expect(snapshot.aggregate == .waiting)
    #expect(snapshot.counts[.running] == 2)
    #expect(snapshot.counts[.waiting] == 1)
}

// MARK: - helpers

private final class StoreBox: @unchecked Sendable {
    private let lock = NSLock()
    private var store = SessionStore()
    func apply(_ e: VibeEvent, now: Date) { lock.lock(); store.apply(e, now: now); lock.unlock() }
    func snapshot() -> SessionStore { lock.lock(); defer { lock.unlock() }; return store }
}

private func waitUntil(timeout: TimeInterval = 2,
                       _ condition: @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("condition never became true")
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `swift test --filter PipelineTests`
Expected: PASS if every previous task is correct. If it fails, the failure names
which seam is broken — fix that task rather than this test.

- [ ] **Step 3: Write the manual replay script**

Create `Scripts/replay.sh`:

```bash
#!/usr/bin/env bash
# Replays a Claude Code hook payload against a running vibecat-hook.
#
#   Scripts/replay.sh permission   # a Bash command needing approval
#   Scripts/replay.sh stop         # a finished turn
#
# Point it at a scratch socket so it never touches the real one:
#   VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
set -euo pipefail

case "${1:-permission}" in
  permission)
    payload='{"hook_event_name":"PreToolUse","session_id":"dev-1","cwd":"'"$PWD"'","tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}'
    ;;
  stop)
    payload='{"hook_event_name":"Stop","session_id":"dev-1","cwd":"'"$PWD"'","model":"Opus 4.8","reasoning_effort":"high"}'
    ;;
  notification)
    payload='{"hook_event_name":"Notification","session_id":"dev-1","cwd":"'"$PWD"'","message":"Claude needs your permission"}'
    ;;
  *)
    echo "usage: $0 [permission|stop|notification]" >&2
    exit 2
    ;;
esac

echo "$payload" | swift run vibecat-hook claude-code
echo "(exit $?)"
```

- [ ] **Step 4: Make it executable and try it**

```bash
chmod +x Scripts/replay.sh
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

Expected: prints `(exit 0)` and nothing else, because no server is listening —
this is the fail-open path working.

- [ ] **Step 5: Document how to run it**

Add to `README.md`, immediately before the `## Planned stack` heading:

```markdown
## Running it

```bash
swift build          # builds VibeCatCore, VibeCatTransport and vibecat-hook
swift test           # the whole pipeline, headless
```

Replay a hook payload by hand:

```bash
VIBECAT_SOCKET=/tmp/vibecat-dev.sock Scripts/replay.sh permission
```

With nothing listening the hook prints nothing and exits `0` — that is the
fail-open path, and it is the behaviour to preserve above all others.
```

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, all tests across both test targets.

- [ ] **Step 7: Commit**

```bash
git add Tests/VibeCatTransportTests/PipelineTests.swift Scripts/replay.sh README.md
git commit -m "test: cover the hook-to-store pipeline end to end"
```

---

## Done when

- `swift test` is green, covering: the wire codec, the state-priority rule, the
  session store, the Claude Code adapter, socket permissions, the fail-open
  deadline, and a full hook-to-store-to-reply round trip.
- `Scripts/replay.sh permission` exits `0` with no server running.
- With a server running, the same command prints a `permissionDecision`.

## What this plan deliberately leaves out

Handled by later plans, and **not** to be built here:

- Any UI, window, or SwiftUI view.
- The Codex, Copilot and Gemini adapters — the protocol is in place, the payload
  contracts need verifying against current releases first (spec §19.2).
- Terminal injection and the jump implementation — `JumpStrategy` is recorded on
  each adapter but nothing acts on it yet.
- Settings persistence.
- Sound.
