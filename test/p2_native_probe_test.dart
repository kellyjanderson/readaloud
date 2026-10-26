import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/prepared_voice_binding.dart';

import '../tools/p2_native_probe.dart' show buildP2ProbeChunkRequest;

void main() {
  test(
    'native lifetime probe binds requests to the prepared voice revision',
    () {
      const binding = PreparedVoiceBinding(
        voiceId: 'af_bella',
        voiceDigest: 'voice-digest',
        modelDigest: 'model-digest',
        engineVersion: 'p2-probe',
        pronunciationProfileId: 'kokoro-default',
        bindingRevision: 7,
        documentId: 'document-1',
      );

      final request = buildP2ProbeChunkRequest(
        binding: binding,
        cycle: '2',
        chunkId: 'chunk-3',
        outputDirectory: '/tmp/p2-probe',
        text: 'Are you okay?',
        tokens: const [1, 2, 3],
      );

      expect(request.voiceId, binding.voiceId);
      expect(request.documentId, binding.documentId);
      expect(request.expectedBindingFingerprint, binding.fingerprint);
      expect(request.expectedBindingRevision, binding.bindingRevision);
      expect(request.generationId, 'generation-2');
      expect(request.synthesisIdentity, 'p2-probe-invocation-2-chunk-3');
    },
  );
}
