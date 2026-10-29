import AVFoundation
import Testing
@testable import rndbuddy

struct CaptureTests {
    @Test func stereoWAVPreservesChannelsAndFinalises() throws {
        let sink = AudioRecordingSink()
        sink.sampleRate = 48_000
        let url = URL.temporaryDirectory.appending(path: "rndbuddy-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        input.frameLength = 512
        for frame in 0..<512 {
            input.floatChannelData![0][frame] = 0.25
            input.floatChannelData![1][frame] = -0.5
        }
        try sink.begin(url: url)
        sink.receive(UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList), frames: 512)
        #expect(sink.finish() == noErr)
        #expect(sink.writeError == noErr)
        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 512)
        #expect(file.processingFormat.sampleRate == 48_000)
        #expect(file.processingFormat.channelCount == 2)
        let output = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 512))
        try file.read(into: output)
        #expect(output.floatChannelData![0][100] == 0.25)
        #expect(output.floatChannelData![1][100] == -0.5)
        // No frames may enter a finished take.
        sink.receive(UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList), frames: 512)
        #expect(sink.writtenFrames == 512)
    }

    @Test func dryStemSumAndRepeatedTakes() throws {
        let sink = AudioRecordingSink()
        let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | 4))
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128))
        input.frameLength = 128
        for channel in 0..<4 {
            for frame in 0..<128 { input.floatChannelData![channel][frame] = Float(channel + 1) * 0.1 }
        }
        for _ in 0..<2 {
            let url = URL.temporaryDirectory.appending(path: "rndbuddy-\(UUID()).wav")
            defer { try? FileManager.default.removeItem(at: url) }
            try sink.begin(url: url)
            sink.receive(UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList), frames: 128, dry: true)
            #expect(sink.finish() == noErr)
            let file = try AVAudioFile(forReading: url)
            #expect(file.length == 128)
            let output = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 128))
            try file.read(into: output)
            #expect(abs(output.floatChannelData![0][0] - 0.25) < 0.00001)
            #expect(output.floatChannelData![0][0] == output.floatChannelData![1][0])
        }
    }
    @Test func oversizedCallbackFailsWithoutTruncatingSilently() throws {
        let sink = AudioRecordingSink()
        let url = URL.temporaryDirectory.appending(path: "rndbuddy-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let input = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8193))
        input.frameLength = 8193
        try sink.begin(url: url)
        sink.receive(UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList), frames: 8193)
        #expect(sink.writeError != noErr)
        #expect(sink.writtenFrames == 0)
        sink.finish()
    }
}

#if os(macOS)
import AppKit
@MainActor struct ExternalStageTests {
    @Test func stageUsesWholeScreenAndReturnsSameWebView() throws {
        let screen = try #require(NSScreen.screens.last)
        let host = PixelsHost(session: DeviceSession(transport: FakeMIDITransport(), preferences: nil))
        let webView = host.webView!
        host.showExternal(on: screen, presentation: .fillScreen)
        defer { host.returnToApp() }
        let window = try #require(webView.window)
        #expect(window.frame == screen.frame)
        print("RNDBUDDY_EXTERNAL_FRAME", screen.localizedName, screen.frame, window.frame, webView.frame)
        #expect(webView.frame == window.contentView?.bounds)
        #expect(!host.handleExternalEscape(keyCode: 0, mouseLocation: NSPoint(x: screen.frame.midX, y: screen.frame.midY)))
        #expect(!host.handleExternalEscape(keyCode: 53, mouseLocation: NSPoint(x: screen.frame.maxX + 10, y: screen.frame.maxY + 10)))
        #expect(host.handleExternalEscape(keyCode: 53, mouseLocation: NSPoint(x: screen.frame.midX, y: screen.frame.midY)))
        #expect(host.external)
        #expect(!host.handleExternalEscape(keyCode: 53, mouseLocation: NSPoint(x: screen.frame.midX, y: screen.frame.midY)))
        #expect(webView.window?.styleMask.contains(.resizable) == true)
        #expect(webView.window?.level == .floating)
        host.returnToApp()
        #expect(!host.external)
        #expect(host.webView === webView)
    }
}
#endif
