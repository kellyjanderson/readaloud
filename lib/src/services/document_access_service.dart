import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DocumentAccessLease {
  DocumentAccessLease({
    required this.path,
    required this.close,
    this.refreshedToken,
  });

  final String path;
  final String? refreshedToken;
  final Future<void> Function() close;
}

abstract class DocumentAccessService {
  Future<String?> createPersistentRestoreToken(String path);

  Future<DocumentAccessLease?> openPersistentRestoreToken(String token);

  Future<DocumentAccessLease?> requestPersistentRestoreAccess(String path);

  Future<DocumentAccessLease?> requestPersistentDirectoryAccess(
    String directoryPath,
  );
}

DocumentAccessService createDocumentAccessService() =>
    const PlatformDocumentAccessService();

class PlatformDocumentAccessService implements DocumentAccessService {
  const PlatformDocumentAccessService();

  static const MethodChannel _channel = MethodChannel(
    'read_aloud/document_access',
  );

  bool get _supportsPersistentRestore =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<String?> createPersistentRestoreToken(String path) async {
    if (!_supportsPersistentRestore || path.trim().isEmpty) {
      return null;
    }

    return _channel.invokeMethod<String>(
      'createPersistentRestoreToken',
      <String, Object?>{'path': path},
    );
  }

  @override
  Future<DocumentAccessLease?> openPersistentRestoreToken(String token) async {
    if (!_supportsPersistentRestore || token.trim().isEmpty) {
      return null;
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'openPersistentRestoreToken',
      <String, Object?>{'token': token},
    );
    final path = (result?['path'] as String?)?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    final refreshedToken = (result?['token'] as String?)?.trim();
    return DocumentAccessLease(
      path: path,
      refreshedToken: refreshedToken == null || refreshedToken.isEmpty
          ? null
          : refreshedToken,
      close: () => _channel.invokeMethod<void>(
        'closePersistentRestoreToken',
        <String, Object?>{'token': refreshedToken ?? token},
      ),
    );
  }

  @override
  Future<DocumentAccessLease?> requestPersistentRestoreAccess(String path) async {
    if (!_supportsPersistentRestore || path.trim().isEmpty) {
      return null;
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestPersistentRestoreAccess',
      <String, Object?>{'path': path},
    );
    final resolvedPath = (result?['path'] as String?)?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return null;
    }
    final token = (result?['token'] as String?)?.trim();
    return DocumentAccessLease(
      path: resolvedPath,
      refreshedToken: token == null || token.isEmpty ? null : token,
      close: () => _channel.invokeMethod<void>(
        'closePersistentRestoreToken',
        <String, Object?>{'token': token},
      ),
    );
  }

  @override
  Future<DocumentAccessLease?> requestPersistentDirectoryAccess(
    String directoryPath,
  ) async {
    if (!_supportsPersistentRestore || directoryPath.trim().isEmpty) {
      return null;
    }

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestPersistentDirectoryAccess',
      <String, Object?>{'path': directoryPath},
    );
    final resolvedPath = (result?['path'] as String?)?.trim();
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return null;
    }
    final token = (result?['token'] as String?)?.trim();
    return DocumentAccessLease(
      path: resolvedPath,
      refreshedToken: token == null || token.isEmpty ? null : token,
      close: () => _channel.invokeMethod<void>(
        'closePersistentRestoreToken',
        <String, Object?>{'token': token},
      ),
    );
  }
}
