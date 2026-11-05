import 'dart:convert';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'modernbooknlp_provider.dart';

/// Immutable reusable evidence. Session/request IDs and process telemetry are
/// deliberately excluded; stored provenance never becomes speaker authority.
class DocumentAnalysisRecord {
  DocumentAnalysisRecord._(
    this.sourceRevision,
    this.text,
    this.providerVersion,
    this.modelIdentity,
    this.adapterVersion,
    this.outputJson,
  ) : key = digest(
        jsonEncode([
          sourceRevision,
          text,
          providerVersion,
          modelIdentity,
          adapterVersion,
          windowPolicy,
        ]),
      );
  final String key;
  final String sourceRevision,
      text,
      providerVersion,
      modelIdentity,
      adapterVersion,
      outputJson;
  static const adapter = modernBookNlpAdapterVersion;
  static const windowPolicy = 'normalized-segments-newline-v1';
  static String digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static String requestKey(ModernBookNlpRequest request) => digest(
    jsonEncode([
      request.sourceRevision,
      request.text,
      modernBookNlpRevision,
      modernBookNlpModelIdentity,
      adapter,
      windowPolicy,
    ]),
  );
  bool get reusable =>
      providerVersion == modernBookNlpRevision &&
      modelIdentity == modernBookNlpModelIdentity &&
      adapterVersion == adapter;

  factory DocumentAnalysisRecord.capture(
    ModernBookNlpRequest request,
    Map<String, dynamic> output,
  ) {
    for (final key in [
      'requestId',
      'ownerId',
      'workId',
      'sourceRevision',
      'analysisRevision',
      'sequence',
    ]) {
      if (output[key] != request.toJson()[key]) {
        throw const FormatException('Analysis owner mismatch');
      }
    }
    if (output['providerId'] != 'modernbooknlp-joint' ||
        output['providerVersion'] != modernBookNlpRevision ||
        output['modelIdentity'] != modernBookNlpModelIdentity ||
        output['adapterVersion'] != adapter) {
      throw const FormatException('Analysis dependencies mismatch');
    }
    return DocumentAnalysisRecord.fromJson({
      'schema': 1,
      'sourceRevision': request.sourceRevision,
      'text': request.text,
      'textSha256': digest(request.text),
      'windowPolicy': windowPolicy,
      'providerId': 'modernbooknlp-joint',
      'providerVersion': output['providerVersion'],
      'modelIdentity': output['modelIdentity'],
      'adapterVersion': output['adapterVersion'],
      'output': {
        for (final key in [
          'entities',
          'quotes',
          'tokenCount',
          'linguisticArtifacts',
        ])
          key: output[key],
      },
    });
  }

  factory DocumentAnalysisRecord.fromJson(Map<String, dynamic> value) {
    try {
      return DocumentAnalysisRecord._decode(value);
    } on TypeError {
      throw const FormatException('Malformed saved analysis');
    }
  }

  factory DocumentAnalysisRecord._decode(Map<String, dynamic> value) {
    if (value['schema'] != 1 ||
        value['windowPolicy'] != windowPolicy ||
        value['providerId'] != 'modernbooknlp-joint') {
      throw const FormatException('Unsupported saved analysis schema');
    }
    for (final key in [
      'sourceRevision',
      'text',
      'providerVersion',
      'modelIdentity',
      'adapterVersion',
    ]) {
      if (value[key] is! String || (value[key] as String).isEmpty) {
        throw FormatException('Missing analysis $key');
      }
    }
    final text = value['text'] as String;
    if (text.length > 16384 || digest(text) != value['textSha256']) {
      throw const FormatException('Invalid saved analysis source');
    }
    final output = Map<String, dynamic>.from(value['output'] as Map);
    const fields = {'entities', 'quotes', 'tokenCount', 'linguisticArtifacts'};
    if (output.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('Unsupported saved analysis output field');
    }
    validateModernBookNlpResult(output, text);
    if (value['adapterVersion'] == adapter &&
        output['linguisticArtifacts'] == null) {
      throw const FormatException('Missing computed linguistic artifacts');
    }
    if (output['tokenCount'] is! int ||
        output['tokenCount'] < 0 ||
        output['tokenCount'] > 4096) {
      throw const FormatException('Invalid analysis token coverage');
    }
    final encoded = jsonEncode(output);
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw const FormatException('Analysis exceeds bound');
    }
    return DocumentAnalysisRecord._(
      value['sourceRevision'],
      text,
      value['providerVersion'],
      value['modelIdentity'],
      value['adapterVersion'],
      encoded,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'sourceRevision': sourceRevision,
    'text': text,
    'textSha256': digest(text),
    'windowPolicy': windowPolicy,
    'providerId': 'modernbooknlp-joint',
    'providerVersion': providerVersion,
    'modelIdentity': modelIdentity,
    'adapterVersion': adapterVersion,
    'output': jsonDecode(outputJson),
  };

  Future<Map<String, dynamic>> restoreForRequest(
    ModernBookNlpRequest request,
  ) => Isolate.run(() => forRequest(request));

  Map<String, dynamic> forRequest(ModernBookNlpRequest request) {
    if (!reusable || key != requestKey(request)) {
      throw const FormatException('Stale saved analysis');
    }
    return {
      ...request.toJson(),
      'ok': true,
      'providerId': 'modernbooknlp-joint',
      'providerVersion': providerVersion,
      'modelIdentity': modelIdentity,
      'adapterVersion': adapterVersion,
      ...jsonDecode(outputJson) as Map<String, dynamic>,
      'restoredFromBook': true,
    };
  }
}
