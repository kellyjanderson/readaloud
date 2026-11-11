// Independent local acoustic evidence; no ScreenCaptureKit or playback changes.
// Build/usage/privacy/ownership: docs/process-audio-capture.md. Refs #142 / #112.
import AVFoundation
import CoreAudio
import Darwin
import Foundation

private struct CaptureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func checked(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CaptureError("\(operation) failed (OSStatus \(status))")
    }
}

private func address(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                               mElement: kAudioObjectPropertyElementMain)
}

// Only fixed-layout HAL value types are passed to this helper.
private func readValue<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          initial: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    throws -> T {
    var result = initial
    var property = address(selector, scope: scope)
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutableBytes(of: &result) {
        AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
    }
    try checked(status, "Read HAL property \(selector) on \(object)")
    guard size == MemoryLayout<T>.size else {
        throw CaptureError("Unexpected HAL property size for \(selector)")
    }
    return result
}

private struct Options {
    let pid: pid_t
    let destination: URL
    let seconds: Double
    let stopFile: String?
    var timingURL: URL { URL(fileURLWithPath: destination.path + ".timing.json") }
    var readyURL: URL { URL(fileURLWithPath: destination.path + ".ready.json") }
    var armedURL: URL { URL(fileURLWithPath: destination.path + ".armed.json") }

    init(_ arguments: [String]) throws {
        guard (arguments.count == 4 || arguments.count == 5),
              let pid = pid_t(arguments[1]), pid > 0,
              let seconds = Double(arguments[3]), seconds.isFinite,
              seconds > 0, seconds <= 300 else {
            throw CaptureError("Usage: CAPTURE PID NEW_OUTPUT.wav SECONDS (0 < seconds <= 300) [STOP_FILE]")
        }
        self.pid = pid
        destination = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        self.seconds = seconds
        stopFile = arguments.count == 5 ? URL(fileURLWithPath: arguments[4]).standardizedFileURL.path : nil
        guard destination.pathExtension.lowercased() == "wav" else {
            throw CaptureError("Output must be a new .wav file")
        }
        for path in [destination.path, timingURL.path, readyURL.path, armedURL.path] {
            guard !FileManager.default.fileExists(atPath: path) else {
                throw CaptureError("Refusing to overwrite \(path)")
            }
        }
        guard stopFile != destination.path, stopFile != timingURL.path,
              stopFile != readyURL.path, stopFile != armedURL.path else {
            throw CaptureError("STOP_FILE must be distinct from capture artifacts")
        }
    }
}

private struct Receipt {
    let unixMicros: Int64
    let monotonicRawNanos: UInt64
    let sampleTime: Float64
    let hostTime: UInt64
}

// Each slot has one owner at a time. The callback takes the permit without
// waiting, copies input into this preallocated buffer, then hands ownership to
// the FIFO writer. The writer releases the permit after all reads/write finish.
private final class BufferSlot {
    let available = DispatchSemaphore(value: 1)
    let pcm: AVAudioPCMBuffer

    init(format: AVAudioFormat, capacity: AVAudioFrameCount) throws {
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw CaptureError("Cannot allocate capture buffer")
        }
        self.pcm = pcm
    }
}

private final class WAVWriter {
    // All mutable fields belong exclusively to writerQueue, including AVAudioFile.
    let options: Options
    let format: AVAudioFormat
    let sessionID: String
    var file: AVAudioFile?
    var failure: String?
    var frames: Int64 = 0
    var buffers: Int64 = 0
    var discardedBuffers: Int64 = 0
    var firstSignalFrame: Int64?
    var firstSignalReceivedUnixMicros: Int64?
    var firstSignalMonotonicRawNanos: UInt64?
    var maxWriteLagSeconds: Double = 0
    var peakAbsoluteSample: Float = 0
    var readyPublished = false

    init(options: Options, format: AVAudioFormat, sessionID: String) throws {
        self.options = options
        self.format = format
        self.sessionID = sessionID
        // Reserve exclusively before AVAudioFile opens our own destination.
        try Data().write(to: options.destination, options: .withoutOverwriting)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        file = try AVAudioFile(forWriting: options.destination, settings: settings,
                               commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
    }

    func write(_ slot: BufferSlot, receipt: Receipt, firstFrame: Int64) throws {
        defer { slot.available.signal() }
        guard failure == nil else { discardedBuffers += 1; return }
        do {
            guard firstFrame == frames, let file, let channels = slot.pcm.floatChannelData else {
                throw CaptureError("Writer frame ordering or PCM storage mismatch")
            }
            var signalOffset: Int64?
            let count = Int(slot.pcm.frameLength)
            let channelCount = Int(format.channelCount)
            for frame in 0..<count {
                for channel in 0..<channelCount {
                    let value = format.isInterleaved
                        ? channels[0][frame * channelCount + channel] : channels[channel][frame]
                    guard value.isFinite else { throw CaptureError("Non-finite captured PCM sample") }
                    let magnitude = abs(value)
                    peakAbsoluteSample = max(peakAbsoluteSample, magnitude)
                    if firstSignalFrame == nil, signalOffset == nil, magnitude > 0.01 {
                        signalOffset = Int64(frame)
                    }
                }
            }
            try file.write(from: slot.pcm)
            frames += Int64(count)
            buffers += 1
            if let signalOffset {
                firstSignalFrame = firstFrame + signalOffset
                firstSignalReceivedUnixMicros = receipt.unixMicros
                firstSignalMonotonicRawNanos = receipt.monotonicRawNanos
            }
            let now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            maxWriteLagSeconds = max(maxWriteLagSeconds,
                                     Double(now - receipt.monotonicRawNanos) / 1_000_000_000)
            if !readyPublished {
                let ready: [String: Any] = [
                    "schema": "readaloud-process-capture-ready-v1",
                    "mechanism": "CoreAudioProcessTap", "sessionID": sessionID,
                    "appPid": options.pid, "sampleRate": format.sampleRate,
                    "firstBufferFrames": count, "framesWritten": frames,
                    "firstPacketReceivedUnixMicros": receipt.unixMicros,
                    "firstPacketMonotonicRawNanos": receipt.monotonicRawNanos,
                    "limit": "A real PCM buffer was written. Silence does not establish capture permission or expected speech. Not physical speaker onset.",
                ]
                try JSONSerialization.data(withJSONObject: ready, options: [.prettyPrinted, .sortedKeys])
                    .write(to: options.readyURL, options: .atomic)
                readyPublished = true
                print("Capture ready: first real buffer written; \(options.readyURL.path)")
                fflush(stdout)
            }
        } catch {
            failure = String(describing: error)
            throw error
        }
    }
}

@available(macOS 14.2, *)
private final class ProcessTapCapture {
    let options: Options
    let sessionID = UUID().uuidString
    // HAL dispatches IOBlocks synchronously onto this serial queue. It owns all
    // callback statistics and the slot cursor; it never waits for the writer.
    let callbackQueue = DispatchQueue(label: "readaloud.qa.process-capture.callback", qos: .userInteractive)
    let writerQueue = DispatchQueue(label: "readaloud.qa.process-capture.writer", qos: .userInitiated)
    let poolCount = 64
    var processObject = AudioObjectID(kAudioObjectUnknown)
    var tap = AudioObjectID(kAudioObjectUnknown)
    var aggregate = AudioObjectID(kAudioObjectUnknown)
    var ioProc: AudioDeviceIOProcID?
    var startAttempted = false
    var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    var format: AVAudioFormat?
    var slots: [BufferSlot] = []
    var writer: WAVWriter?
    var bufferCapacity: AVAudioFrameCount = 0

    // callbackQueue-only state (including changes delivered by property listeners).
    var accepting = true
    var failure: String?
    var cursor = 0
    var callbacks: Int64 = 0
    var framesReceived: Int64 = 0
    var framesSubmitted: Int64 = 0
    var buffersSubmitted: Int64 = 0
    var droppedBuffers: Int64 = 0
    var poolOverflows: Int64 = 0
    var deviceOverloads: Int64 = 0
    var discontinuities: Int64 = 0
    var formatChanges: Int64 = 0
    var callbackStalls: Int64 = 0
    var maxPacketGapSeconds: Double = 0
    var maxCallbackReceiptGapSeconds: Double = 0
    var nextSampleTime: Float64?
    var firstReceipt: Receipt?
    var lastReceipt: Receipt?

    init(options: Options) { self.options = options }

    func fail(_ message: String) {
        dispatchPrecondition(condition: .onQueue(callbackQueue))
        if failure == nil { failure = message }
        accepting = false
    }

    func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
                event: @escaping () -> Void) throws {
        var property = property
        let block: AudioObjectPropertyListenerBlock = { _, _ in event() }
        try checked(AudioObjectAddPropertyListenerBlock(object, &property, callbackQueue, block),
                    "Register HAL listener \(property.mSelector)")
        listeners.append((object, property, block))
    }

    func translateProcess() throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = options.pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { qualifier in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property,
                                       UInt32(MemoryLayout<pid_t>.size), qualifier, &size, &object)
        }
        try checked(status, "Translate requested PID to CoreAudio process")
        return object
    }

    func configure() throws {
        let actualPID = try readValue(processObject, kAudioProcessPropertyPID, initial: pid_t(0))
        guard actualPID == options.pid else { throw CaptureError("CoreAudio process PID mismatch") }
        let description = CATapDescription(stereoMixdownOfProcesses: [processObject])
        description.name = "Read Aloud QA \(sessionID)"
        description.isPrivate = true
        description.isExclusive = false
        description.muteBehavior = .unmuted
        if #available(macOS 26.0, *) { description.isProcessRestoreEnabled = false }
        try checked(AudioHardwareCreateProcessTap(description, &tap), "Create private process tap")

        var uid: CFString = "" as CFString
        var property = address(kAudioTapPropertyUID)
        var size = UInt32(MemoryLayout<CFString>.size)
        try checked(withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(tap, &property, 0, nil, &size, $0)
        }, "Read created tap UID")
        guard !(uid as String).isEmpty else { throw CaptureError("Created tap has no UID") }
        var tapASBD = try readValue(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard let format = withUnsafePointer(to: &tapASBD, { AVAudioFormat(streamDescription: $0) }) else {
            throw CaptureError("Unsupported process-tap format")
        }
        guard tapASBD.mFormatID == kAudioFormatLinearPCM,
              format.commonFormat == .pcmFormatFloat32, tapASBD.mBitsPerChannel == 32,
              tapASBD.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.channelCount == 2, format.sampleRate.isFinite, format.sampleRate > 0,
              tapASBD.mBytesPerFrame == (format.isInterleaved ? 8 : 4) else {
            throw CaptureError("Process tap must provide native little-endian stereo Float32 PCM")
        }
        self.format = format
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Read Aloud private capture \(sessionID)",
            kAudioAggregateDeviceUIDKey: "org.readaloud.qa.capture.\(sessionID)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid]],
        ]
        // No physical subdevices, output streams, default-device/volume setters,
        // or routing changes: the private aggregate is only an input consumer.
        try checked(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate),
                    "Create private tap-only aggregate")
        let inputStream = try singleInputStream()
        let aggregateASBD = try readValue(inputStream, kAudioStreamPropertyVirtualFormat,
                                         initial: AudioStreamBasicDescription())
        guard aggregateASBD.mFormatID == tapASBD.mFormatID,
              aggregateASBD.mFormatFlags == tapASBD.mFormatFlags,
              aggregateASBD.mSampleRate == tapASBD.mSampleRate,
              aggregateASBD.mBytesPerFrame == tapASBD.mBytesPerFrame,
              aggregateASBD.mChannelsPerFrame == tapASBD.mChannelsPerFrame,
              aggregateASBD.mBitsPerChannel == tapASBD.mBitsPerChannel else {
            throw CaptureError("Aggregate input format differs from process tap")
        }
        let deviceFrames = try readValue(aggregate, kAudioDevicePropertyBufferFrameSize, initial: UInt32(0))
        guard deviceFrames > 0, deviceFrames <= 16_384 else {
            throw CaptureError("Unsupported aggregate callback size \(deviceFrames)")
        }
        bufferCapacity = max(4096, deviceFrames * 4)
        slots = try (0..<poolCount).map { _ in try BufferSlot(format: format, capacity: bufferCapacity) }
        writer = try writerQueue.sync { try WAVWriter(options: options, format: format, sessionID: sessionID) }

        try listen(aggregate, address(kAudioDeviceProcessorOverload)) { [self] in
            deviceOverloads += 1
            fail("CoreAudio reported processor overload; capture is invalid")
        }
        try listen(inputStream, address(kAudioStreamPropertyVirtualFormat)) { [self] in
            formatChanges += 1
            fail("Aggregate input format changed during capture")
        }
        try listen(tap, address(kAudioTapPropertyFormat)) { [self] in
            formatChanges += 1
            fail("Process tap format changed during capture")
        }
        try checked(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, callbackQueue) {
            [self] _, data, time, _, _ in receive(data, time: time.pointee)
        }, "Create capture IOProc")
        guard ioProc != nil else { throw CaptureError("CoreAudio returned no IOProc") }
    }

    func singleInputStream() throws -> AudioObjectID {
        var property = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        try checked(AudioObjectGetPropertyDataSize(aggregate, &property, 0, nil, &size),
                    "Read aggregate input-stream count")
        guard size == MemoryLayout<AudioObjectID>.size else {
            throw CaptureError("Expected exactly one aggregate input stream")
        }
        var stream = AudioObjectID(kAudioObjectUnknown)
        try checked(AudioObjectGetPropertyData(aggregate, &property, 0, nil, &size, &stream),
                    "Read aggregate input stream")
        return stream
    }

    func receive(_ data: UnsafePointer<AudioBufferList>, time: AudioTimeStamp) {
        dispatchPrecondition(condition: .onQueue(callbackQueue))
        let receipt = Receipt(unixMicros: Int64(Date().timeIntervalSince1970 * 1_000_000),
                              monotonicRawNanos: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
                              sampleTime: time.mSampleTime, hostTime: time.mHostTime)
        callbacks += 1
        if let lastReceipt {
            maxCallbackReceiptGapSeconds = max(maxCallbackReceiptGapSeconds,
                Double(receipt.monotonicRawNanos - lastReceipt.monotonicRawNanos) / 1_000_000_000)
        }
        lastReceipt = receipt
        guard accepting, let format else { droppedBuffers += 1; return }
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        let expectedBuffers = format.isInterleaved ? 1 : 2
        let bytesPerFrame: UInt32 = format.isInterleaved ? 8 : 4
        guard source.count == expectedBuffers,
              let first = source.first, first.mDataByteSize > 0,
              first.mDataByteSize % bytesPerFrame == 0 else {
            droppedBuffers += 1
            fail("Missing, empty or malformed aggregate PCM buffer")
            return
        }
        let count = first.mDataByteSize / bytesPerFrame
        framesReceived += Int64(count)
        guard source.allSatisfy({ $0.mData != nil && $0.mDataByteSize == first.mDataByteSize &&
            $0.mNumberChannels == (format.isInterleaved ? 2 : 1) }), count <= bufferCapacity else {
            droppedBuffers += 1
            fail("Capture PCM layout changed or buffer exceeded preallocated capacity")
            return
        }
        guard time.mFlags.contains(.sampleTimeValid), time.mFlags.contains(.hostTimeValid),
              time.mSampleTime.isFinite else {
            droppedBuffers += 1
            fail("Capture callback has no valid sample/host timestamp")
            return
        }
        if let nextSampleTime {
            let gap = time.mSampleTime - nextSampleTime
            if gap.isFinite {
                maxPacketGapSeconds = max(maxPacketGapSeconds, abs(gap) / format.sampleRate)
            }
            // At most half a sample of floating-point timestamp rounding. A
            // single missing/repeated whole frame always invalidates capture.
            guard gap.isFinite, abs(gap) < 0.5 else {
                discontinuities += 1
                droppedBuffers += 1
                fail("Capture sample-time discontinuity: \(gap) frames")
                return
            }
        }
        nextSampleTime = time.mSampleTime + Double(count)
        let slot = slots[cursor]
        guard slot.available.wait(timeout: .now()) == .success else {
            poolOverflows += 1
            droppedBuffers += 1
            fail("Bounded capture pool exhausted; no buffer was silently dropped")
            return
        }
        cursor = (cursor + 1) % poolCount
        slot.pcm.frameLength = count
        let target = UnsafeMutableAudioBufferListPointer(slot.pcm.mutableAudioBufferList)
        for index in 0..<source.count {
            memcpy(target[index].mData!, source[index].mData!, Int(source[index].mDataByteSize))
        }
        if firstReceipt == nil { firstReceipt = receipt }
        let firstFrame = framesSubmitted
        framesSubmitted += Int64(count)
        buffersSubmitted += 1
        writerQueue.async { [self] in
            do { try writer!.write(slot, receipt: receipt, firstFrame: firstFrame) }
            catch {
                let message = "WAV writer failed: \(error)"
                callbackQueue.async { [self] in fail(message) }
            }
        }
    }

    // Lifecycle state/IDs belong to the calling capture task. Stop/destroy the
    // producer before draining the fixed writer backlog or releasing buffers.
    // All teardown operations are attempted even when an earlier one fails.
    func cleanUp() -> [String] {
        var errors: [String] = []
        func note(_ status: OSStatus, _ operation: String) {
            if status != noErr { errors.append("\(operation) failed (OSStatus \(status))") }
        }
        if startAttempted, let ioProc { note(AudioDeviceStop(aggregate, ioProc), "Stop capture IOProc") }
        if let ioProc {
            note(AudioDeviceDestroyIOProcID(aggregate, ioProc), "Destroy capture IOProc")
            self.ioProc = nil
        }
        for (object, value, block) in listeners.reversed() {
            var property = value
            note(AudioObjectRemovePropertyListenerBlock(object, &property, callbackQueue, block),
                 "Remove HAL listener \(property.mSelector)")
        }
        listeners.removeAll()
        callbackQueue.sync { accepting = false }
        writerQueue.sync { writer?.file = nil }
        // Drain a possible final writer-error report before reading statistics.
        callbackQueue.sync {}
        if aggregate != kAudioObjectUnknown {
            note(AudioHardwareDestroyAggregateDevice(aggregate), "Destroy private aggregate")
            aggregate = AudioObjectID(kAudioObjectUnknown)
        }
        if tap != kAudioObjectUnknown {
            note(AudioHardwareDestroyProcessTap(tap), "Destroy private process tap")
            tap = AudioObjectID(kAudioObjectUnknown)
        }
        return errors
    }

    func run() async throws {
        var errors: [String] = []
        var stopReason = "deadline"
        let commandStart = ProcessInfo.processInfo.systemUptime
        let deadline = commandStart + options.seconds
        // Signal sources only signal a nonblocking flag on this small queue;
        // no HAL or file operations run in a POSIX signal handler.
        let signalQueue = DispatchQueue(label: "readaloud.qa.process-capture.signal")
        var stopSignal: Int32?
        let signalSources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: signalQueue)
            source.setEventHandler { stopSignal = number }
            source.resume()
            return source
        }
        defer { signalSources.forEach { $0.cancel() } }
        do {
            // A launched PID can precede CoreAudio registration. Never widen
            // the tap to other processes or to global/system audio.
            let registrationDeadline = min(deadline, commandStart + 15)
            while processObject == kAudioObjectUnknown {
                guard kill(options.pid, 0) == 0 || errno == EPERM else {
                    throw CaptureError("Requested app PID is unavailable")
                }
                if FileManager.default.fileExists(atPath: options.stopFile ?? "") ||
                    signalQueue.sync(execute: { stopSignal != nil }) {
                    throw CaptureError("Capture cancelled before process registration")
                }
                processObject = try translateProcess()
                if processObject != kAudioObjectUnknown { break }
                guard ProcessInfo.processInfo.systemUptime < registrationDeadline else {
                    throw CaptureError("Requested PID did not register with CoreAudio before deadline")
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try configure()
            let armed: [String: Any] = [
                "schema": "readaloud-process-capture-armed-v1",
                "mechanism": "CoreAudioProcessTap", "sessionID": sessionID,
                "appPid": options.pid, "processAudioObjectID": processObject,
                "sampleRate": format!.sampleRate, "bufferCapacityFrames": bufferCapacity,
                "armedUnixMicros": Int64(Date().timeIntervalSince1970 * 1_000_000),
                "armedMonotonicRawNanos": clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
                "limit": "Tap, aggregate and IOProc are installed; AudioDeviceStart has not returned. No callback, audio, permission or interval coverage is asserted.",
            ]
            try JSONSerialization.data(withJSONObject: armed, options: [.prettyPrinted, .sortedKeys])
                .write(to: options.armedURL, options: .atomic)
            startAttempted = true
            try checked(AudioDeviceStart(aggregate, ioProc), "Start process-tap capture")
            print("Capturing exact app PID \(options.pid) through CoreAudio process tap; session \(sessionID)")
            fflush(stdout)
            while ProcessInfo.processInfo.systemUptime < deadline {
                let callbackError = callbackQueue.sync { () -> String? in
                    // Receipt scheduling is separate from the sample timeline.
                    // Once callbacks start, a whole second without one is an
                    // unobserved interval, never evidence of quiet playback.
                    if failure == nil, let lastReceipt,
                       clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - lastReceipt.monotonicRawNanos > 1_000_000_000 {
                        callbackStalls += 1
                        fail("No CoreAudio callback for over one second; interval is unobserved")
                    }
                    return failure
                }
                if let callbackError { throw CaptureError(callbackError) }
                if let number = signalQueue.sync(execute: { stopSignal }) {
                    stopReason = "signal:\(number)"
                    break
                }
                if let path = options.stopFile, FileManager.default.fileExists(atPath: path) {
                    stopReason = "stopFile"
                    break
                }
                guard kill(options.pid, 0) == 0 || errno == EPERM else {
                    throw CaptureError("Requested app PID exited during capture")
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        } catch { errors.append(String(describing: error)); stopReason = "failure" }
        errors.append(contentsOf: cleanUp())
        let callbackState = callbackQueue.sync { () -> (String?, Int64, Int64, Bool, [String: Any]) in
            var data: [String: Any] = [
                "callbacks": callbacks, "framesReceived": framesReceived, "framesSubmitted": framesSubmitted,
                "buffersSubmitted": buffersSubmitted, "droppedBuffers": droppedBuffers,
                "poolOverflows": poolOverflows, "deviceOverloads": deviceOverloads,
                "timestampDiscontinuities": discontinuities, "formatChanges": formatChanges,
                "callbackStalls": callbackStalls, "maxPacketGapSeconds": maxPacketGapSeconds,
                "maxCallbackReceiptGapSeconds": maxCallbackReceiptGapSeconds,
            ]
            data["firstPacketReceivedUnixMicros"] = firstReceipt?.unixMicros
            data["firstPacketMonotonicRawNanos"] = firstReceipt?.monotonicRawNanos
            data["firstPacketSampleTime"] = firstReceipt?.sampleTime
            data["firstPacketHostTime"] = firstReceipt?.hostTime
            data["lastPacketReceivedUnixMicros"] = lastReceipt?.unixMicros
            data["lastPacketMonotonicRawNanos"] = lastReceipt?.monotonicRawNanos
            if let lastReceipt, lastReceipt.sampleTime.isFinite {
                data["lastPacketSampleTime"] = lastReceipt.sampleTime
            }
            data["lastPacketHostTime"] = lastReceipt?.hostTime
            if let lastReceipt {
                data["lastCallbackReceiptAgeAtCleanupSeconds"] =
                    Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - lastReceipt.monotonicRawNanos) / 1_000_000_000
            }
            return (failure, framesSubmitted, buffersSubmitted,
                    droppedBuffers > 0 || poolOverflows > 0 || deviceOverloads > 0 ||
                    discontinuities > 0 || formatChanges > 0 || callbackStalls > 0, data)
        }
        if let failure = callbackState.0, !errors.contains(failure) {
            errors.append(failure)
        }
        let writerState = writerQueue.sync { writer }
        if let writerState {
            if let failure = writerState.failure, !errors.contains(failure) { errors.append(failure) }
            if writerState.frames != callbackState.1 || writerState.buffers != callbackState.2 ||
                writerState.discardedBuffers > 0 {
                errors.append("Written PCM does not cover every submitted buffer")
            }
            if writerState.frames <= 0 { errors.append("No app PCM frames were captured") }
            do {
                let saved = try AVAudioFile(forReading: options.destination)
                guard saved.length == writerState.frames,
                      saved.fileFormat.sampleRate == format?.sampleRate,
                      saved.fileFormat.channelCount == 2,
                      saved.fileFormat.commonFormat == .pcmFormatFloat32 else {
                    throw CaptureError("Finalized WAV header/frame count differs from captured PCM")
                }
            } catch { errors.append("Final WAV validation failed: \(error)") }
        } else { errors.append("Capture did not initialize a WAV writer") }
        if callbackState.3 {
            errors.append("Capture contains loss, overflow, overload or a format/timestamp discontinuity")
        }
        var timing: [String: Any] = [
            "schema": "readaloud-app-capture-timing-v1", "mechanism": "CoreAudioProcessTap",
            "sessionID": sessionID, "appPid": options.pid, "processAudioObjectID": processObject,
            "status": errors.isEmpty ? "complete" : "failed", "errors": errors, "stopReason": stopReason,
            "frames": writerState?.frames ?? 0, "sampleRate": format?.sampleRate ?? 0,
            "signalThreshold": 0.01, "buffersWritten": writerState?.buffers ?? 0,
            "writerDiscardedBuffers": writerState?.discardedBuffers ?? 0,
            "poolSlots": poolCount, "bufferCapacityFrames": bufferCapacity,
            "maxWriteLagSeconds": writerState?.maxWriteLagSeconds ?? 0,
            "peakAbsoluteSample": writerState?.peakAbsoluteSample ?? 0,
            "readyPublished": writerState?.readyPublished ?? false,
            "privateTap": true, "privateAggregate": true, "tapAutoStart": true, "muteBehavior": "unmuted",
            "deadlineIncludesSetup": true, "requestedSeconds": options.seconds,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - commandStart,
            "limit": "Callback receipt upper bound; requires expected-waveform match. Not physical speaker onset. A continuous tap timeline does not prove expected content, permission or the physical output path. No Play gate is introduced.",
        ]
        timing.merge(callbackState.4) { _, callbackValue in callbackValue }
        timing["firstSignalReceivedUnixMicros"] = writerState?.firstSignalReceivedUnixMicros
        timing["firstSignalFrame"] = writerState?.firstSignalFrame
        timing["firstSignalMonotonicRawNanos"] = writerState?.firstSignalMonotonicRawNanos
        try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys])
            .write(to: options.timingURL, options: .atomic)
        guard errors.isEmpty else { throw CaptureError(errors.joined(separator: "; ")) }
        print("Captured \(writerState!.frames) frames at \(format!.sampleRate) Hz into \(options.destination.path)")
    }
}

@main
private struct CaptureMain {
    static func main() async {
        do {
            let options = try Options(CommandLine.arguments)
            guard #available(macOS 14.2, *) else { throw CaptureError("CoreAudio process taps require macOS 14.2 or later") }
            try await ProcessTapCapture(options: options).run()
        } catch {
            fputs("Capture failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
