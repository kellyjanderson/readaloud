import '../models/character.dart';
import '../models/character_cast_registry.dart';
import '../models/cast_voice_assignment.dart';
import '../models/voice_profile.dart';
import 'cast_voice_assignment_service.dart';
import 'character_codec.dart';

/// Single main-isolate character/selection writer. No worker or native handle
/// is retained here. The controller's existing coalesced preference pump owns
/// persistence; provider deltas cannot import selectedVoice or Reset state.
class WorkCharacterStore {
  final Map<String, Map<String, CastEntry>> _works = {};
  final Map<String, String> _workAliases = {};
  final Map<String, Map<String, String>> _redirects = {};
  final Map<String, int> _sequences = {};
  String? _source, _activeWork;
  int _analysisRevision = -1;

  String workId(String key) {
    final seen = <String>{};
    while (_workAliases.containsKey(key)) {
      if (!seen.add(key)) throw const FormatException('Cyclic work alias');
      key = _workAliases[key]!;
    }
    return key;
  }

  void begin({
    required String workId,
    required String sourceRevision,
    required int analysisRevision,
  }) {
    _activeWork = this.workId(workId);
    _source = sourceRevision;
    _analysisRevision = analysisRevision;
    _sequences.clear();
  }

  void cancelAnalysis() {
    _activeWork = null;
    _source = null;
    _sequences.clear();
  }

  bool apply(CharacterAnalysisDelta delta) {
    if (workId(delta.workId) != _activeWork ||
        delta.sourceRevision != _source ||
        delta.analysisRevision != _analysisRevision ||
        delta.sequence <= (_sequences[delta.providerId] ?? -1)) {
      return false;
    }
    _sequences[delta.providerId] = delta.sequence;
    mergeEvidence(delta.workId, delta.registry);
    return true;
  }

  String _castId(String work, String id) {
    final aliases = _redirects[work] ?? const <String, String>{};
    final seen = <String>{};
    while (aliases.containsKey(id)) {
      if (!seen.add(id)) throw const FormatException('Cyclic character alias');
      id = aliases[id]!;
    }
    return id;
  }

  CastEntry? character(String work, String id) =>
      _works[workId(work)]?[_castId(workId(work), id)];
  Iterable<CastEntry> entries(String work) =>
      _works[workId(work)]?.values ?? const [];
  Map<String, String> redirects(String work) =>
      Map.unmodifiable(_redirects[workId(work)] ?? {});

  void mergeEvidence(String key, CharacterCastRegistry evidence) {
    final work = workId(key);
    final records = _works.putIfAbsent(work, () => {});
    for (final incoming in evidence.entries) {
      final id = _castId(work, incoming.castId);
      records[id] = _mergeRecord(records[id], incoming, work, id);
    }
    for (final redirect in evidence.castIdRedirects.entries) {
      final old = records[_castId(work, redirect.key)],
          target = records[_castId(work, redirect.value)];
      if (old?.castId == target?.castId) continue;
      if (old == null || target == null) continue;
      var state = target.characterState;
      final a = old.selectedVoice, b = target.selectedVoice;
      if (a.mode == VoiceSelectionMode.explicit &&
          b.mode == VoiceSelectionMode.explicit &&
          a.voiceId != b.voiceId) {
        records[target.castId] = target.withCharacterState(
          state.copyWith(
            selectionConflicts: [
              ...state.selectionConflicts.where((v) => v.voiceId != a.voiceId),
              a,
            ],
          ),
        );
        continue; // Distinct selected voices require explicit reconciliation.
      }
      if (b.revision == 0 && a.revision > 0) {
        state = state.copyWith(selectedVoice: a);
      }
      final merged = _mergeRecord(old, target, work, target.castId);
      records[target.castId] = merged.withCharacterState(
        merged.characterState.copyWith(
          revision:
              (old.revision > target.revision
                  ? old.revision
                  : target.revision) +
              1,
          selectedVoice: state.selectedVoice,
          automaticVoices: {
            ...old.characterState.automaticVoices,
            ...state.automaticVoices,
          },
        ),
      );
      (_redirects[work] ??= {})[old.castId] = target.castId;
      records.remove(old.castId);
    }
  }

  CastEntry _mergeRecord(
    CastEntry? old,
    CastEntry incoming,
    String work,
    String id,
  ) {
    final prior = old?.characterState ?? CharacterState(workId: work);
    // The legacy provider publishes cumulative compact profiles. Do not sum its
    // counts again, or let a sparse later fragment erase stronger evidence.
    int rank(CharacterIdentityProfile? p) => p == null
        ? -1
        : switch (p.genderSource) {
            CharacterGenderEvidenceSource.explicitIdentity => 4,
            CharacterGenderEvidenceSource.explicitApposition => 3,
            CharacterGenderEvidenceSource.descriptor => 2,
            CharacterGenderEvidenceSource.pronoun => 1,
            CharacterGenderEvidenceSource.unknown =>
              p.genderIdentityLabel == CharacterGenderIdentityLabel.unknown
                  ? -1
                  : 0,
          };
    final profile = rank(incoming.identityProfile) >= rank(old?.identityProfile)
        ? incoming.identityProfile
        : old?.identityProfile;
    final presented = <String, ScopedGenderEvidence>{
      for (final e in [...prior.presentedGender, ...incoming.presentedGender])
        '${e.sourceRevision}:${e.segmentIds.join(',')}': e,
    };
    return CastEntry(
      castId: id,
      roleKind: incoming.roleKind,
      displayLabel: incoming.confidence > 0
          ? incoming.displayLabel
          : old?.displayLabel ?? incoming.displayLabel,
      confidence: incoming.confidence,
      provenance: incoming.provenance,
      observedAliases: {
        ...?old?.observedAliases,
        ...incoming.observedAliases,
      }.toList(),
      attributionIds: {
        ...?old?.attributionIds,
        ...incoming.attributionIds,
      }.toList(),
      identityProfile: profile,
      characterState: prior.copyWith(
        workId: work,
        revision: prior.revision + 1,
        explicitGender: prior.explicitGender.merge(incoming.explicitGender),
        implicitGender: prior.implicitGender.merge(incoming.implicitGender),
        presentedGender: presented.values.toList(),
      ),
    );
  }

  /// Explicit document import may seed durable choices. Provider publications
  /// cannot. Existing local selections or Reset tombstones always win over an
  /// imported snapshot; their revision counters are not globally comparable.
  void restoreDocument(String key, CharacterCastRegistry snapshot) {
    final savedWork = snapshot.entries
        .map((e) => e.workId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (savedWork.length > 1) {
      throw const FormatException('Mixed work identities');
    }
    if (savedWork.isNotEmpty) associate(savedWork.single, key);
    final work = workId(key);
    final records = _works.putIfAbsent(work, () => {});
    for (final incoming in snapshot.entries) {
      final old = character(work, incoming.castId);
      if (old == null) {
        records[incoming.castId] = incoming.withCharacterState(
          incoming.characterState.copyWith(workId: work),
        );
      } else if (old.selectedVoice.revision == 0 &&
          incoming.selectedVoice.revision > 0) {
        records[old.castId] = old.withCharacterState(
          old.characterState.copyWith(selectedVoice: incoming.selectedVoice),
        );
      }
    }
    mergeEvidence(work, snapshot);
  }

  void select(
    String key,
    String castId,
    String? voiceId, {
    String provenance = 'user',
  }) {
    final work = workId(key),
        old = character(key, castId) ?? _placeholder(key, castId);
    final choice = VoiceSelection(
      mode: voiceId == null
          ? VoiceSelectionMode.automatic
          : VoiceSelectionMode.explicit,
      voiceId: voiceId,
      revision: old.selectedVoice.revision + 1,
      provenance: provenance,
    );
    (_works[work] ??= {})[old.castId] = old.withCharacterState(
      old.characterState.copyWith(
        workId: work,
        revision: old.revision + 1,
        selectedVoice: choice,
        automaticVoices: {},
        selectionConflicts: [],
      ),
    );
  }

  CastEntry _placeholder(String work, String id) => CastEntry(
    castId: id,
    roleKind: id == 'cast_narrator'
        ? CastEntryRoleKind.narrator
        : CastEntryRoleKind.character,
    displayLabel: id,
    confidence: 0,
    provenance: CastEntryProvenance.sourceMetadata,
    characterState: CharacterState(workId: workId(work)),
  );

  void migrateLegacy(Map<String, Map<String, String>> values) {
    for (final work in values.entries) {
      for (final choice in work.value.entries) {
        if ((character(work.key, choice.key)?.selectedVoice.revision ?? 0) ==
            0) {
          select(work.key, choice.key, choice.value, provenance: 'legacy');
        }
      }
    }
  }

  /// Work/source aliases join physical graph identities without changing the
  /// stable workId. Source-owned selections (including Reset) win at EOF.
  void associate(String source, String canonical) {
    final from = workId(source), to = workId(canonical);
    if (from == to) return;
    final records = _works.putIfAbsent(from, () => {});
    for (final entry in (_works[to] ?? <String, CastEntry>{}).entries) {
      final current = records[entry.key];
      final merged = _mergeRecord(
        entry.value,
        current ?? entry.value,
        from,
        entry.key,
      );
      final selected = current != null && current.selectedVoice.revision > 0
          ? current.selectedVoice
          : entry.value.selectedVoice;
      records[entry.key] = merged.withCharacterState(
        merged.characterState.copyWith(
          revision:
              ((current?.revision ?? 0) > entry.value.revision
                  ? current!.revision
                  : entry.value.revision) +
              1,
          selectedVoice: selected,
          automaticVoices: {
            ...entry.value.characterState.automaticVoices,
            ...?current?.characterState.automaticVoices,
          },
        ),
      );
    }
    (_redirects[from] ??= {}).addAll(_redirects.remove(to) ?? {});
    _works.remove(to);
    _workAliases[to] = from;
    _workAliases[canonical] = from;
    if (_activeWork == to) _activeWork = from;
  }

  CharacterCastRegistry registry(String key, {required String documentId}) {
    final records = entries(key).toList();
    if (!records.any((e) => e.roleKind == CastEntryRoleKind.narrator)) {
      records.insert(0, _placeholder(key, 'cast_narrator'));
    }
    return CharacterCastRegistry(
      documentId: documentId,
      registryVersion: 'work-character-v1',
      entries: records,
      castIdRedirects: redirects(key),
    );
  }

  CastVoiceAssignmentSet resolve({
    required String workId,
    required String engineId,
    required List<VoiceProfile> voices,
    required String narratorVoiceId,
    CharacterCastRegistry? evidence,
    Map<String, String>? capturedChoices,
    Set<String> editedCastIds = const {},
  }) {
    final work = this.workId(workId);
    final graph = registry(work, documentId: evidence?.documentId ?? work);
    final available = {for (final v in voices) v.id: v};
    final automatic = <String, String>{};
    final explicit = <String, String>{};
    for (final e in graph.entries) {
      final selected =
          capturedChoices?[e.castId] ??
          (capturedChoices == null ? e.selectedVoice.voiceId : null);
      if (selected != null) explicit[e.castId] = selected;
      final previous = e.characterState.automaticVoices[engineId];
      final voice = available[previous];
      if (e.roleKind != CastEntryRoleKind.narrator &&
          voice != null &&
          (e.inferredGender == null ||
              e.identityProfile?.conflictFlag == true ||
              e.inferredGender == VoiceGender.neutral ||
              voice.gender == e.inferredGender)) {
        automatic[e.castId] = previous!;
      }
    }
    final assigned = const CastVoiceAssignmentService().resolve(
      CastVoiceAssignmentInput(
        characterCastRegistry: graph,
        availableVoices: voices,
        fallbackVoiceId: narratorVoiceId,
        preferredNarratorVoiceId: narratorVoiceId,
        storedAssignments: {
          for (final e in explicit.entries)
            if (!editedCastIds.contains(e.key)) e.key: e.value,
        },
        userOverrides: {
          for (final e in explicit.entries)
            if (editedCastIds.contains(e.key)) e.key: e.value,
        },
        automaticAssignments: automatic,
      ),
    );
    for (final a in assigned.assignments) {
      final old = character(work, a.castId);
      if (old == null ||
          a.automaticVoiceId == null ||
          old.characterState.automaticVoices[engineId] == a.automaticVoiceId) {
        continue;
      }
      _works[work]![old.castId] = old.withCharacterState(
        old.characterState.copyWith(
          automaticVoices: {
            ...old.characterState.automaticVoices,
            engineId: a.automaticVoiceId!,
          },
        ),
      );
    }
    return assigned;
  }

  Map<String, String> selections(String work) => Map.unmodifiable({
    for (final e in entries(work))
      if (e.selectedVoice.mode == VoiceSelectionMode.explicit)
        e.castId: e.selectedVoice.voiceId!,
  });
  Map<String, Map<String, String>> get legacySelections => Map.unmodifiable({
    for (final key in {..._works.keys, ..._workAliases.keys})
      if (selections(key).isNotEmpty) key: selections(key),
  });
  CharacterStoreSnapshot snapshot() => CharacterStoreSnapshot._(this);
  Map<String, Object?> toJson() => {
    'schema': 1,
    'aliases': Map.of(_workAliases),
    'redirects': {for (final e in _redirects.entries) e.key: Map.of(e.value)},
    'works': {
      for (final w in _works.entries)
        w.key: w.value.values.map(encodeCharacter).toList(),
    },
  };
  WorkCharacterStore();
  factory WorkCharacterStore.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1) {
      throw const FormatException('Unsupported work character schema');
    }
    final result = WorkCharacterStore();
    result._workAliases.addAll(Map<String, String>.from(json['aliases']));
    for (final w in (json['works'] as Map).entries) {
      result._works[w.key] = {
        for (final raw in w.value as List)
          (raw as Map)['castId'] as String: decodeCharacter(
            Map<String, dynamic>.from(raw),
          ),
      };
    }
    for (final r in (json['redirects'] as Map).entries) {
      result._redirects[r.key] = Map<String, String>.from(r.value);
    }
    for (final key in result._workAliases.keys) {
      result.workId(key);
    }
    for (final w in result._works.entries) {
      for (final e in w.value.values) {
        if (e.workId != w.key) {
          throw const FormatException('Mismatched character work');
        }
      }
      for (final id in result._redirects[w.key]?.keys ?? <String>[]) {
        if (!w.value.containsKey(result._castId(w.key, id))) {
          throw const FormatException('Missing character alias target');
        }
      }
    }
    return result;
  }
}

/// Immutable handoff for the existing one-active/one-pending save pump. Capture
/// copies record references only; recursive encoding/validation runs off UI.
class CharacterStoreSnapshot {
  CharacterStoreSnapshot._(WorkCharacterStore owner)
    : _works = Map.unmodifiable({
        for (final w in owner._works.entries)
          w.key: Map<String, CastEntry>.unmodifiable(w.value),
      }),
      _aliases = Map.unmodifiable(owner._workAliases),
      _redirects = Map.unmodifiable({
        for (final w in owner._redirects.entries)
          w.key: Map<String, String>.unmodifiable(w.value),
      });
  final Map<String, Map<String, CastEntry>> _works;
  final Map<String, String> _aliases;
  final Map<String, Map<String, String>> _redirects;
  WorkCharacterStore restore() {
    final owner = WorkCharacterStore();
    for (final w in _works.entries) {
      owner._works[w.key] = Map.of(w.value);
    }
    owner._workAliases.addAll(_aliases);
    for (final w in _redirects.entries) {
      owner._redirects[w.key] = Map.of(w.value);
    }
    return owner;
  }

  Map<String, Object?> toJson() => restore().toJson();
}
