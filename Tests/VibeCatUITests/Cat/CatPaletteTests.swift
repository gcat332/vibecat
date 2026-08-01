import Testing
@testable import VibeCatUI

private let running = RGBA(hex: "#5B9DF9")!
private let ground = RGBA(hex: "#05070B")!
private let white = RGBA(hex: "#FFFFFF")!

private func mix(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
    RGBA(r: a.r * t + b.r * (1 - t),
         g: a.g * t + b.g * (1 - t),
         b: a.b * t + b.b * (1 - t))
}
private func close(_ a: RGBA, _ b: RGBA) -> Bool {
    abs(a.r - b.r) < 0.002 && abs(a.g - b.g) < 0.002 && abs(a.b - b.b) < 0.002
}

@Test func theBodyToneIsTheAccentItself() {
    #expect(CatPalette(accent: running)[.body] == running)
}

@Test func theDarkTonesAreTheAccentOverTheGround() {
    let p = CatPalette(accent: running)
    #expect(close(p[.outline], mix(running, ground, 0.20)))
    #expect(close(p[.shadow], mix(running, ground, 0.60)))
}

@Test func theLightTonesAreTheAccentOverWhite() {
    let p = CatPalette(accent: running)
    #expect(close(p[.highlight], mix(running, white, 0.64)))
    #expect(close(p[.lightest], mix(running, white, 0.36)))
}

/// The face must read as a face at any hue, so these do not follow the accent.
@Test func theFacialTonesAreFixedWhateverTheAccent() {
    let a = CatPalette(accent: RGBA(hex: "#5B9DF9")!)
    let b = CatPalette(accent: RGBA(hex: "#FF5C5C")!)
    for tone: Tone in [.innerEar, .nose, .eyeWhite, .sparkle, .pupil] {
        #expect(a[tone] == b[tone], "\(tone) should not follow the accent")
    }
    #expect(a[.innerEar].hex == "#F2A0B6")
    #expect(a[.nose].hex == "#F08098")
    #expect(a[.eyeWhite].hex == "#FFFFFF")
    #expect(a[.pupil].hex == "#12131A")
}

/// A ramp with no ordering is not a ramp. Darkest to lightest, by luminance.
@Test func theAccentTonesFormAMonotonicRamp() {
    func luma(_ c: RGBA) -> Double { 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
    for state in IslandState.allCases {
        let p = CatPalette(accent: state.accent)
        let ramp: [Tone] = [.outline, .shadow, .body, .highlight, .lightest]
        let values = ramp.map { luma(p[$0]) }
        #expect(values == values.sorted(), "\(state) ramp is not monotonic: \(values)")
    }
}

@Test func everyToneHasAColour() {
    let p = CatPalette(accent: running)
    for tone in Tone.allCases { _ = p[tone] }
}
