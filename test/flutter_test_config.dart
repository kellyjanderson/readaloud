import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Every test gets a real, isolated support directory. No unit/widget test may
/// read or migrate the user's character files or depend on another test's cache.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final suite = await Directory.systemTemp.createTemp('readaloud-tests-');
  final provider = _TestPaths(suite.path);
  PathProviderPlatform.instance = provider;
  var index = 0;
  setUp(() async {
    provider.root = '${suite.path}/${index++}';
    await Directory(provider.root).create(recursive: true);
  });
  tearDownAll(() async {
    if (await suite.exists()) await suite.delete(recursive: true);
  });
  await testMain();
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);
  String root;
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/documents';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
}
