class HeadlessSessionResult {
  const HeadlessSessionResult({
    required this.exitCode,
    required this.succeeded,
    required this.failed,
  });

  final int exitCode;
  final int succeeded;
  final int failed;
}
