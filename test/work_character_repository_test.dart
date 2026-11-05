import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/work_character_repository.dart';
import 'package:read_aloud/src/services/work_character_store.dart';

void main() {
  late Directory root;
  late WorkCharacterRepository repository;
  File record(String id) =>
      File('${root.path}/${sha256.convert(utf8.encode(id))}/characters.json');
  WorkCharacterStore twoWorks() => WorkCharacterStore()
    ..select('rosalina', 'ada', 'voice-a')
    ..select('city', 'mara', 'voice-b');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('work-repository-');
    repository = WorkCharacterRepository(root.path);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'VS24 per-work migration, Reset, aliases and file deletion stay isolated',
    () async {
      final old = twoWorks()
        ..select('city', 'mara', null)
        ..associate('city', 'renamed-city');
      final legacy = jsonEncode(old.toJson());
      final sourceIds = jsonEncode({
        'source-r': 'rosalina',
        'source-c': 'renamed-city',
      });
      final loaded = await repository.load(
        legacyCharacters: legacy,
        legacySourceIds: sourceIds,
      );
      expect(await record('rosalina').exists(), isTrue);
      expect(await record('city').exists(), isTrue);
      expect(
        loaded.snapshot
            .restore()
            .character('renamed-city', 'mara')!
            .selectedVoice
            .voiceId,
        isNull,
      );
      final cityBytes = await record('city').readAsBytes();
      await record('rosalina').delete();
      // Even if preference cleanup was interrupted, the migration marker wins.
      final reopened = await WorkCharacterRepository(
        root.path,
      ).load(legacyCharacters: legacy, legacySourceIds: sourceIds);
      expect(reopened.snapshot.restore().entries('rosalina'), isEmpty);
      expect(reopened.sourceIds, {'source-c': 'city'});
      expect(await record('city').readAsBytes(), cityBytes);
    },
  );

  test(
    'VS25 interrupted migration preserves already-published newer choices',
    () async {
      final current = WorkCharacterStore()
        ..select('rosalina', 'ada', 'new-voice');
      await repository.save(current.snapshot(), {'new-source': 'rosalina'});
      final migrated = await repository.load(
        legacyCharacters: jsonEncode(twoWorks().toJson()),
      );
      final owner = migrated.snapshot.restore();
      expect(
        owner.character('rosalina', 'ada')!.selectedVoice.voiceId,
        'new-voice',
      );
      expect(owner.character('city', 'mara')!.selectedVoice.voiceId, 'voice-b');
      expect(migrated.sourceIds['new-source'], 'rosalina');
    },
  );

  test(
    'VS26 corrupt or future work blocks all writes and preserves other files',
    () async {
      final owner = twoWorks();
      await repository.load(legacyCharacters: jsonEncode(owner.toJson()));
      final original = await record('rosalina').readAsBytes();
      for (final bad in ['{broken', '{"schema":999,"workId":"city"}']) {
        await record('city').writeAsString(bad);
        await expectLater(repository.load(), throwsFormatException);
        owner.select('rosalina', 'ada', 'uncommitted');
        await expectLater(
          repository.save(owner.snapshot(), {}),
          throwsFormatException,
        );
        expect(await record('rosalina').readAsBytes(), original);
        expect(await record('city').readAsString(), bad);
      }
    },
  );

  test(
    'VS27 unchanged work files are not rewritten; aliases retire old files',
    () async {
      final owner = twoWorks();
      await repository.load(legacyCharacters: jsonEncode(owner.toJson()));
      final before = await record('city').lastModified();
      owner.select('rosalina', 'ada', 'new');
      await repository.save(owner.snapshot(), {});
      expect(await record('city').lastModified(), before);
      owner.associate('rosalina', 'city');
      await repository.save(owner.snapshot(), {});
      expect(await record('city').exists(), isFalse);
      final reopened = (await repository.load()).snapshot.restore();
      expect(reopened.character('city', 'ada')!.selectedVoice.voiceId, 'new');
      expect(
        reopened.character('city', 'mara')!.selectedVoice.voiceId,
        'voice-b',
      );
    },
  );
  test(
    'VS28 future migration marker blocks load and save without mutation',
    () async {
      final owner = twoWorks();
      await repository.load(legacyCharacters: jsonEncode(owner.toJson()));
      final before = await record('rosalina').readAsBytes();
      final marker = File('${root.path}/migration.json');
      await marker.writeAsString('{"schema":999,"complete":true}');
      await expectLater(repository.load(), throwsFormatException);
      owner.select('rosalina', 'ada', 'future-write');
      await expectLater(
        repository.save(owner.snapshot(), {}),
        throwsFormatException,
      );
      expect(await record('rosalina').readAsBytes(), before);
      expect(await marker.readAsString(), '{"schema":999,"complete":true}');
    },
  );
}
