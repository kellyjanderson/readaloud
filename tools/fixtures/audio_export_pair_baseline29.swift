// Immutable historical CODE fixture for filesystem diagnostics; not current architecture.
// Baseline origin commit: 29de8bc22d1ed5e046714402397f8e7f5d5dfda3
// Original AppDelegate SHA256: 83cd88cf5b04fb41bbab005f1e5416f779829ebec026db2f79b0d235304a630b
// Helper body SHA256: f828772abfcae5b56999dcd6f9fba5ada6016fc9418277c29df7db0f4afb217c
import Foundation
import Darwin

final class AudioExportPairPublication {
  struct Failure: Error {
    let publication: Error
    let rollback: Error
    var preservesStage: Bool { true }
  }

  private final class SidecarPresenter: NSObject, NSFilePresenter {
    let primaryPresentedItemURL: URL?
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = 1
      queue.qualityOfService = .utility
      return queue
    }()
    init(output: URL, sidecar: URL) {
      primaryPresentedItemURL = output
      presentedItemURL = sidecar
    }
  }

  static func sidecar(for output: URL) throws -> URL {
    guard output.isFileURL, !output.hasDirectoryPath, output.path.hasPrefix("/"),
      output.pathExtension.lowercased() == "wav" else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    return output.deletingPathExtension().appendingPathExtension("json")
  }

  static func validatePair(output: URL, sidecar: URL) throws {
    guard try self.sidecar(for: output).standardizedFileURL == sidecar.standardizedFileURL else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
  }

  static func coordinateAndPublish(stage: URL, output: URL,
    registerPresenter: (NSFilePresenter) throws -> Void = { NSFileCoordinator.addFilePresenter($0) }) throws {
    let sidecar = try self.sidecar(for: output)
    let presenter = SidecarPresenter(output: output, sidecar: sidecar)
    var registered = false
    defer { if registered { NSFileCoordinator.removeFilePresenter(presenter) } }
    let coordinator = NSFileCoordinator(filePresenter: presenter)
    var coordinationError: NSError?
    var publicationError: Error?
    coordinator.coordinate(writingItemAt: output, options: .forReplacing,
      writingItemAt: sidecar, options: .forReplacing, error: &coordinationError) { audioURL, jsonURL in
      do {
        try publishFiles(stage: stage, output: audioURL, sidecar: jsonURL,
          prepareRelatedAccess: {
            // Related-item registration needs an existing primary. The complete
            // WAV is already installed, and this one coordinator still holds
            // both write claims through JSON publication or ordinary rollback.
            try registerPresenter(presenter)
            registered = true
          })
      }
      catch { publicationError = error }
    }
    if let error = publicationError { throw error }
    if let error = coordinationError { throw error }
  }

  static func publishFiles(stage: URL, output: URL, sidecar: URL,
    fileManager: FileManager = .default,
    move: (URL, URL) throws -> Void = AudioExportPairPublication.renameFile,
    prepareRelatedAccess: () throws -> Void = {}) throws {
    try validatePair(output: output, sidecar: sidecar)
    guard stage.isFileURL, stage.standardizedFileURL != output.deletingLastPathComponent().standardizedFileURL else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    let audio = stage.appendingPathComponent("audio.wav")
    let json = stage.appendingPathComponent("metadata.json")
    for url in [audio, json] {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else {
        throw CocoaError(.fileReadInvalidFileName)
      }
    }
    func validateExistingDestination(_ url: URL) throws {
      guard fileManager.fileExists(atPath: url.path) else { return }
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory != true, values.isSymbolicLink != true else {
        throw CocoaError(.fileWriteInvalidFileName)
      }
    }
    try validateExistingDestination(output)
    let oldAudio = stage.appendingPathComponent("previous.wav")
    let oldJson = stage.appendingPathComponent("previous.json")
    var audioBackedUp = false, jsonBackedUp = false
    var audioPublished = false, jsonPublished = false
    do {
      if fileManager.fileExists(atPath: output.path) {
        try move(output, oldAudio)
        audioBackedUp = true
      }
      try move(audio, output)
      audioPublished = true
      try prepareRelatedAccess()
      // Sidecar inspection and every sidecar mutation require related access.
      try validateExistingDestination(sidecar)
      if fileManager.fileExists(atPath: sidecar.path) {
        try move(sidecar, oldJson)
        jsonBackedUp = true
      }
      try move(json, sidecar)
      jsonPublished = true
    } catch {
      let publication = error
      do {
        if jsonPublished { try fileManager.removeItem(at: sidecar) }
        if audioPublished { try fileManager.removeItem(at: output) }
        if audioBackedUp { try move(oldAudio, output) }
        if jsonBackedUp { try move(oldJson, sidecar) }
      } catch { throw Failure(publication: publication, rollback: error) }
      throw publication
    }
  }

  static func renameFile(_ source: URL, _ destination: URL) throws {
    // FileManager.moveItem may copy across volumes. POSIX rename either commits
    // an atomic same-volume move or fails (including EXDEV), with no fallback.
    let (status, code) = source.path.withCString { sourcePath in
      destination.path.withCString { destinationPath in
        (rename(sourcePath, destinationPath), errno)
      }
    }
    if status != 0 {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
        userInfo: [NSFilePathErrorKey: destination.path])
    }
  }
}
