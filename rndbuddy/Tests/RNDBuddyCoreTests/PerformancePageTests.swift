import Testing
import Foundation
@testable import RNDBuddyCore

struct PerformancePageTests {
    @Test func pagesRoundTripThroughJSON() throws {
        var page = PerformancePage.drift()
        let field = page.controls[0].id
        page.placements[.mac] = [Placement(controlID: field, column: 10, row: 0, width: 8, height: 6)]
        page.controls[1].bindings[0].scope = .fixed(2)
        page.controls[1].bindings[0].curve = .soft
        let data = try JSONEncoder().encode(page)
        #expect(String(decoding: data, as: UTF8.self).contains("\"mac\""))
        #expect(try JSONDecoder().decode(PerformancePage.self, from: data) == page)
    }
    @Test func defaultsValidateAndMirrorCurrentBehaviour() throws {
        for page in PerformancePage.defaults { try page.validate() }
        let field = PerformancePage.drift().controls[0]
        #expect(field.kind == .xy)
        #expect(field.bindings.map(\.target) == [PerformanceMapping().x.target, PerformanceMapping().y.target])
    }
    @Test func legacyMappingBecomesPage() throws {
        var mapping = PerformanceMapping()
        mapping.x = AxisMapping(target: .masterReverb, minimum: 0.2, maximum: 0.8, inverted: true)
        mapping.playYAxis = .velocity
        let page = PerformancePage(legacy: mapping, name: "Old set")
        try page.validate()
        #expect(page.name == "Old set")
        #expect(page.controls[0].bindings[0].axis == mapping.x)
        #expect(page.controls[0].playYAxis == .velocity)
    }
    @Test func curvesKeepEndPointsAndOrder() {
        for curve in ResponseCurve.allCases {
            #expect(curve.apply(0) == 0)
            #expect(curve.apply(1) == 1)
            #expect(curve.apply(-1) == 0 && curve.apply(2) == 1)
            let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(curve.apply)
            #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }
    @Test func bindingAppliesInvertCurveThenRange() {
        let binding = ControlBinding(.volume, axis: AxisMapping(target: .reverb, minimum: 0.2, maximum: 0.6, inverted: true), curve: .exponential)
        #expect(binding.axis.target == .volume)
        #expect(abs(binding.mapped(0) - 0.6) < 1e-9)
        #expect(abs(binding.mapped(1) - 0.2) < 1e-9)
        #expect(abs(binding.mapped(0.5) - (0.2 + 0.25 * 0.4)) < 1e-9)
    }
    @Test func scopeResolvesChannels() {
        #expect(ControlBinding(.reverb).control(selectedTrack: 1) == (91, 3))
        #expect(ControlBinding(.reverb, scope: .fixed(3)).control(selectedTrack: 1) == (91, 5))
        #expect(ControlBinding(.masterVolume, scope: .fixed(3)).control(selectedTrack: 1) == (7, 1))
    }
    @Test func validationRejectsUnsafeData() {
        var page = PerformancePage.drift()
        page.controls[0].bindings.removeLast()
        #expect(throws: PageError.self) { try page.validate() }
        page = .drift(); page.controls[1].bindings[0].scope = .fixed(4)
        #expect(throws: PageError.self) { try page.validate() }
        page = .drift(); page.controls[1].bindings[0].axis.maximum = 1.5
        #expect(throws: PageError.self) { try page.validate() }
        page = .drift(); page.controls[3].action = nil
        #expect(throws: PageError.self) { try page.validate() }
        page = .drift(); page.placements[.phonePortrait] = [Placement(controlID: page.controls[0].id, column: 6, row: 0, width: 4, height: 2)]
        #expect(throws: PageError.self) { try page.validate() }
        page = .drift(); page.controls.append(page.controls[0])
        #expect(throws: PageError.self) { try page.validate() }
    }
    @Test func firmwareGatesDeepReverbAndJGActions() {
        let tone = ControlSpec(kind: .fader, title: "Tone", bindings: [ControlBinding(.tone)])
        let freeze = ControlSpec(kind: .trigger, title: "Freeze", action: .freeze)
        let volume = ControlSpec(kind: .fader, title: "Vol", bindings: [ControlBinding(.volume)])
        #expect(FirmwareCapabilities.supports(volume, firmware: .official14))
        #expect(!FirmwareCapabilities.supports(tone, firmware: .official14))
        #expect(!FirmwareCapabilities.supports(freeze, firmware: .official14))
        #expect(FirmwareCapabilities.supports(tone, firmware: .jg023))
        #expect(FirmwareCapabilities.supports(.reroll, firmware: .jg023))
        #expect(!FirmwareCapabilities.supports(volume, firmware: .unknown))
        #expect(FirmwareCapabilities.supports(.hold, firmware: .unknown))
        #expect(FirmwareCapabilities.reason(tone, firmware: .official14) == "Needs JG firmware")
        #expect(FirmwareCapabilities.reason(volume, firmware: .unknown) == "Firmware not detected")
        #expect(FirmwareCapabilities.reason(volume, firmware: .jg023) == nil)
    }
    @Test(arguments: LayoutClass.allCases) func defaultPagesFlowWithoutOverlap(layout: LayoutClass) {
        for page in PerformancePage.defaults {
            let result = PerformanceLayout.flow(page, in: layout)
            #expect(result.overflow.isEmpty)
            #expect(Set(result.placements.map(\.controlID)) == Set(page.controls.map(\.id)))
            let grid = layout.grid
            for (index, p) in result.placements.enumerated() {
                #expect(p.column >= 0 && p.row >= 0 && p.column + p.width <= grid.columns && p.row + p.height <= grid.rows)
                for other in result.placements[(index + 1)...] { #expect(!p.overlaps(other)) }
            }
        }
    }
    @Test func flowKeepsValidPlacementsAndZones() {
        var page = PerformancePage.drift()
        let field = page.controls[0].id
        let stored = Placement(controlID: field, column: 0, row: 0, width: 6, height: 4)
        page.placements[.mac] = [stored, Placement(controlID: UUID(), column: 8, row: 0, width: 2, height: 2)]
        let result = PerformanceLayout.flow(page, in: .mac)
        #expect(result.placements.first { $0.controlID == field } == stored)
        let tracks = result.placements.first { $0.controlID == page.controls[4].id }!
        #expect(tracks.row + tracks.height == LayoutClass.mac.grid.rows)
        let hold = result.placements.first { $0.controlID == page.controls[3].id }!
        #expect(hold.column + hold.width == LayoutClass.mac.grid.columns)
        #expect(PerformanceLayout.flow(page, in: .mac) == result)
    }
    @Test func crowdedPageReportsOverflow() {
        let controls = (0..<60).map { ControlSpec(kind: .trigger, title: "T\($0)", action: .mute) }
        let result = PerformanceLayout.flow(PerformancePage(name: "Busy", controls: controls), in: .phoneLandscape)
        let grid = LayoutClass.phoneLandscape.grid
        #expect(result.placements.reduce(0) { $0 + $1.width * $1.height } == grid.columns * grid.rows)
        #expect(!result.overflow.isEmpty)
        #expect(result.placements.count + result.overflow.count == 60)
    }
}
