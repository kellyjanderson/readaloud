// ignore_for_file: avoid_print

import 'app_launch_options.dart';
import 'headless_session_result.dart';

Future<HeadlessSessionResult> runHeadlessSessionInternal(
  AppLaunchOptions options,
) async {
  print('Headless mode is not available on this Flutter platform.');
  return const HeadlessSessionResult(exitCode: 1, succeeded: 0, failed: 0);
}
