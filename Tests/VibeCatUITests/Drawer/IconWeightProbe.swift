import Testing
import Foundation
import SwiftUI
import VibeCatCore
@testable import VibeCatUI

/// Measures what each bundled mark actually paints at the size a row draws it, because
/// "the frames are equal" and "they look the same size" are different claims.
///
/// `SourceIcon` sets `.aspectRatio(contentMode: .fit)` and `.frame(width: side, height:
/// side)`, so every icon gets an identical box and none can be stretched — distortion
/// is structurally impossible. What `.fit` does **not** equalise is how much of its own
/// 256×256 canvas each source file fills, and those differ: measured on the assets,
/// from 63% of the height for `claude_logo` to 100% for the filled circles. `.fit`
/// scales the *canvas* to the box, so the glyph inside inherits that variance.
///
/// **The threshold is `a > 128`, not `!isTransparent`, and that correction mattered.**
/// `Pixel.isTransparent` is `a == 0`, so the first version of this probe counted every
/// antialiased whisper at a scaled bitmap's edge and reported the *canvas* extent
/// rather than the glyph's — every mark came back at 98–100% and an 0.86 optical scale
/// appeared to do nothing. Half-alpha is the line between "this pixel is part of the
/// mark" and "this pixel is the edge fading out".
///
/// Env-gated because it is a measuring instrument, not an assertion — it prints a table
/// for a person to read:
///
///     VIBECAT_ICON_WEIGHT=1 Scripts/test.sh --filter iconWeight
@Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAT_ICON_WEIGHT"] != nil))
@MainActor func iconWeight() throws {
    // **`SourceIcon.side` defaults to 16 and `SessionRow` does not override it**, so
    // that is the slot to measure. An earlier version of this probe used 14 and wrapped
    // the view in `.frame(14, 14)` without passing `side:` — so the icon laid itself out
    // in a 16pt box that a 14pt frame then centred, and an 0.86 optical scale measured
    // as 110px instead of 96. The instrument, not the code, was wrong.
    let side: CGFloat = 16
    let scale: CGFloat = 8   // so a 14pt box is 112px and single-pixel edges are visible
    let box = Int(side * scale)

    print("\nicon           box      painted   fill%   aspect")
    print("------------------------------------------------------")

    var fills: [(String, Double)] = []
    for icon in BundledIcon.allCases {
        let path = try #require(icon.path)
        // The same optical scale the row applies — a probe that skipped it would
        // measure a view nobody renders.
        let view = SourceIcon(path: path, fallback: .generic, side: side,
                              accent: Color(IslandState.idle.accent), style: .brandColour,
                              opticalScale: icon.opticalScale)
        // `side:` passed explicitly, so the view's own box and the box being measured
        // are the same box.
        let r = try rasterise(view.frame(width: side, height: side), scale: scale)  // side matches SourceIcon's

        var minX = box, maxX = -1, minY = box, maxY = -1
        for y in 0..<r.height {
            for x in 0..<r.width where r[x, y].a > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { print("\(icon.rawValue): painted nothing"); continue }
        let w = maxX - minX + 1, h = maxY - minY + 1
        let fill = Double(max(w, h)) / Double(box) * 100
        fills.append((icon.rawValue, fill))
        let name = icon.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("\(name) \(box)px    \(w)x\(h)"
              + "   fill \(String(format: "%5.1f", fill))%"
              + "   aspect \(String(format: "%.2f", Double(w) / Double(h)))")
    }

    // The geometric fallback, for comparison: it is drawn by us at `side` and so fills
    // its box by construction, which is the standard the assets are being read against.
    let markRaster = try rasterise(
        CLIMarkView(mark: .generic, side: side, colour: Color(IslandState.idle.accent))
            .frame(width: side, height: side), scale: scale)
    var mMinX = box, mMaxX = -1, mMinY = box, mMaxY = -1
    for y in 0..<markRaster.height {
        for x in 0..<markRaster.width where markRaster[x, y].a > 128 {
            mMinX = min(mMinX, x); mMaxX = max(mMaxX, x)
            mMinY = min(mMinY, y); mMaxY = max(mMaxY, y)
        }
    }
    let mw = mMaxX - mMinX + 1, mh = mMaxY - mMinY + 1
    print("CLIMark        \(box)px    \(mw)x\(mh)"
          + "   fill \(String(format: "%5.1f", Double(max(mw, mh)) / Double(box) * 100))%"
          + "   (the geometric fallback)")

    // A strip a person can look at: every mark at the row's real 14pt, on the drawer's
    // own ground, with a hairline baseline so a short glyph's vertical drift is visible.
    if let out = ProcessInfo.processInfo.environment["VIBECAT_ICON_STRIP"] {
        let strip = HStack(spacing: 10) {
            ForEach(BundledIcon.allCases, id: \.self) { ic in
                SourceIcon(path: ic.path, fallback: .generic, side: side,
                           accent: Color(IslandState.idle.accent), style: .brandColour,
                           opticalScale: ic.opticalScale)
                    .frame(width: side, height: side)
            }
            CLIMarkView(mark: .generic, side: side, colour: Color(IslandState.idle.accent))
                .frame(width: side, height: side)
        }
        .padding(8)
        .background(Color(islandGroundColour))
        _ = try rasterise(strip, scale: 8).writePNG(to: out)
        print("\nstrip -> \(out)  (order: \(BundledIcon.allCases.map(\.rawValue).joined(separator: ", ")), CLIMark)")
    }

    if let lo = fills.min(by: { $0.1 < $1.1 }), let hi = fills.max(by: { $0.1 < $1.1 }) {
        print("\nspread: \(String(format: "%.1f", lo.1))% (\(lo.0))"
              + " to \(String(format: "%.1f", hi.1))% (\(hi.0))"
              + " — \(String(format: "%.2f", hi.1 / lo.1))x")
    }
}
