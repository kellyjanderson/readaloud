import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/kokoro_playback_coordination.dart';

void main() {
  test('finalized audio closes credit before corrected publication', () {
    final credit = KokoroProducedAudioCredit();
    final admission = KokoroBufferAdmission();
    credit.reserve('a', const Duration(seconds: 3));
    credit.reserve('b', const Duration(seconds: 6));
    expect(
      admission.admits(
        audioLead: credit.unpublishedLead([]),
        outstandingChunks: 0,
      ),
      isFalse,
    );
    // The first WAV is corrected/published; its raw duration is replaced, not
    // counted a second time and not lost while its playlist future is pending.
    expect(credit.unpublishedLead(['a']), const Duration(seconds: 6));
    credit.published(['a']);
    expect(credit.unpublishedLead(['a']), const Duration(seconds: 6));
    credit.clear();
    expect(credit.unpublishedLead([]), Duration.zero);
  });
  test('queued publication retains credit and transport scales it once', () {
    final credit = KokoroProducedAudioCredit()
      ..reserve('waiting', const Duration(seconds: 10));
    expect(
      kokoroPlayableLead(credit.unpublishedLead([]), playerSpeed: 2),
      const Duration(seconds: 5),
    );
    credit.published(['waiting']);
    expect(credit.unpublishedLead(['waiting']), Duration.zero);
  });
}
