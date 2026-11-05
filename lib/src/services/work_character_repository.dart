import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'atomic_text_file.dart';
import 'work_character_store.dart';

class StoredWorkCharacters {
  StoredWorkCharacters(this.snapshot, Map<String, String> sourceIds)
    : sourceIds = Map.unmodifiable(sourceIds);
  final CharacterStoreSnapshot snapshot;
  final Map<String, String> sourceIds;
}

/// Disk adapter for the existing character owner and controller save pump.
/// One admitted operation, no queue. All codec/hash/file work runs off UI.
/// A per-work file is the commit unit; migration's marker retires legacy input.
class WorkCharacterRepository {
  WorkCharacterRepository(this.rootPath);
  final String rootPath;
  bool _busy = false;

  Future<T> _run<T>(Future<T> Function() work) async {
    if (_busy) throw StateError('Character repository already has an owner');
    _busy = true;
    try {
      return await Isolate.run(work);
    } finally {
      _busy = false;
    }
  }

  Future<StoredWorkCharacters> load({
    String? legacyCharacters,
    String? legacyChoices,
    String? legacySourceIds,
  }) {
    final root = rootPath;
    return _run(() async {
      final existing = await _readRecords(root);
      final marker = File(p.join(root, 'migration.json'));
      if (await _migrationCompleted(root)) {
        final result = _combine(existing.values);
        await _retireRedirectedFiles(root, existing, result.snapshot);
        return result;
      }
      final owner = legacyCharacters == null
          ? WorkCharacterStore()
          : WorkCharacterStore.fromJson(
              Map<String, dynamic>.from(jsonDecode(legacyCharacters)),
            );
      if (legacyChoices != null) {
        final choices = (jsonDecode(legacyChoices) as Map).map(
          (k, v) => MapEntry(k as String, Map<String, String>.from(v)),
        );
        owner.migrateLegacy(choices);
      }
      final sources = legacySourceIds == null
          ? <String, String>{}
          : Map<String, String>.from(jsonDecode(legacySourceIds));
      final migrated = _partition(owner.snapshot(), sources);
      final currentOwner = _combine(existing.values).snapshot.restore();
      // A prior partial migration or already saved file wins over old preferences.
      for (final entry in migrated.entries) {
        if (!existing.containsKey(entry.key) &&
            currentOwner.workId(entry.key) == entry.key) {
          await _writeRecord(root, entry.key, entry.value);
        }
      }
      final result = _combine((await _readRecords(root)).values);
      await Directory(root).create(recursive: true);
      await atomicWriteText(
        marker.path,
        jsonEncode({'schema': 1, 'complete': true}),
      );
      return result;
    });
  }

  Future<void> save(
    CharacterStoreSnapshot snapshot,
    Map<String, String> sourceIds,
  ) {
    final root = rootPath;
    final sources = Map<String, String>.unmodifiable(sourceIds);
    return _run(() async {
      await _migrationCompleted(root);
      final existing = await _readRecords(
        root,
      ); // Refuse corrupt/future records.
      final records = _partition(snapshot, sources);
      for (final entry in records.entries) {
        if (jsonEncode(existing[entry.key]) == jsonEncode(entry.value)) {
          continue;
        }
        await _writeRecord(root, entry.key, entry.value);
      }
      final published = await _readRecords(root);
      final admitted = _combine(published.values);
      await _retireRedirectedFiles(root, published, admitted.snapshot);
      // Absence in a partial snapshot is not deletion. Explicit closed-app
      // removal of one work file is supported after migration is complete.
    });
  }
}

String _directoryFor(String root, String id) =>
    p.join(root, sha256.convert(utf8.encode(id)).toString());

Map<String, Map<String, Object?>> _partition(
  CharacterStoreSnapshot snapshot,
  Map<String, String> sources,
) {
  final owner = snapshot.restore();
  final state = snapshot.toJson();
  final works = Map<String, dynamic>.from(state['works'] as Map);
  final aliases = Map<String, String>.from(state['aliases'] as Map);
  final redirects = Map<String, dynamic>.from(state['redirects'] as Map);
  for (final id in sources.values) {
    works.putIfAbsent(owner.workId(id), () => []);
  }
  return {
    for (final w in works.entries)
      w.key: {
        'schema': 1,
        'workId': w.key,
        'characters': w.value,
        'aliases': [
          for (final alias in aliases.keys)
            if (owner.workId(alias) == w.key) alias,
        ],
        'redirects': redirects[w.key] ?? <String, String>{},
        'sourceRevisions': [
          for (final s in sources.entries)
            if (owner.workId(s.value) == w.key) s.key,
        ],
      },
  };
}

Future<Map<String, Map<String, dynamic>>> _readRecords(String root) async {
  final directory = Directory(root);
  final records = <String, Map<String, dynamic>>{};
  if (!await directory.exists()) return records;
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! Directory ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.basename(entity.path))) {
      continue;
    }
    final file = File(p.join(entity.path, 'characters.json'));
    if (!await file.exists()) continue;
    final record = Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()),
    );
    final id = record['workId'];
    if (record['schema'] != 1 ||
        id is! String ||
        id.isEmpty ||
        _directoryFor(root, id) != entity.path) {
      throw FormatException(
        'Invalid or unsupported character record: ${file.path}',
      );
    }
    _combine([
      record,
    ]); // Validate aggregates, aliases and Reset before admission.
    records[id] = record;
  }
  return records;
}

StoredWorkCharacters _combine(Iterable<Map<String, dynamic>> records) {
  final works = <String, Object?>{}, redirects = <String, Object?>{};
  final aliases = <String, String>{}, sources = <String, String>{};
  void associate(Map<String, String> target, String key, String id) {
    if (target.containsKey(key) && target[key] != id) {
      throw const FormatException('Conflicting work identity association');
    }
    target[key] = id;
  }

  for (final record in records) {
    for (final alias in List<String>.from(record['aliases'])) {
      associate(aliases, alias, record['workId'] as String);
    }
  }
  String canonical(String id) {
    final seen = <String>{};
    while (aliases.containsKey(id)) {
      if (!seen.add(id)) throw const FormatException('Cyclic work association');
      id = aliases[id]!;
    }
    return id;
  }

  for (final record in records) {
    final id = record['workId'] as String;
    if (canonical(id) == id) {
      works[id] = record['characters'];
      redirects[id] = record['redirects'];
    }
    for (final source in List<String>.from(record['sourceRevisions'])) {
      associate(sources, source, canonical(id));
    }
  }
  final owner = WorkCharacterStore.fromJson({
    'schema': 1,
    'works': works,
    'aliases': aliases,
    'redirects': redirects,
  });
  return StoredWorkCharacters(owner.snapshot(), sources);
}

Future<void> _writeRecord(
  String root,
  String id,
  Map<String, Object?> record,
) async {
  final directory = _directoryFor(root, id);
  await Directory(directory).create(recursive: true);
  await atomicWriteText(
    p.join(directory, 'characters.json'),
    const JsonEncoder.withIndent('  ').convert(record),
  );
}

/// A published canonical record is authoritative after a work association.
/// Recover the write/retire interruption window without reviving old records.
Future<void> _retireRedirectedFiles(
  String root,
  Map<String, Map<String, dynamic>> records,
  CharacterStoreSnapshot snapshot,
) async {
  final owner = snapshot.restore();
  for (final id in records.keys) {
    final target = owner.workId(id);
    if (target != id && records.containsKey(target)) {
      await File(p.join(_directoryFor(root, id), 'characters.json')).delete();
    }
  }
}

Future<bool> _migrationCompleted(String root) async {
  final marker = File(p.join(root, 'migration.json'));
  if (!await marker.exists()) return false;
  final value = jsonDecode(await marker.readAsString());
  if (value is! Map || value['schema'] != 1 || value['complete'] != true) {
    throw const FormatException('Unsupported character migration marker');
  }
  return true;
}
