import 'app_launch_options.dart';
import 'headless_session_result.dart';
import 'headless_session_runner_stub.dart'
    if (dart.library.io) 'headless_session_runner_io.dart';

Future<HeadlessSessionResult> runHeadlessSession(
  AppLaunchOptions options,
) => runHeadlessSessionInternal(options);
