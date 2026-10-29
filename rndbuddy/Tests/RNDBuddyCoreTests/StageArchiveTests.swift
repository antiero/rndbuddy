import Foundation
import Testing
@testable import RNDBuddyCore

struct StageArchiveTests {
    @Test func pageArchiveIsAdditiveAndBounded() throws {
        let old = Data(#"{"version":1,"patches":[]}"#.utf8)
        #expect(try PatchArchive.decode(old).pages == nil)
        let pages = PerformancePage.defaults
        let data = try JSONEncoder().encode(PatchArchive(patches: [], pages: pages))
        #expect(try PatchArchive.decode(data).pages == pages)
        #expect(throws: (any Error).self) {
            try PatchArchive.decode(JSONEncoder().encode(PatchArchive(patches: [], pages: Array(repeating: pages[0], count: 1001))))
        }
    }
    @Test func overlapsAreRejected() {
        var page = PerformancePage.drift()
        page.placements[.mac] = page.controls.prefix(2).map { Placement(controlID: $0.id, column: 0, row: 0, width: 2, height: 2) }
        #expect(throws: (any Error).self) { try page.validate() }
    }
    @Test func legacySourcesRemainDecodable() throws {
        #expect(try JSONDecoder().decode(InputSource.self, from: Data(#""hands""#.utf8)) == .hands)
        for source in InputSource.allCases {
            #expect(try JSONDecoder().decode(InputSource.self, from: JSONEncoder().encode(source)) == source)
        }
    }
}
