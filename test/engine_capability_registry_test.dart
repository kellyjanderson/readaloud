import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/engine_capability.dart';

void main() {
  group('EngineCapabilityRegistry', () {
    const registry = EngineCapabilityRegistry();

    test('returns deterministic kokoro capability profiles', () {
      final first = registry.lookup(
        engineId: 'kokoro',
        platformFamily: 'macos',
      );
      final second = registry.lookup(
        engineId: 'kokoro',
        platformFamily: 'macos',
      );

      expect(first.toMap(), second.toMap());
      expect(first.capabilityProfileId, 'kokoro:macos:v1');
      expect(first.supportsDirectRepresentation('phoneme_string'), isTrue);
      expect(first.supportsApproximation('normalized_spoken_text'), isTrue);
      expect(first.supportsPlainTextFallback, isTrue);
    });
  });
}
