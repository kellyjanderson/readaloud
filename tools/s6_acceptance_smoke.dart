// One native build for S6's real regeneration and model-forbidden offline probes.
// ENGINE RECEIPT selects regeneration; BOOK.radoc RECEIPT selects offline replay.
// Both probes use the normal app/controller/player and leave normal Quit to the
// bounded external runner. No production routing or engine behavior is changed.
import 'radoc_playback_smoke.dart' as offline;
import 'radoc_regeneration_smoke.dart' as regeneration;
import 'modernbooknlp_persistence_smoke.dart' as booknlp;
import 'packaged_runtime_smoke.dart' as runtime;

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'runtime-cancel') {
    await runtime.main(args.skip(1).toList());
  } else if (args.isNotEmpty && args.first == 'booknlp') {
    await booknlp.main(args.skip(1).toList());
  } else if (args.isNotEmpty && args.first.startsWith('fish_drama3')) {
    await regeneration.main(args);
  } else {
    await offline.main(args);
  }
}
