import '../models/english_pronunciation_profile.dart';
import '../models/pronunciation_artifact.dart';
import 'pronunciation_lexical_resources.dart';

enum PronunciationResourceLayerKind {
  globalEnglish,
  baseVariant,
  overlayProfile,
  sourceMetadata,
  userOverride,
}

class MergedPronunciationResources {
  const MergedPronunciationResources({
    required this.selectedProfileId,
    required this.entries,
    required this.winningLayerIds,
    required this.winningLayerKinds,
  });

  const MergedPronunciationResources.empty({this.selectedProfileId = 'en-us-core'})
    : entries = const <String, List<PronunciationRepresentation>>{},
      winningLayerIds = const <String, String>{},
      winningLayerKinds = const <String, PronunciationResourceLayerKind>{};

  final String selectedProfileId;
  final Map<String, List<PronunciationRepresentation>> entries;
  final Map<String, String> winningLayerIds;
  final Map<String, PronunciationResourceLayerKind> winningLayerKinds;

  List<PronunciationRepresentation>? operator [](String lexicalTarget) {
    return entries[lexicalTarget];
  }

  String? winningLayerIdFor(String lexicalTarget) {
    return winningLayerIds[lexicalTarget];
  }

  PronunciationResourceLayerKind? winningLayerKindFor(String lexicalTarget) {
    return winningLayerKinds[lexicalTarget];
  }
}

class PronunciationResourceLayeringInput {
  const PronunciationResourceLayeringInput({
    required this.profile,
    this.sourceMetadataResources =
        const <String, List<PronunciationRepresentation>>{},
    this.userOverrideResources =
        const <String, List<PronunciationRepresentation>>{},
  });

  final EnglishPronunciationProfile profile;
  final Map<String, List<PronunciationRepresentation>> sourceMetadataResources;
  final Map<String, List<PronunciationRepresentation>> userOverrideResources;
}

class PronunciationResourceLayeringService {
  const PronunciationResourceLayeringService({
    this.defaultLayers = defaultPronunciationResourceLayers,
  });

  final Map<String, Map<String, List<PronunciationRepresentation>>>
  defaultLayers;

  MergedPronunciationResources merge(PronunciationResourceLayeringInput input) {
    final mergedEntries = <String, List<PronunciationRepresentation>>{};
    final winningLayerIds = <String, String>{};
    final winningLayerKinds = <String, PronunciationResourceLayerKind>{};

    void applyLayer({
      required String layerId,
      required PronunciationResourceLayerKind layerKind,
      required Map<String, List<PronunciationRepresentation>> resources,
    }) {
      for (final entry in resources.entries) {
        mergedEntries[entry.key] = List<PronunciationRepresentation>.unmodifiable(
          entry.value,
        );
        winningLayerIds[entry.key] = layerId;
        winningLayerKinds[entry.key] = layerKind;
      }
    }

    applyLayer(
      layerId: 'global-en',
      layerKind: PronunciationResourceLayerKind.globalEnglish,
      resources: defaultLayers['global-en'] ?? const {},
    );

    for (final layerId in input.profile.resourceLayerIds) {
      if (layerId == 'global-en') {
        continue;
      }
      final layerKind = input.profile.isOverlayProfile &&
              input.profile.resourceLayerIds.last == layerId
          ? PronunciationResourceLayerKind.overlayProfile
          : PronunciationResourceLayerKind.baseVariant;
      applyLayer(
        layerId: layerId,
        layerKind: layerKind,
        resources: defaultLayers[layerId] ?? const {},
      );
    }

    applyLayer(
      layerId: 'source-metadata',
      layerKind: PronunciationResourceLayerKind.sourceMetadata,
      resources: input.sourceMetadataResources,
    );
    applyLayer(
      layerId: 'user-override',
      layerKind: PronunciationResourceLayerKind.userOverride,
      resources: input.userOverrideResources,
    );

    return MergedPronunciationResources(
      selectedProfileId: input.profile.profileId,
      entries: Map<String, List<PronunciationRepresentation>>.unmodifiable(
        mergedEntries,
      ),
      winningLayerIds: Map<String, String>.unmodifiable(winningLayerIds),
      winningLayerKinds:
          Map<String, PronunciationResourceLayerKind>.unmodifiable(
            winningLayerKinds,
          ),
    );
  }
}
