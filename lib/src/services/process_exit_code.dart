import 'process_exit_code_stub.dart'
    if (dart.library.io) 'process_exit_code_io.dart';

void setProcessExitCode(int code) => setProcessExitCodeInternal(code);
