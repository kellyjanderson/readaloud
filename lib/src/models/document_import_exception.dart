class DocumentImportException implements Exception {
  const DocumentImportException({
    required this.code,
    required this.message,
    this.fileName,
    this.cause,
  });

  final String code;
  final String message;
  final String? fileName;
  final Object? cause;

  @override
  String toString() {
    final fileLabel = (fileName == null || fileName!.isEmpty)
        ? ''
        : ' ($fileName)';
    return 'DocumentImportException[$code]$fileLabel: $message';
  }
}
