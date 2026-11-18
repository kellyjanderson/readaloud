#!/usr/bin/env ruby
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class NativeEditMenuTest < Minitest::Test
  def test_native_commands_survive_menu_replacement_until_quit
    source = File.read(File.join(__dir__, '../macos/Runner/AppDelegate.swift'))
    helper = source[/^@MainActor\nprivate final class NativeEditMenu \{.*?^\}/m]
    refute_nil helper

    harness = <<~'SWIFT'
      final class PasteResponder: NSResponder {
        var pasteInvocations = 0

        @objc func paste(_ sender: Any?) {
          pasteInvocations += 1
        }
      }

      final class ProbeApplication: NSApplication {
        // AppKit can resolve the first responder in a window that never orders on screen.
        var probeWindow: NSWindow?
        override var keyWindow: NSWindow? { probeWindow }
        override var mainWindow: NSWindow? { probeWindow }
      }

      @MainActor
      func readerMenu() -> NSMenu {
        let menu = NSMenu()
        for title in ["Read Aloud", "File", "Help"] {
          let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
          entry.submenu = NSMenu(title: title)
          menu.addItem(entry)
        }
        return menu
      }

      @MainActor
      func drainMainQueue() {
        var finished = false
        DispatchQueue.main.async { finished = true }
        let deadline = Date().addingTimeInterval(1)
        while !finished && RunLoop.current.run(mode: .default, before: deadline) {}
        precondition(finished, "main queue did not drain")
      }

      MainActor.assumeIsolated {
        let app = ProbeApplication.shared as! ProbeApplication
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        let initial = readerMenu()
        let existingEdit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        existingEdit.submenu = NSMenu(title: "Edit")
        initial.insertItem(existingEdit, at: 2)
        app.mainMenu = initial
        let nativeEditMenu = NativeEditMenu()
        nativeEditMenu.start()
        precondition(initial.items.filter { $0.title == "Edit" }.count == 1)
        precondition(initial.item(withTitle: "Edit") === existingEdit)

        let superseded = readerMenu()
        app.mainMenu = superseded
        let current = readerMenu()
        app.mainMenu = current
        drainMainQueue()
        precondition(superseded.item(withTitle: "Edit") == nil)
        precondition(current.items.map(\.title) == ["Read Aloud", "File", "Edit", "Help"])
        let edit = current.item(withTitle: "Edit")!.submenu!
        precondition(edit.autoenablesItems)
        let commands = edit.items.filter { !$0.isSeparatorItem }
        precondition(commands.compactMap(\.action).map(NSStringFromSelector) ==
          ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"])
        precondition(commands.map(\.keyEquivalent) == ["z", "z", "x", "c", "v", "a"])
        precondition(commands.allSatisfy { $0.target == nil })
        for command in commands {
          precondition(command.keyEquivalentModifierMask ==
            (command.title == "Redo" ? [.command, .shift] : [.command]))
        }

        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        let responder = PasteResponder()
        app.probeWindow = window
        precondition(window.makeFirstResponder(responder))
        let commandV = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
          characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        precondition(current.performKeyEquivalent(with: commandV))
        precondition(responder.pasteInvocations == 1)

        let another = readerMenu()
        app.mainMenu = another
        drainMainQueue()
        precondition(another.items.map(\.title) == ["Read Aloud", "File", "Edit", "Help"])
        app.mainMenu = another
        drainMainQueue()
        precondition(another.items.filter { $0.title == "Edit" }.count == 1)

        let pendingAtQuit = readerMenu()
        app.mainMenu = pendingAtQuit
        nativeEditMenu.stop()
        drainMainQueue()
        precondition(pendingAtQuit.item(withTitle: "Edit") == nil)
      }
    SWIFT

    Dir.mktmpdir('readaloud-native-edit-menu') do |directory|
      swift = File.join(directory, 'main.swift')
      executable = File.join(directory, 'test')
      File.write(swift, "import AppKit\n#{helper}\n#{harness}")
      output, status = Open3.capture2e('/usr/bin/xcrun', 'swiftc', '-swift-version', '5', swift, '-o', executable)
      assert status.success?, output
      output, status = Open3.capture2e(executable)
      assert status.success?, output
    end
  end
end
