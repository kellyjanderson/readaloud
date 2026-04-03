// ignore_for_file: avoid_print

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/app.dart';
import 'src/services/app_launch_options.dart';
import 'src/services/english_pronunciation_dictionary_service.dart';
import 'src/services/headless_session_runner.dart';
import 'src/services/process_exit_code.dart';

Future<void> main(List<String> args) async {
  final parseResult = parseAppLaunchOptions(args);
  if (parseResult.options.showHelp) {
    print(parseResult.usage);
    return;
  }
  if (parseResult.options.hasValidationError) {
    print(parseResult.options.validationError);
    print('');
    print(parseResult.usage);
    setProcessExitCode(2);
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await EnglishPronunciationDictionaryService.instance.initialize();

  if (parseResult.options.headless) {
    final result = await runHeadlessSession(parseResult.options);
    setProcessExitCode(result.exitCode);
    return;
  }

  runApp(ReadAloudApp(launchOptions: parseResult.options));
}
