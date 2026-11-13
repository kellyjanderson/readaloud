// Native sandbox lifetime probe for the production packaged-runtime installer.
// The external runner owns normal Quit; this probe never exits the process.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:read_aloud/src/services/packaged_python_runtime.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 2 || !{'mlx', 'modernbooknlp'}.contains(args[0])) {
    throw ArgumentError('Expected RUNTIME_ID RECEIPT_JSON');
  }
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('Test') && !support.path.contains('s6')) {
    throw StateError('Use an isolated QA sandbox identity');
  }
  final status = ValueNotifier<String>('Checking runtime cancellation…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder<String>(
            valueListenable: status,
            builder: (_, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  final probeParent = await Directory(
    '${support.path}/s6-runtime-cancel',
  ).create(recursive: true);
  final root = await probeParent.createTemp('attempt-');
  final owner = PackagedPythonRuntimeOwner();
  final receipt = <String, Object?>{
    'schema': 'readaloud-native-runtime-cancel-v1',
    'passed': false,
    'runtimeId': args[0],
    'privateSupport': root.path,
    'progress': <Map<String, dynamic>>[],
  };
  final watch = Stopwatch()..start();
  var lastTick = 0, maxDelay = 0;
  final heartbeat = Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = watch.elapsedMilliseconds;
    final delay = now - lastTick - 50;
    if (delay > maxDelay) maxDelay = delay;
    lastTick = now;
  });
  Timer? cancellationTimer;
  Future<void>? drain;
  int? cancelAt;
  var progressAfterCancel = 0;
  var events = 0;
  try {
    late PackagedRuntimeLease lease;
    lease = owner.acquire(
      runtimeId: args[0],
      resources: Directory(
        '${File(Platform.resolvedExecutable).parent.parent.path}/Resources',
      ),
      support: root,
      consumerRevision:
          'native-cancel-${DateTime.now().microsecondsSinceEpoch}',
      onProgress: (value) {
        if (cancelAt != null) progressAfterCancel++;
        events++;
        if (events <= 500) {
          (receipt['progress']! as List).add({
            ...value,
            'elapsedMs': watch.elapsedMilliseconds,
          });
        }
        status.value = value['message'] as String? ?? 'Preparing runtime';
        if (value['stage'] == 'runtimeExtract' && cancellationTimer == null) {
          cancellationTimer = Timer(const Duration(milliseconds: 150), () {
            cancelAt = watch.elapsedMilliseconds;
            status.value = 'Cancelling runtime preparation…';
            drain = lease.cancelAndDrain();
          });
        }
      },
    );
    var cancelled = false;
    try {
      await lease.executable.timeout(const Duration(minutes: 5));
      throw StateError(
        'Cancelled installation unexpectedly published executable',
      );
    } on PackagedRuntimeCancelled {
      cancelled = true;
      receipt['consumerCancellationMs'] = watch.elapsedMilliseconds - cancelAt!;
    }
    await drain?.timeout(const Duration(seconds: 30));
    await owner.shutdown().timeout(const Duration(seconds: 30));
    final leftovers = await root
        .list(recursive: true, followLinks: false)
        .take(100)
        .toList();
    final allowedDirectories = {
      '${root.path}/python-runtimes',
      '${root.path}/python-runtimes/v2',
      '${root.path}/python-runtimes/v2/${args[0]}',
    };
    final ownedFiles = leftovers
        .where((e) => e is! Directory || !allowedDirectories.contains(e.path))
        .map((e) => e.path)
        .toList();
    receipt.addAll({
      'cancelledDuringExtraction': cancelled && cancelAt != null,
      'progressAfterCancellation': progressAfterCancel,
      'leftoverFiles': ownedFiles,
      'progressEventCount': events,
      'progressLogTruncated': events > 500,
      'maxUiHeartbeatDelayMs': maxDelay,
      'resourceShutdownComplete': true,
    });
    if (!cancelled ||
        progressAfterCancel != 0 ||
        ownedFiles.isNotEmpty ||
        maxDelay > 250) {
      throw StateError('Cancellation/progress/lifetime gate failed');
    }
    receipt['passed'] = true;
  } catch (error, stack) {
    receipt['error'] = '$error';
    receipt['stack'] = '$stack';
  } finally {
    cancellationTimer?.cancel();
    try {
      await owner.shutdown().timeout(const Duration(seconds: 30));
    } catch (error) {
      receipt['passed'] = false;
      receipt['shutdownError'] = '$error';
    }
    heartbeat.cancel();
    receipt['elapsedMs'] = watch.elapsedMilliseconds;
    status.value = receipt['passed'] == true
        ? 'Runtime cancellation check passed'
        : 'Runtime cancellation check failed';
    final file = File(args[1]);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(receipt),
      flush: true,
    );
    stdout.writeln(
      'PACKAGED_RUNTIME_SMOKE_COMPLETE passed=${receipt['passed']}',
    );
  }
}
