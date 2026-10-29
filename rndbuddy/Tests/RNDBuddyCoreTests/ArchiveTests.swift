import Foundation
import Testing
@testable import RNDBuddyCore

struct ArchiveTests {
    func patch() -> PatchDocument {
        var snapshot = PatchSnapshot(seed: .max, firmware: .jg023, tempo: 123, root: 3, scale: 6, masterVolume: 100, masterReverb: 55)
        snapshot.tracks[0].volume = 92
        snapshot.tracks[0].reverb = 42
        snapshot.tracks[0].rerollSeed = 0x12345678
        snapshot.tracks[0].engineOverride = 1
        snapshot.reverbParameters = [85:12,90:110]
        snapshot.preservedCSV = ["FUTURE FIELD":"keep me"]
        return PatchDocument(name: "Quiet, \"current\"\nII", tags: "warm, ambient", snapshot: snapshot)
    }
    @Test func archiveRoundTrip() throws {
        let patch = patch()
        let data = try JSONEncoder().encode(PatchArchive(patches: [patch]))
        #expect(try PatchArchive.decode(data).patches == [patch])
    }
    @Test func rejectsUnsupportedVersionAndInvalidState() throws {
        var archive = PatchArchive(patches: [patch()]); archive.version = 2
        #expect(throws: Error.self) { try PatchArchive.decode(JSONEncoder().encode(archive)) }
        var invalid = patch(); invalid.snapshot.tracks[0].volume = 500
        #expect(throws: Error.self) { try PatchArchive.validate(invalid.snapshot) }
        invalid = patch(); invalid.snapshot.tracks[0].id = 3
        #expect(throws: Error.self) { try PatchArchive.validate(invalid.snapshot) }
    }
    @Test func jgCSVPreservesQuotesNewlinesRerollsAndUnknownFields() throws {
        let original = patch()
        let decoded = try PatchCSV.decode(PatchCSV.encode([original]))
        #expect(decoded.count == 1)
        let patch = try #require(decoded.first)
        #expect(patch.name == original.name)
        #expect(patch.tags == original.tags)
        #expect(patch.snapshot.seed == .max)
        #expect(patch.snapshot.root == 3)
        #expect(patch.snapshot.scale == 6)
        #expect(patch.snapshot.tracks[0].rerollSeed == 0x12345678)
        #expect(patch.snapshot.tracks[0].volume == 92)
        #expect(patch.snapshot.reverbParameters[85] == 12)
        #expect(patch.snapshot.reverbParameters[90] == 110)
        #expect(patch.snapshot.preservedCSV["FUTURE FIELD"] == "keep me")
    }
    @Test func CSVRejectsMalformedAndTruncatedData() {
        #expect(throws: Error.self) { try PatchCSV.decode("SYSEX,PATCH NAME\nF010F7,test") }
        #expect(throws: Error.self) { try PatchCSV.rows("\"never closed") }
        #expect(throws: Error.self) { try PatchCSV.decode("SYSEX,SYSEX,PATCH NAME\na,a,b") }
    }
}

struct MappingArchiveTests {
    @Test func archiveRetainsMappingsAndReadsOlderPatchOnlyFiles() throws {
        let mapping=MappingDocument(name:"Stage",mapping:PerformanceMapping())
        let archive=PatchArchive(patches:[],mappings:[mapping])
        #expect(try PatchArchive.decode(JSONEncoder().encode(archive)).mappings == [mapping])
        #expect(try PatchArchive.decode(Data("{\"version\":1,\"patches\":[]}".utf8)).mappings == nil)
    }
    @Test func rejectsInvalidMappingRange() throws {
        var mapping=MappingDocument(name:"Invalid",mapping:PerformanceMapping())
        mapping.mapping.x.maximum=2
        #expect(throws:Error.self) { try PatchArchive.decode(JSONEncoder().encode(PatchArchive(patches:[],mappings:[mapping]))) }
    }
}
