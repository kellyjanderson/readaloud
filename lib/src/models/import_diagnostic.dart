enum ImportDiagnosticSeverity { info, warning, error }

class ImportDiagnostic {
  const ImportDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.sourceLocator,
    this.relatedBlockId,
  });

  final ImportDiagnosticSeverity severity;
  final String code;
  final String message;
  final String? sourceLocator;
  final String? relatedBlockId;
}
