import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/widgets/reader_status_toast.dart';

void main() {
  test(
    'file picker entitlement failure is not described as speech failure',
    () {
      final message = sanitizeReaderStatusMessage(
        'Failed to import picked file content: '
        'PlatformException(ENTITLEMENT_NOT_FOUND, missing entitlement, null)',
      );
      expect(message, contains('file chooser'));
      expect(message, contains('file-access permission'));
      expect(message, isNot(contains('Speech generation')));
    },
  );

  test('other file picker failures retain file-opening context', () {
    expect(
      sanitizeReaderStatusMessage(
        'Failed to import picked file content: PlatformException(picker, failed, null)',
      ),
      'The file could not be opened. Try choosing it again.',
    );
  });

  test('inference failures retain speech context', () {
    expect(
      sanitizeReaderStatusMessage('PlatformException(INFERENCE_ERROR, failed)'),
      contains('Speech generation'),
    );
  });
}
