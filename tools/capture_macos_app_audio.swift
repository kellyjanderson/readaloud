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
    var nextPresentationTime: Double?
    var maxPacketGap: Double = 0
    var firstPacketReceivedUnixMicros: Int64?
    var firstSignalReceivedUnixMicros: Int64?
    var firstSignalFrame: Int64?
    var firstSignalMonotonicRawNanos: UInt64?

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
            let received = Int64(Date().timeIntervalSince1970 * 1_000_000)
            let receivedMonotonic = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            if firstPacketReceivedUnixMicros == nil { firstPacketReceivedUnixMicros = received }
            // Receipt time is a conservative upper bound, not the presentation
            // clock or physical speaker onset. Match the saved waveform before
            // interpreting this signal as the intended speech.
            if firstSignalFrame == nil, let channels = pcm.floatChannelData {
                let channelCount = Int(format.channelCount)
                let stride = format.isInterleaved ? channelCount : 1
                for frame in 0..<count {
                    var signal: Float = 0
                    for channel in 0..<channelCount {
                        let data = format.isInterleaved ? channels[0] : channels[channel]
                        let offset = frame * stride + (format.isInterleaved ? channel : 0)
                        signal = max(signal, abs(data[offset]))
                    }
                    if signal > 0.01 {
                        firstSignalFrame = frames + Int64(frame)
                        firstSignalReceivedUnixMicros = received
                        firstSignalMonotonicRawNanos = receivedMonotonic
                        break
                    }
                }
            }
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
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            guard pts.isFinite else { throw NSError(domain: "ReadAloudCapture", code: 5) }
            if let next = nextPresentationTime {
                maxPacketGap = max(maxPacketGap, abs(pts - next))
                guard abs(pts - next) < 0.1 else {
                    throw NSError(domain: "ReadAloudCapture", code: 6,
                      userInfo: [NSLocalizedDescriptionKey: "Capture packet timestamp discontinuity: \(pts - next) seconds"])
                }
            }
            nextPresentationTime = pts + Double(count) / format.sampleRate
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
        guard (args.count == 4 || args.count == 5), let pid = Int32(args[1]), pid > 0,
              let seconds = Double(args[3]), seconds > 0, seconds <= 300 else {
            fatalError("Usage: CAPTURE PID NEW_OUTPUT.wav SECONDS (1–300) [STOP_FILE]")
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
        fflush(stdout)
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if args.count == 5 && FileManager.default.fileExists(atPath: args[4]) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
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
        var timing: [String: Any] = [
            "schema": "readaloud-app-capture-timing-v1", "appPid": pid,
            "frames": result.0, "sampleRate": result.1,
            "signalThreshold": 0.01, "maxPacketGapSeconds": output.maxPacketGap,
            "limit": "Callback receipt upper bound; requires expected-waveform match. Not physical speaker onset. No Play gate is introduced."
        ]
        timing["firstPacketReceivedUnixMicros"] = output.firstPacketReceivedUnixMicros
        timing["firstSignalReceivedUnixMicros"] = output.firstSignalReceivedUnixMicros
        timing["firstSignalFrame"] = output.firstSignalFrame
        timing["firstSignalMonotonicRawNanos"] = output.firstSignalMonotonicRawNanos
        try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: destination.path + ".timing.json"), options: .atomic)
        print("Captured \(result.0) frames at \(result.1) Hz into \(destination.path)")
    }
}
