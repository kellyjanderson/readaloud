import 'package:flutter/material.dart';

import '../theme/read_aloud_theme.dart';

class ReaderStatusToast extends StatelessWidget {
  const ReaderStatusToast({
    super.key,
    required this.message,
    required this.style,
    required this.onDismiss,
  });

  final String message;
  final ReaderToastStyle style;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: style.background,
      borderRadius: BorderRadius.circular(18),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          children: [
            Icon(style.icon, color: style.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: style.foreground),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDismiss,
              color: style.foreground,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class ReaderToastStyle {
  const ReaderToastStyle({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
}

String sanitizeReaderStatusMessage(String message) {
  if (message.contains('PlatformException') ||
      message.contains('INFERENCE_ERROR')) {
    return 'Speech generation hit a temporary error. Try playing again.';
  }
  if (message.length <= 180) {
    return message;
  }
  return '${message.substring(0, 177).trimRight()}...';
}

ReaderToastStyle toastStyleForStatus({
  required BuildContext context,
  required String message,
}) {
  final tokens = readAloudThemeTokens(context);
  final normalized = message.toLowerCase();
  final isError =
      normalized.contains('failed') ||
      normalized.contains('error') ||
      normalized.contains('could not') ||
      normalized.contains('unavailable');
  final isWarning =
      !isError &&
      (normalized.contains('choose ') ||
          normalized.contains('pause ') ||
          normalized.contains('stopped') ||
          normalized.contains('updated'));

  if (isError) {
    return ReaderToastStyle(
      background: tokens.errorToastBackground,
      foreground: tokens.errorToastForeground,
      icon: Icons.error_outline,
    );
  }
  if (isWarning) {
    return ReaderToastStyle(
      background: tokens.warningToastBackground,
      foreground: tokens.warningToastForeground,
      icon: Icons.info_outline,
    );
  }
  return ReaderToastStyle(
    background: tokens.infoToastBackground,
    foreground: tokens.infoToastForeground,
    icon: Icons.check_circle_outline,
  );
}
