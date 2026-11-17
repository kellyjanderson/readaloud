#!/usr/bin/env ruby
# Executes the exact Foundation-only transaction class from AppDelegate.swift.
# This is local publication/rollback proof, not a sandbox/UI grant claim.
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'json'

class AudioExportPublicationTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_native_pair_validation_publication_and_rollback
    source = File.read(File.join(ROOT, 'macos/Runner/AppDelegate.swift'))
    marker = 'final class AudioExportPairPublication {'
    assert_equal 2, source.split(marker, -1).length
    helper = marker + source.split(marker, 2).last
    harness = <<~'SWIFT'
      final class RecordingMoves {
        var sources: [String] = []
        func move(_ source: URL, _ destination: URL) throws {
          sources.append(source.lastPathComponent)
          try AudioExportPairPublication.renameFile(source, destination)
        }
      }
      final class FailingMoves {
        var failRollback = false
        func move(_ source: URL, _ destination: URL) throws {
          if source.lastPathComponent == "metadata.json" ||
            (failRollback && source.lastPathComponent == "previous.wav") {
            throw CocoaError(.fileWriteNoPermission)
          }
          try AudioExportPairPublication.renameFile(source, destination)
        }
      }
      let fm = FileManager.default
      let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try fm.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? fm.removeItem(at: root) }
      func fixture(_ name: String) throws -> (URL, URL, URL) {
        let folder = root.appendingPathComponent(name)
        let stage = folder.appendingPathComponent("stage")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("book.wav")
        let sidecar = folder.appendingPathComponent("book.json")
        try Data("old audio".utf8).write(to: output)
        try Data("old json".utf8).write(to: sidecar)
        try Data("new audio".utf8).write(to: stage.appendingPathComponent("audio.wav"))
        try Data("new json".utf8).write(to: stage.appendingPathComponent("metadata.json"))
        return (stage, output, sidecar)
      }
      func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
      func require(_ condition: Bool) { precondition(condition, "native transaction assertion") }
      func refuses(_ action: () throws -> Void) throws {
        var refused = false
        do { try action() } catch { refused = true }
        require(refused)
      }
      let (stage, output, json) = try fixture("success")
      let recording = RecordingMoves()
      try AudioExportPairPublication.coordinateAndPublish(stage: stage, output: output, move: recording.move)
      require(recording.sources.first == "book.wav")
      require(recording.sources[1] == "audio.wav")
      require(recording.sources.last == "metadata.json")
      require(try text(output) == "new audio")
      require(try text(json) == "new json")
      require(try text(stage.appendingPathComponent("previous.wav")) == "old audio")
      require(try text(stage.appendingPathComponent("previous.json")) == "old json")

      let (rollbackStage, rollbackOutput, rollbackJson) = try fixture("rollback")
      try refuses { try AudioExportPairPublication.coordinateAndPublish(stage: rollbackStage,
        output: rollbackOutput, move: FailingMoves().move) }
      require(try text(rollbackOutput) == "old audio")
      require(try text(rollbackJson) == "old json")

      let (recoveryStage, recoveryOutput, recoveryJson) = try fixture("recovery")
      let failing = FailingMoves(); failing.failRollback = true
      var retained = false
      do { try AudioExportPairPublication.coordinateAndPublish(stage: recoveryStage,
        output: recoveryOutput, move: failing.move) }
      catch let error as AudioExportPairPublication.Failure { retained = error.preservesStage }
      require(retained)
      require(try text(recoveryStage.appendingPathComponent("previous.wav")) == "old audio")
      require(try text(recoveryJson) == "old json")

      try refuses { try AudioExportPairPublication.validatePair(output: output,
        sidecar: root.appendingPathComponent("different.json")) }
      try refuses { try AudioExportPairPublication.validatePair(output: output,
        sidecar: output.deletingLastPathComponent().appendingPathComponent("different.json")) }
      try refuses { _ = try AudioExportPairPublication.sidecar(for: root.appendingPathComponent("book.txt")) }

      let (directoryStage, directoryOutput, directoryJson) = try fixture("directory")
      try fm.removeItem(at: directoryJson)
      try fm.createDirectory(at: directoryJson, withIntermediateDirectories: false)
      try refuses { try AudioExportPairPublication.coordinateAndPublish(stage: directoryStage,
        output: directoryOutput) }
      require(try text(directoryOutput) == "old audio")
      let (coordinatedStage, coordinatedOutput, coordinatedJson) = try fixture("coordinated")
      try AudioExportPairPublication.coordinateAndPublish(stage: coordinatedStage, output: coordinatedOutput)
      require(try text(coordinatedOutput) == "new audio")
      require(try text(coordinatedJson) == "new json")
      let (newStage, newOutput, newJson) = try fixture("new-primary")
      try fm.removeItem(at: newOutput)
      try fm.removeItem(at: newJson)
      var newRegistered = false
      try AudioExportPairPublication.coordinateAndPublish(stage: newStage, output: newOutput,
        registerPresenter: { presenter in
          require(try text(presenter.primaryPresentedItemURL!!) == "new audio")
          require(!fm.fileExists(atPath: newJson.path))
          NSFileCoordinator.addFilePresenter(presenter)
          newRegistered = true
        })
      require(newRegistered)
      require(try text(newOutput) == "new audio")
      require(try text(newJson) == "new json")

      for existing in [false, true] {
        let (deniedStage, deniedOutput, deniedJson) = try fixture(existing ? "denied-existing" : "denied-new")
        if !existing {
          try fm.removeItem(at: deniedOutput)
          try fm.removeItem(at: deniedJson)
        }
        var requested = false
        try refuses { try AudioExportPairPublication.coordinateAndPublish(stage: deniedStage, output: deniedOutput,
          registerPresenter: { presenter in
            require(try text(presenter.primaryPresentedItemURL!!) == "new audio")
            if existing { require(try text(deniedJson) == "old json") }
            else { require(!fm.fileExists(atPath: deniedJson.path)) }
            requested = true
            throw CocoaError(.fileWriteNoPermission)
          }) }
        require(requested)
        if existing {
          require(try text(deniedOutput) == "old audio")
          require(try text(deniedJson) == "old json")
        } else {
          require(!fm.fileExists(atPath: deniedOutput.path))
          require(!fm.fileExists(atPath: deniedJson.path))
        }
      }
      let (crossStage, crossOutput, crossJson) = try fixture("cross-volume")
      var moves = 0
      var observedEXDEV = false
      do { try AudioExportPairPublication.coordinateAndPublish(stage: crossStage,
        output: crossOutput, move: { _, _ in
          moves += 1
          throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))
        }) }
      catch let error as NSError { observedEXDEV = error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV) }
      require(observedEXDEV && moves == 1)
      require(try text(crossOutput) == "old audio")
      require(try text(crossJson) == "old json")
      let (foreignStage, foreignOutput, foreignJson) = try fixture("foreign-inode")
      var fenced = false
      do { try AudioExportPairPublication.coordinateAndPublish(stage: foreignStage, output: foreignOutput,
        registerPresenter: { presenter in
          try Data("foreign wave".utf8).write(to: foreignOutput, options: .atomic)
          NSFileCoordinator.addFilePresenter(presenter)
        }) }
      catch let error as AudioExportPairPublication.Failure { fenced = error.preservesStage }
      require(fenced)
      require(try text(foreignOutput) == "foreign wave")
      require(try text(foreignJson) == "old json")
      require(try text(foreignStage.appendingPathComponent("previous.wav")) == "old audio")

      let (_, refusedOutput, refusedJson) = try fixture("refused-stage")
      try refuses { try AudioExportPairPublication.coordinateAndPublish(
        stage: refusedOutput.deletingLastPathComponent(), output: refusedOutput) }
      require(try text(refusedOutput) == "old audio")
      require(try text(refusedJson) == "old json")
      let (cancelStage, cancelOutput, cancelJson) = try fixture("cancel-before-admission")
      let cancelled = AudioExportPairPublication.Cancellation()
      cancelled.cancelPending()
      try refuses { try AudioExportPairPublication.coordinateAndPublish(stage: cancelStage,
        output: cancelOutput, cancellation: cancelled) }
      require(try text(cancelOutput) == "old audio")
      require(try text(cancelJson) == "old json")

      let (admittedStage, admittedOutput, admittedJson) = try fixture("cancel-admitted-primary")
      let admittedCancellation = AudioExportPairPublication.Cancellation()
      var fullWaveInstalled = false
      try refuses { try AudioExportPairPublication.coordinateAndPublish(stage: admittedStage,
        output: admittedOutput, move: { source, destination in
          if source.lastPathComponent == "audio.wav" { admittedCancellation.cancelPending() }
          try AudioExportPairPublication.renameFile(source, destination)
          if source.lastPathComponent == "audio.wav" { fullWaveInstalled = true }
        }, cancellation: admittedCancellation) }
      require(fullWaveInstalled)
      require(try text(admittedOutput) == "old audio")
      require(try text(admittedJson) == "old json")

      // A pending JSON coordinator must cancel and restore WAV before an
      // unrelated writer relinquishes its claim. No filesystem body is killed.
      final class ResultBox {
        let lock = NSLock()
        var error: Error?
        func set(_ value: Error?) { lock.lock(); error = value; lock.unlock() }
        func failed() -> Bool { lock.lock(); defer { lock.unlock() }; return error != nil }
      }
      let (waitingStage, waitingOutput, waitingJson) = try fixture("cancel-pending-json")
      let claimEntered = DispatchSemaphore(value: 0), releaseClaim = DispatchSemaphore(value: 0)
      let claimFinished = DispatchSemaphore(value: 0), presenterRegistered = DispatchSemaphore(value: 0)
      let exportFinished = DispatchSemaphore(value: 0)
      let waitingCancellation = AudioExportPairPublication.Cancellation(), outcome = ResultBox()
      DispatchQueue.global(qos: .utility).async {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        coordinator.coordinate(writingItemAt: waitingJson, options: .forReplacing, error: &error) { _ in
          claimEntered.signal(); releaseClaim.wait()
        }
        claimFinished.signal()
      }
      require(claimEntered.wait(timeout: .now() + 3) == .success)
      DispatchQueue.global(qos: .utility).async {
        do {
          try AudioExportPairPublication.coordinateAndPublish(stage: waitingStage, output: waitingOutput,
            cancellation: waitingCancellation, registerPresenter: { presenter in
              NSFileCoordinator.addFilePresenter(presenter)
              presenterRegistered.signal()
            })
          outcome.set(nil)
        } catch { outcome.set(error) }
        exportFinished.signal()
      }
      require(presenterRegistered.wait(timeout: .now() + 3) == .success)
      waitingCancellation.cancelPending()
      let completedBeforeClaimRelease = exportFinished.wait(timeout: .now() + 3) == .success
      releaseClaim.signal()
      require(claimFinished.wait(timeout: .now() + 3) == .success)
      require(completedBeforeClaimRelease && outcome.failed())
      require(try text(waitingOutput) == "old audio")
      require(try text(waitingJson) == "old json")
      print("AUDIO_EXPORT_SWIFT_CASES=17")
    SWIFT
    Dir.mktmpdir('audio-export-swift-') do |dir|
      path = File.join(dir, 'main.swift')
      File.write(path, "import Foundation\n#{helper}\n#{harness}")
      compiled, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', File.join(dir, 'test'))
      assert status.success?, compiled
      stdout, status = Open3.capture2e(File.join(dir, 'test'))
      assert status.success?, stdout
      assert_includes stdout, 'AUDIO_EXPORT_SWIFT_CASES=17'
    end
  end

  def test_json_is_declared_only_as_related_supporting_type
    stdout, status = Open3.capture2e('/usr/bin/plutil', '-extract', 'CFBundleDocumentTypes', 'json', '-o', '-',
      File.join(ROOT, 'macos/Runner/Info.plist'))
    assert status.success?, stdout
    related = JSON.parse(stdout).select { |entry| entry['NSIsRelatedItemType'] }
    assert_equal 1, related.length
    assert_equal ['json'], related.first.fetch('CFBundleTypeExtensions')
    assert_equal ['public.json'], related.first.fetch('LSItemContentTypes')
    assert_equal 'Editor', related.first.fetch('CFBundleTypeRole')
    assert_equal 'None', related.first.fetch('LSHandlerRank')
  end
end
