// Local acoustic evidence: capture only the explicitly named app process.
// swiftc -parse-as-library tools/capture_macos_app_audio.swift -o CAPTURE
// CAPTURE PID NEW_OUTPUT.wav SECONDS (at most 300). Never changes audio routing.
import AVFoundation
import CoreGraphics
import ScreenCaptureKit

final class AppAudioCapture: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "readaloud.test.audio-capture")
    let destination: URL
    var file: AVAudioFile?
    var frames: Int64 = 0
    var sampleRate: Double = 0
    var failure: Error?

    init(destination: URL) { self.destination = destination }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, sample.isValid, failure == nil,
              let description = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return }
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format,
                                        frameCapacity: AVAudioFrameCount(count)) else { return }
        pcm.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList)
        do {
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            if file == nil {
                var settings = format.settings
                settings[AVLinearPCMIsNonInterleaved] = false
                file = try AVAudioFile(forWriting: destination, settings: settings,
                                       commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                sampleRate = format.sampleRate
            }
            guard sampleRate == format.sampleRate else {
                throw NSError(domain: "ReadAloudCapture", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Capture sample rate changed"])
            }
            try file!.write(from: pcm)
            frames += Int64(count)
        } catch { failure = error }
    }
}

@main
struct CaptureMain {
    static func main() async {
        do { try await capture() }
        catch { fputs("Capture failed: \(error)\n", stderr); exit(1) }
    }

    static func capture() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let pid = Int32(args[1]), pid > 0,
              let seconds = Double(args[3]), seconds > 0, seconds <= 300 else {
            fatalError("Usage: CAPTURE PID NEW_OUTPUT.wav SECONDS (1–300)")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw NSError(domain: "ReadAloudCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Screen/audio capture permission unavailable; no permission prompt requested"])
        }
        let destination = URL(fileURLWithPath: args[2])
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
        }
        var filter: SCContentFilter?
        var bundle = ""
        // A spawned PID can precede its WindowServer registration. Wait only
        // for this explicit process; never substitute another app or all audio.
        for _ in 0..<150 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let app = content.applications.first(where: { $0.processID == pid }),
               let display = content.displays.first {
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                bundle = app.bundleIdentifier
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let filter else {
            throw NSError(domain: "ReadAloudCapture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Requested app PID/display unavailable"])
        }
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        let output = AppAudioCapture(destination: destination)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
        try await stream.startCapture()
        print("Capturing app PID \(pid), bundle \(bundle)")
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        let result = output.queue.sync { () -> (Int64, Double, Error?) in
            output.file = nil
            return (output.frames, output.sampleRate, output.failure)
        }
        if let error = result.2 { throw error }
        guard result.0 > 0 else {
            throw NSError(domain: "ReadAloudCapture", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "No app audio captured"])
        }
        print("Captured \(result.0) frames at \(result.1) Hz into \(destination.path)")
    }
}
