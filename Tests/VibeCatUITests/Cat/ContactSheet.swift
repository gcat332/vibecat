import SwiftUI
import Testing
@testable import VibeCatUI

/// A developer tool, not a gate. Renders every badge and every coat × mood to
/// one PNG so the artwork can be judged by eye — the thing this project could
/// not do for three plans, and the reason `plain` shipped six cells different
/// from `tabby` with a passing test.
///
/// Off by default because it writes a file and asserts nothing:
///
///     VIBECAT_CONTACT_SHEET=/tmp/sheet.png swift test --filter contactSheet
///
/// Assertions belong in the golden tests beside this file. This is for eyes.
@Suite("Contact sheet")
struct ContactSheetTool {
    /// Big enough to judge a one-cell marking, which is 1pt on the real island.
    static let cell: CGFloat = 6
    static let scale: CGFloat = 2

    @MainActor
    static func sheet() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(IslandState.allCases, id: \.self) { state in
                    VStack(spacing: 4) {
                        BadgeCanvas(badge: Badge(state: state), phase: 0,
                                    tint: state.accent, cellSize: cell)
                        Text(Badge(state: state).rawValue)
                            .font(.system(size: 7)).foregroundStyle(.white)
                    }
                }
            }
            ForEach(Coat.allCases, id: \.self) { coat in
                HStack(alignment: .bottom, spacing: 10) {
                    Text(coat.rawValue)
                        .font(.system(size: 8)).foregroundStyle(.white)
                        .frame(width: 46, alignment: .leading)
                    ForEach(IslandState.allCases, id: \.self) { state in
                        // Phase 0.2 is mid-cycle: past any at-zero special case,
                        // short of trot's blink at 0.92.
                        CatCanvas(cat: ResolvedCat(coat: coat,
                                                   mood: CatMood(state: state),
                                                   phase: 0.2),
                                  palette: CatPalette(accent: state.accent),
                                  cellSize: cell)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.02, green: 0.027, blue: 0.043))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_CONTACT_SHEET"] != nil))
    @MainActor func contactSheet() throws {
        let path = ProcessInfo.processInfo.environment["VIBECAT_CONTACT_SHEET"]!
        let raster = try rasterise(Self.sheet(), scale: Self.scale)
        #expect(raster.writePNG(to: path), "could not write \(path)")
        print("contact sheet: \(raster.width)x\(raster.height) -> \(path)")
    }
}
