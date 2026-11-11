// Bounded real HTTPS refresh and offline reopen; no Flutter app or model load.
import 'dart:convert';
import 'dart:io';

import 'package:read_aloud/src/services/fish_drama_catalog_store.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2)
    throw ArgumentError('Expected SOURCE_COMMIT NEW_OUTPUT');
  final output = Directory(args[1]).absolute;
  if (await output.exists()) throw StateError('Preserve existing evidence');
  await output.create(recursive: true);
  final models = await File('assets/fish_drama_models.json').readAsString();
  final checksums = await File(
    'assets/fish_drama_model_checksums.json',
  ).readAsString();
  FishDramaCatalogStore owner({FishDramaCatalogTransport? transport}) =>
      FishDramaCatalogStore(
        root: output,
        bundledModelsJson: models,
        bundledChecksumsJson: checksums,
        transport: transport,
      );
  final store = owner();
  final receipt = <String, Object?>{'passed': false, 'sourceCommit': args[0]};
  try {
    final initial = await store.load();
    final refreshed = await store.refresh(manifestRevision: args[0]);
    if (!refreshed.succeeded) throw StateError('${refreshed.error}');
    if (initial.catalogVersion != 0 || refreshed.snapshot.catalogVersion < 1) {
      throw StateError('Expected validated update over bundled fallback');
    }
    receipt['snapshotIdentity'] = refreshed.snapshot.identity;
    receipt['catalogVersion'] = refreshed.snapshot.catalogVersion;
    receipt['pinnedVariants'] = refreshed.snapshot.catalog.variants.map(
      (key, value) => MapEntry(key, value.pinnedIdentity),
    );
    await store.close();
    var networkCalls = 0;
    final reopened = owner(
      transport: (_) async {
        networkCalls++;
        throw const SocketException('Offline qualification');
      },
    );
    try {
      final saved = await reopened.load();
      if (saved.identity != refreshed.snapshot.identity || networkCalls != 0) {
        throw StateError('Offline last-valid catalog was not reused');
      }
      final failed = await reopened.refresh();
      if (failed.succeeded || failed.snapshot.identity != saved.identity) {
        throw StateError('Failed refresh did not retain last valid catalog');
      }
      receipt['offlineLoadNetworkCalls'] = 0;
      receipt['failedRefreshRetainedIdentity'] = failed.snapshot.identity;
      receipt['passed'] = true;
    } finally {
      await reopened.close();
    }
  } catch (error) {
    receipt['error'] = '$error';
  } finally {
    await store.close();
    await File('${output.path}/receipt.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
  }
  stdout.writeln(jsonEncode(receipt));
  if (receipt['passed'] != true) exitCode = 1;
}
