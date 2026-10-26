import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/models/dialogue_attribution.dart';
import 'package:read_aloud/src/models/document_voice_attribution.dart';
import 'package:read_aloud/src/models/speech_annotation.dart';
import 'package:read_aloud/src/services/document_import_service.dart';

String words(String text) => RegExp(
  r"[A-Za-z0-9]+",
).allMatches(text.toLowerCase()).map((match) => match.group(0)).join(' ');

void main() {
  // Seeded permutations break the corpus's across-file identity/count ladder.
  final files =
      Directory('test/fixtures/rc2_prose/oracles')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..shuffle(Random(9137));
  for (final file in files) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    test(
      'natural prose normal import: $name exact identities and span owners',
      () {
        final oracle =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final text = File(
          'test/fixtures/rc2_prose/text/$name.txt',
        ).readAsStringSync();
        expect(
          sha256.convert(utf8.encode(text)).toString(),
          oracle['sourceSha256'],
        );
        expect(
          text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length,
          inInclusiveRange(350, 500),
        );
        // Only natural prose goes through the production importer.
        final document = DocumentImportService().importPastedText(text);
        final registry = document.characterCastRegistry;
        expect(registry.narratorEntry.castId, 'cast_narrator');
        expect(
          registry.characterEntries.map((entry) => entry.castId).toSet(),
          (oracle['canonicalCastIds'] as List).cast<String>().toSet(),
        );
        final hints = oracle['voiceHints'] as Map<String, dynamic>;
        for (final entry in registry.characterEntries) {
          final hint = hints[entry.castId] as Map<String, dynamic>;
          expect(entry.inferredGender?.name, hint['gender']);
          expect(entry.identityProfile!.genderSource.name, hint['source']);
        expect(entry.identityProfile!.pronounProfile.hasEvidence, isTrue);
          for (final evidence in entry.identityProfile!.evidenceSpans) {
            final segment = document.speechDocument.segments.firstWhere(
              (segment) => segment.segmentId == evidence.segmentId,
            );
            expect(
              segment.normalizedText.substring(
                evidence.startUtf16,
                evidence.endUtf16,
              ),
              evidence.text,
            );
          }
        }
        for (final name
            in (oracle['namedNonSpeakers'] as List).cast<String>()) {
          expect(
            registry.characterEntries.any(
              (entry) => entry.observedAliases.contains(name),
            ),
            isFalse,
          );
        }
        final expected = (oracle['dialogue'] as List)
            .cast<Map<String, dynamic>>();
        final actual = document.dialogueAttributions.outcomes;
        expect(actual, hasLength(expected.length));
        final castByAttribution = {
          for (final entry in registry.characterEntries)
            for (final id in entry.attributionIds) id: entry.castId,
        };
        for (var index = 0; index < expected.length; index++) {
          final quote = expected[index];
          expect(
            text.substring(
              quote['startUtf16'] as int,
              quote['endUtf16'] as int,
            ),
            quote['text'],
          );
          final outcome = actual[index];
          expect(
            outcome.resolution,
            DialogueAttributionResolution.attributedSpeaker,
            reason: '${quote['text']} must not silently fall back to narrator',
          );
          expect(
            castByAttribution[outcome.attributionId],
            quote['castId'],
            reason: quote['text'] as String,
          );
          final annotations = document.baseSpeechAnnotations.annotations.where(
            (annotation) =>
                annotation.kind == SpeechAnnotationKind.dialogueSpan &&
                annotation.dialogueSpanId == outcome.dialogueSpanId,
          );
          final segmentIds = annotations
              .map((annotation) => annotation.segmentId)
              .toSet();
          final emittedText = document.speechDocument.segments
              .where((segment) => segmentIds.contains(segment.segmentId))
              .map((segment) => segment.normalizedText)
              .join(' ');
          expect(words(emittedText), words(quote['text'] as String));
        }
        final dialogueSegments = document.baseSpeechAnnotations.annotations
            .where(
              (annotation) =>
                  annotation.kind == SpeechAnnotationKind.dialogueSpan,
            )
            .map((annotation) => annotation.segmentId)
            .toSet();
        for (final range in document.documentVoiceAttribution.ranges) {
          if (range.segmentIds.every((id) => !dialogueSegments.contains(id))) {
            expect(range.kind, DocumentVoiceAttributionKind.narration);
            expect(range.castId, 'cast_narrator');
          }
        }
      },
    );
  }
}
