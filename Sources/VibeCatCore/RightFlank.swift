import Foundation

/// §6.2's choosable right flank, as a stored preference: "configurable: session
/// count (default), agent icon, or nothing."
///
/// **Mirrors `CollapsedLayout.RightContent`'s three cases but is not that
/// type.** `RightContent.sessionCount` carries a live `Int` — the count at the
/// moment of layout — and a stored preference must not carry a live count of
/// its own; there is nothing to persist between launches but the *choice*.
/// `RightContent` stays in `VibeCatUI/IslandGeometry.swift`, where the live
/// count is computed; Plan 6.1's Task 5 maps one onto the other.
public enum RightFlank: String, Sendable, CaseIterable {
    case sessionCount, agentIcon, nothing
}
