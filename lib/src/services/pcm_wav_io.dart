import 'dart:io';

import 'pcm_wav.dart';

/// Scans a caller-owned handle without reading audio/metadata payloads.
/// The caller serializes access, owns execution context, cancellation and close;
/// this function changes the handle position and never closes it. Checkpoints
/// bracket every bounded read so stale/cancelled workers stop before more I/O.
Future<PcmWavLayout> scanPcmWavFile(
  RandomAccessFile file, {
  void Function()? checkpoint,
}) async {
  checkpoint?.call();
  final scan = PcmWavScan(await file.length());
  while (scan.nextRead != null) {
    final request = scan.nextRead!;
    checkpoint?.call();
    await file.setPosition(request.offset);
    checkpoint?.call();
    final bytes = await file.read(request.length);
    checkpoint?.call();
    scan.accept(bytes);
  }
  return scan.finish();
}
