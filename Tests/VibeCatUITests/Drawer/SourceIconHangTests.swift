import AppKit
import Darwin
import SwiftUI
import Testing
import VibeCatCore
@testable import VibeCatUI

// MARK: - The defect these exist for
//
// `SourceIcon.loadValidImage`'s doc comment claimed to handle "every way a path
// can be wrong that must not throw, hang or crash" and enumerated five bad
// inputs. Every one of those five is a file whose `open(2)` **returns**. Plan 7
// Task 6's hardware run found the sixth: a path whose `open(2)` never returns.
//
// Measured, not hypothesised. The signed `VibeCat.app`, launched with `open`,
// drawing a custom source whose icon lived at `~/Downloads/icon/codex_logo.png`.
// The island went dead; `sample` on the live process put the **main thread** in
// `SourceIcon.loadValidImage → NSImage(contentsOfFile:) →
// NSData(contentsOfFile:) → open → __open`, and it stayed there until the
// process was killed. `~/Downloads` is TCC-protected; an `open`-launched bundle
// is attributed to itself rather than to the terminal, so it holds no inherited
// grant, and an `LSUIElement` app cannot present the prompt TCC wants to show.
// `open(2)` simply never answers.
//
// No fixture in this suite could have found that: every one of them is a real
// file in `/tmp` that the test process can always read.
//
// MARK: - The fixture that did not work, recorded rather than deleted
//
// The first version of this file used a **FIFO with no writer**, on the correct
// premise that `open(2)` on one blocks. It does not get that far. Measured with a
// standalone binary:
//
//     mkfifo = 0
//     fileExists = true isDir = false
//     NSImage = nil elapsed = 0.0076
//     Data    = nil elapsed = 0.00013
//
// Foundation `stat`s first and refuses a non-regular file, so the read returns
// `nil` in milliseconds. All four tests written against that fixture passed **in
// 0.001 seconds each** — which is to say they would have passed against the
// unbounded code they existed to catch. Reported rather than adjusted, per this
// repo's standard, and replaced with the injection below.
//
// MARK: - What is tested instead
//
// `SourceIconLoader.read` is injectable, so these drive the timeout branch with a
// read of known duration. The defect *is* "a read that takes arbitrarily long",
// so that is a faithful model of it, and it is falsifiable: against an unbounded
// loader the first call returns the image *late* instead of `nil` *early*, and
// `aReadSlowerThanTheDeadlineYieldsNothingRatherThanWaiting` fails on both of its
// assertions. What injection cannot prove is that the real `readImage` is the
// thing that can stall — the `sample` stack above is the evidence for that, and
// it came from hardware.

/// A solid square PNG, same shape and reason as `SourceIconTests.makeTempIcon`:
/// never a committed file and never one of the owner's real icons.
@MainActor
private func makeTempIcon(_ colour: NSColor, side: Int = 64) throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibecat-sourceicon-hang-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent("icon.png").path
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    colour.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try #require(rep.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: path))
    return path
}

private let iconMagenta = RGBA(r: 1, g: 0, b: 1)

/// Counts how many times the injected read is entered, so a test can assert
/// "one thread, not one per render" directly rather than inferring it from timing.
private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
}

// MARK: - The wait is bounded

/// §2.3: "every wait is bounded." The read takes ten deadlines; the caller must
/// come back in about one, with nothing.
///
/// Both assertions fail against an unbounded loader — it would return the image
/// after 500ms — which is what makes this a test rather than a description. The
/// upper bound is four deadlines rather than one, so that scheduler latency under
/// full-suite load cannot fail it while still being nowhere near the 500ms the
/// read takes.
@Test func aReadSlowerThanTheDeadlineYieldsNothingRatherThanWaiting() async throws {
    let deadline = 0.05
    let image = NSImage(size: CGSize(width: 8, height: 8))
    let loader = SourceIconLoader(deadline: deadline) { _ in
        Thread.sleep(forTimeInterval: deadline * 10)
        return image
    }

    let started = Date()
    let first = loader.image(atPath: "/any/path.png")
    let elapsed = Date().timeIntervalSince(started)

    #expect(first == nil,
            "a read ten times slower than the deadline still handed back an image — the caller waited for it, and on the main thread that is a frozen island")
    #expect(elapsed < deadline * 4,
            "the call took \(elapsed)s against a \(deadline)s deadline — the wait is not bounded")
}

/// The other half of the same rule: once the slow read lands, a later render gets
/// the real image, so a timeout costs one render of the geometric mark rather
/// than hiding an icon for the life of the process.
///
/// **A mutation this does *not* catch, reported rather than papered over.**
/// Caching `nil` in the timeout branch — `cache[path] = NSImage?.none` before
/// `return nil` — leaves this test, and every other test in this file, green. The
/// in-flight read overwrites the cache the moment it completes, so the poisoned
/// entry is never observed; and if the read never completes, `inFlight` still
/// holds the path and the answer is `nil` either way. `SourceIconLoader`'s doc
/// comment now says so, and says the choice is conservatism rather than a
/// requirement.
///
/// What this test **does** pin, mutation-verified: removing `cache[path] = image`
/// from the background block. The second `#expect` then fails (`nil != nil`), as
/// do both assertions in `aSuccessfulReadIsCachedRatherThanRepeated` and the
/// count in `aFailedReadIsCachedTooRatherThanRetriedEveryRender`.
@Test func aTimedOutReadIsNotCachedSoALaterRenderSelfHeals() async throws {
    let deadline = 0.05
    let image = NSImage(size: CGSize(width: 8, height: 8))
    let loader = SourceIconLoader(deadline: deadline) { _ in
        Thread.sleep(forTimeInterval: deadline * 4)
        return image
    }

    #expect(loader.image(atPath: "/any/path.png") == nil, "the fixture did not actually time out")
    try await Task.sleep(for: .milliseconds(500))
    #expect(loader.image(atPath: "/any/path.png") != nil,
            "the image never became available after the slow read completed — a timeout poisoned the cache, so one slow first read hides an icon forever")
}

/// One slow path must not cost one parked thread per render — that is the
/// difference between a leaked stack and an exhausted process. Asserted on the
/// read count, not on timing, so it says exactly what it means.
///
/// Mutation-verified: removing the `inFlight` bookkeeping (dispatching
/// unconditionally) takes the count from 1 to 6.
@Test func repeatedReadsOfASlowPathDispatchOnlyOnce() async throws {
    let deadline = 0.02
    let counter = ReadCounter()
    let loader = SourceIconLoader(deadline: deadline) { _ in
        counter.bump()
        Thread.sleep(forTimeInterval: 5)
        return nil
    }

    let started = Date()
    for _ in 0..<6 { #expect(loader.image(atPath: "/any/path.png") == nil) }
    let elapsed = Date().timeIntervalSince(started)

    #expect(counter.count == 1,
            "\(counter.count) reads were dispatched for six renders of one slow path — a scrolling list would park a new thread per frame")
    #expect(elapsed < deadline * 8,
            "six renders took \(elapsed)s, so they each waited a full deadline rather than the first one only")
}

// MARK: - The cache, which is what makes the deadline affordable

/// A good path is read once. Proved by deleting the file after the first read: a
/// second read that still returns an image can only be coming from the cache.
/// Uses the **real** read, not an injected one, so it is also the test that says
/// a genuine 64×64 PNG does load inside the default deadline.
///
/// Mutation-verified: deleting `cache[path] = image` from
/// `SourceIconLoader.image(atPath:)` makes the second `#expect` fail — the second
/// read re-reads a file that is no longer there and returns `nil`.
@MainActor @Test func aSuccessfulReadIsCachedRatherThanRepeated() throws {
    let path = try makeTempIcon(.magenta)
    #expect(SourceIcon.loadValidImage(atPath: path) != nil,
            "a 64×64 PNG did not load inside the \(SourceIconLoader.defaultDeadline)s default deadline — either the deadline is too tight or the read is not reaching the file")

    try FileManager.default.removeItem(atPath: path)
    #expect(FileManager.default.fileExists(atPath: path) == false)
    #expect(SourceIcon.loadValidImage(atPath: path) != nil,
            "the second read of a path whose file has since been deleted returned nothing — the first read was not cached, so every render re-reads the file from disk")
}

/// And a cached answer really is the icon rather than merely non-nil: the render
/// still shows the icon's own hue, which only its pixels can produce.
@MainActor @Test func aCachedIconStillRendersItsOwnHue() throws {
    let path = try makeTempIcon(.magenta)
    _ = SourceIcon.loadValidImage(atPath: path)
    try FileManager.default.removeItem(atPath: path)

    let raster = try rasterise(
        SourceIcon(path: path, fallback: .codex, side: 16,
                   accent: Color(IslandState.waiting.accent), style: .brandColour)
            .frame(width: 16, height: 16))
    #expect(raster.pixelCount(near: iconMagenta) > 100,
            "a cached icon rendered none of its own magenta — the cache is storing something other than the decoded image")
}

/// A path whose read genuinely fails caches the failure, so a missing icon does
/// not pay the dispatch on every single render for the life of the process. This
/// is the one place a cached `nil` is correct, as opposed to the timeout case
/// above where it is a bug.
@Test func aFailedReadIsCachedTooRatherThanRetriedEveryRender() async throws {
    let counter = ReadCounter()
    let loader = SourceIconLoader { _ in counter.bump(); return nil }
    for _ in 0..<4 { #expect(loader.image(atPath: "/nope.png") == nil) }
    #expect(counter.count == 1,
            "\(counter.count) reads for four renders of a path that is not an image — a source with a bad icon path would dispatch a thread on every frame")
}
