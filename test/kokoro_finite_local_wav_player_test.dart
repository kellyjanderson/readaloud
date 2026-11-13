import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:read_aloud/src/services/kokoro_tts_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const mainChannel = MethodChannel('com.ryanheise.just_audio.methods');
  const sessionChannel = MethodChannel('com.ryanheise.audio_session');
  final nativeRequests = <Map<dynamic, dynamic>>[];
  final nativeCalls = <String>[];
  final ownedChannels = <MethodChannel>[];

  setUp(() {
    nativeRequests.clear();
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      if (call.method == 'init') {
        final request = Map<dynamic, dynamic>.from(call.arguments as Map);
        nativeRequests.add(request);
        final id = request['id'] as String;
        final methods = MethodChannel('com.ryanheise.just_audio.methods.$id');
        final events = MethodChannel('com.ryanheise.just_audio.events.$id');
        final data = MethodChannel('com.ryanheise.just_audio.data.$id');
        ownedChannels.addAll([methods, events, data]);
        messenger.setMockMethodCallHandler(events, (_) async => null);
        messenger.setMockMethodCallHandler(data, (_) async => null);
        messenger.setMockMethodCallHandler(methods, (call) async {
          nativeCalls.add(call.method);
          if (call.method == 'load') {
            await messenger.handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope({
                'processingState': 3,
                'updateTime': 0,
                'updatePosition': 0,
                'bufferedPosition': 1000000,
                'duration': 1000000,
                'currentIndex': 0,
              }),
              (_) {},
            );
            return {'duration': 1000000};
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(mainChannel, null);
    messenger.setMockMethodCallHandler(sessionChannel, null);
    for (final channel in ownedChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    ownedChannels.clear();
  });

  for (final optIn in [false, true]) {
    test(
      'native init owns immutable finite WAV opt-in=$optIn before load and after stop',
      () async {
        final player = AudioPlayer(
          readAloudFiniteLocalWavQueue: optIn,
          handleInterruptions: false,
          handleAudioSessionActivation: false,
        );
        addTearDown(player.dispose);
        expect(player.readAloudFiniteLocalWavQueue, optIn);
        expect(
          nativeRequests,
          isEmpty,
          reason: 'construction must remain idle',
        );
        await player.setAudioSources([
          AudioSource.uri(Uri.file('/owned-speech.data')),
        ]);
        expect(nativeRequests, hasLength(1));
        expect(
          nativeRequests.single['readAloudFiniteLocalWavQueue'],
          Platform.isMacOS && optIn ? isTrue : isNull,
        );
        await player.stop();
        await player.load();
        expect(nativeRequests, hasLength(2));
        expect(nativeRequests.last['id'], isNot(nativeRequests.first['id']));
        expect(
          nativeRequests.last['readAloudFiniteLocalWavQueue'],
          Platform.isMacOS && optIn ? isTrue : isNull,
        );
      },
    );
  }

  test('only the internally owned macOS engine player opts in', () async {
    final owned = KokoroTtsEngine();
    expect(owned.debugFiniteLocalWavQueue, Platform.isMacOS);
    owned.dispose();
    for (final optIn in [false, true]) {
      final player = AudioPlayer(readAloudFiniteLocalWavQueue: optIn);
      final injected = KokoroTtsEngine(player: player);
      expect(
        injected.debugFiniteLocalWavQueue,
        optIn,
        reason: 'injection must preserve the caller policy',
      );
      injected.dispose();
      await player.dispose();
    }
    expect(
      nativeRequests,
      isEmpty,
      reason: 'engine constructor does not initialize native playback',
    );
  });

  test(
    'opted-in rejection preserves logical playlist and native calls',
    () async {
      final player = AudioPlayer(readAloudFiniteLocalWavQueue: true);
      addTearDown(player.dispose);
      final local = AudioSource.uri(Uri.file('/owned-speech.data'));
      await player.setAudioSources([local]);
      final callsBefore = List.of(nativeCalls);
      final unsupported = <AudioSource>[
        ProgressiveAudioSource(Uri.parse('https://example.test/speech.wav')),
        ProgressiveAudioSource(Uri.parse('file://remote/tmp/speech.wav')),
        ProgressiveAudioSource(Uri.parse('file:///tmp/speech.wav?variant=1')),
        ProgressiveAudioSource(Uri.parse('file:///tmp/speech.wav#part')),
        HlsAudioSource(Uri.file('/stream.data')),
        ClippingAudioSource(
          child: ProgressiveAudioSource(Uri.file('/speech.data')),
        ),
        // ignore: deprecated_member_use
        LoopingAudioSource(
          child: ProgressiveAudioSource(Uri.file('/speech.data')),
          count: 2,
        ),
        // ignore: deprecated_member_use
        ConcatenatingAudioSource(
          children: [
            ProgressiveAudioSource(
              Uri.parse('https://example.test/future.wav'),
            ),
          ],
        ),
      ];
      for (final bad in unsupported) {
        await expectLater(player.setAudioSources([bad]), throwsArgumentError);
        await expectLater(player.addAudioSource(bad), throwsArgumentError);
        await expectLater(
          player.insertAudioSource(0, bad),
          throwsArgumentError,
        );
        await expectLater(
          player.addAudioSources([
            ProgressiveAudioSource(Uri.file('/valid.data')),
            bad,
          ]),
          throwsArgumentError,
        );
        await expectLater(
          player.insertAudioSources(0, [
            ProgressiveAudioSource(Uri.file('/valid.data')),
            bad,
          ]),
          throwsArgumentError,
        );
        expect(player.audioSources, [same(local)]);
        expect(nativeCalls, callsBefore);
      }
    },
    skip: !Platform.isMacOS,
  );

  test('generic player retains remote and wrapped playlist behavior', () async {
    final player = AudioPlayer();
    addTearDown(player.dispose);
    final remote = ProgressiveAudioSource(
      Uri.parse('https://example.test/speech.wav'),
    );
    final wrapped = ClippingAudioSource(
      child: ProgressiveAudioSource(Uri.file('/speech.data')),
    );
    await player.setAudioSources([remote], preload: false);
    await player.addAudioSource(wrapped);
    expect(player.audioSources, [same(remote), same(wrapped)]);
    expect(nativeRequests, isEmpty);
  });
}
