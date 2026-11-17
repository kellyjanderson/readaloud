#!/usr/bin/env ruby
# Foundation CLI ownership/rollback checks only: no NSApplication or SavePanel.
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'timeout'
require 'digest'
require 'fileutils'
require 'json'

class S11ExportFilesystemProbeTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_frozen_baseline_builds_without_its_private_git_ancestor
    Dir.mktmpdir('s11-public-probe-check-') do |dir|
      workspace = File.join(dir, 'repo')
      paths = %w[tools/build_s11_export_filesystem_probe.rb tools/s11_export_filesystem_probe.swift
                 tools/fixtures/audio_export_pair_baseline29.swift macos/Runner/Info.plist macos/Runner/Release.entitlements]
      paths.each do |relative|
        target = File.join(workspace, relative)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(File.join(ROOT, relative), target)
      end
      [['init', '-q'], ['add', '.'], ['-c', 'user.name=Source Check', '-c', 'user.email=source-check@example.invalid',
        '-c', 'commit.gpgsign=false', 'commit', '-qm', 'Sanitized source fixture']].each do |arguments|
        output, status = Open3.capture2e('git', '-C', workspace, *arguments)
        assert status.success?, output
      end
      _, absent = Open3.capture2e('git', '-C', workspace, 'cat-file', '-e', '29de8bc22d1ed5e046714402397f8e7f5d5dfda3^{commit}')
      refute absent.success?
      wav = File.join(dir, 'input.wav')
      File.binwrite(wav, 'RIFF' + [38].pack('V') + 'WAVEfmt ' + [16, 1, 1, 24000, 48000, 2, 16].pack('VvvVVvv') + 'data' + [2].pack('V') + [123].pack('s<'))
      json = File.join(dir, 'input.json')
      File.write(json, '{"fixture":"filesystem only"}')
      output, status = Open3.capture2e('ruby', File.join(workspace, paths.first), File.join(dir, 'Probe.app'), wav, json)
      assert status.success?, output
      assert File.file?(File.join(dir, 'Probe.app/Contents/MacOS/s11_export_probe'))
      manifest = JSON.parse(File.read(File.join(dir, 'Probe.app/Contents/Resources/manifest.json')))
      assert_equal 'f828772abfcae5b56999dcd6f9fba5ada6016fc9418277c29df7db0f4afb217c', manifest.fetch('baselineHelperSHA256')
    end
  end

  def test_scoped_transactions_complete_and_roll_back_without_ui
    native = File.read(File.join(__dir__, 'fixtures/audio_export_pair_baseline29.swift'))
    marker = 'final class AudioExportPairPublication {'
    helper = marker + native.split(marker, 2).last
    assert_equal native[/^\/\/ Helper body SHA256: ([0-9a-f]{64})$/, 1], Digest::SHA256.hexdigest(helper)
    probe = File.read(File.join(__dir__, 's11_export_filesystem_probe.swift')).split('private func performExport', 2).first
    harness = <<~'SWIFT'
      let root = URL(fileURLWithPath: CommandLine.arguments[1])
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      private let evidence = try Evidence(root: root.appendingPathComponent("evidence"))
      let fm = FileManager.default
      func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
      func require(_ condition: Bool) { precondition(condition) }
      var cases = 0
      for mode in ["two-phase"] {
        for existing in [false, true] {
          for fault in ["none", "authorization", "metadata"] {
            let denied = fault != "none"
            let folder = root.appendingPathComponent("\(mode)-\(existing)-\(fault)")
            let stage = folder.appendingPathComponent("stage")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent("fixture.wav")
            let sidecar = folder.appendingPathComponent("fixture.json")
            try Data("complete-new-wave".utf8).write(to: stage.appendingPathComponent("audio.wav"))
            if fault != "metadata" { try Data("new-json".utf8).write(to: stage.appendingPathComponent("metadata.json")) }
            if existing {
              try Data("old-wave".utf8).write(to: output)
              try Data("old-json".utf8).write(to: sidecar)
            }
            var failed = false
            do {
              try scopedTransaction(mode: mode, stage: stage, output: output, evidence: evidence,
                register: { presenter in
                  require(try text(presenter.primaryPresentedItemURL!!) == "complete-new-wave")
                  if fault == "authorization" { throw CocoaError(.fileWriteNoPermission) }
                  NSFileCoordinator.addFilePresenter(presenter)
                })
            } catch { failed = true }
            precondition(failed == denied)
            if !denied {
              require(try text(output) == "complete-new-wave")
              require(try text(sidecar) == "new-json")
            } else if existing {
              require(try text(output) == "old-wave")
              require(try text(sidecar) == "old-json")
            } else {
              precondition(!fm.fileExists(atPath: output.path))
              precondition(!fm.fileExists(atPath: sidecar.path))
            }
            cases += 1
          }
        }
      }
      let notified = root.appendingPathComponent("notification")
      let notifiedStage = notified.appendingPathComponent("stage")
      try fm.createDirectory(at: notifiedStage, withIntermediateDirectories: true)
      let notifiedOutput = notified.appendingPathComponent("fixture.wav")
      let notifiedJson = notified.appendingPathComponent("fixture.json")
      try Data("complete-new-wave".utf8).write(to: notifiedStage.appendingPathComponent("audio.wav"))
      try Data("new-json".utf8).write(to: notifiedStage.appendingPathComponent("metadata.json"))
      try notifiedTransaction(stage: notifiedStage, output: notifiedOutput, evidence: evidence,
        register: { NSFileCoordinator.addFilePresenter($0) })
      require(try text(notifiedOutput) == "complete-new-wave")
      require(try text(notifiedJson) == "new-json")
      cases += 1
      let nested = root.appendingPathComponent("nested-refusal")
      let nestedStage = nested.appendingPathComponent("stage")
      try fm.createDirectory(at: nestedStage, withIntermediateDirectories: true)
      let nestedOutput = nested.appendingPathComponent("fixture.wav")
      let nestedJson = nested.appendingPathComponent("fixture.json")
      try Data("complete-new-wave".utf8).write(to: nestedStage.appendingPathComponent("audio.wav"))
      try Data("new-json".utf8).write(to: nestedStage.appendingPathComponent("metadata.json"))
      var nestedRefused = false
      do { try scopedTransaction(mode: "nested-related", stage: nestedStage,
        output: nestedOutput, evidence: evidence, register: { NSFileCoordinator.addFilePresenter($0) }) }
      catch { nestedRefused = true }
      precondition(nestedRefused)
      precondition(!fm.fileExists(atPath: nestedOutput.path))
      precondition(!fm.fileExists(atPath: nestedJson.path))
      cases += 1
      evidence.drainSourceChecks()
      let events = try String(contentsOf: evidence.root.appendingPathComponent("events.jsonl"), encoding: .utf8)
      precondition(events.components(separatedBy: "\"event\":\"coordinationWaitDeadline\"").count == 2)
      print("SCOPED_TRANSACTION_CASES=\(cases)")
    SWIFT
    Dir.mktmpdir('s11-scope-source-') do |dir|
      path = File.join(dir, 'main.swift')
      File.write(path, "import Foundation\n#{helper}\n#{probe}\n#{harness}")
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', path, '-o', File.join(dir, 'checks'))
      assert status.success?, output
      output = status = nil
      Open3.popen2e(File.join(dir, 'checks'), File.join(dir, 'fixtures')) do |stdin, stream, waiter|
        stdin.close
        begin
          Timeout.timeout(25) { output = stream.read; status = waiter.value }
        ensure
          if waiter.alive?
            Process.kill('TERM', waiter.pid) rescue Errno::ESRCH
            unless waiter.join(2)
              Process.kill('KILL', waiter.pid) rescue Errno::ESRCH
              waiter.join
            end
          end
        end
      end
      assert status.success?, output
      assert_includes output, 'SCOPED_TRANSACTION_CASES=8'
      assert_includes output, 'coordinationWaitDeadline'
    end
  end
end
