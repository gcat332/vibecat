import Testing
import Foundation
import SwiftUI
@testable import VibeCatUI

@Test @MainActor func zzSidebarProbe() throws {
    guard ProcessInfo.processInfo.environment["VIBECAT_PROBE"] != nil else { return }
    let r = try rasterise(SettingsSidebar(selection: .constant("display")).frame(height: 200))
    let pane = SettingsPalette.pane
    let o = 0.11
    let hi = Raster.Pixel(RGBA(r: pane.r * (1 - o) + o, g: pane.g * (1 - o) + o, b: pane.b * (1 - o) + o))
    print("PROBE size \(r.width)x\(r.height) expected highlight \(hi)")
    func near(_ p: Raster.Pixel, _ t: Raster.Pixel, _ tol: Int) -> Bool {
        abs(Int(p.r) - Int(t.r)) <= tol && abs(Int(p.g) - Int(t.g)) <= tol && abs(Int(p.b) - Int(t.b)) <= tol
    }
    // where does label ink stop, per row?
    for i in 0..<4 {
        let top = 10 + 36 * i
        var maxInkX = 0
        for y in top..<(top + 36) {
            for x in 8..<188 {
                let p = r[x, y]
                // any pixel clearly brighter than the highlight = glyph/label ink
                if Int(p.r) > 70 { maxInkX = max(maxInkX, x) }
            }
        }
        var counts: [String: Int] = [:]
        for (name, range) in [("8..<188", 8..<188), ("140..<185", 140..<185), ("150..<185", 150..<185)] {
            var n = 0
            for y in (top + 2)..<(top + 34) { for x in range where near(r[x, y], hi, 3) { n += 1 } }
            counts[name] = n
        }
        print("PROBE row \(i) top=\(top) maxInkX=\(maxInkX) highlightCounts=\(counts.sorted { $0.key < $1.key })")
    }
}
