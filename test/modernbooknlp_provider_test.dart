import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:read_aloud/src/services/modernbooknlp_provider.dart';

void main() {
  late Directory root;
  late ModernBookNlpProvider provider;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('nlp-protocol-');
    final helper = File('${root.path}/worker.rb');
    await helper.writeAsString(r'''
require 'json'
r=JSON.parse(STDIN.readline)
File.write(ARGV[0]+'/pid',Process.pid)
if r['text']=='block'
  sleep 30
elsif r['text']=='oversize'
  puts 'x'*(1024*1024+1)
else
  r['sourceRevision']='obsolete' if r['text']=='stale'
  puts JSON.generate(r.merge('ok'=>true,'providerId'=>'modernbooknlp-joint','providerVersion'=>'84f1f34f6f0ec7c6e9c558b4371e61ea2354d95b','modelIdentity'=>'a32c85b99e6491f559e0c46c6257b18be0a39a06c15c281389ca0934c229cfb2','adapterVersion'=>'readaloud-cpu-1','entities'=>[],'quotes'=>[]))
end
''');
    final executable = File('${root.path}/python');
    await executable.writeAsString(
      '#!/bin/sh\nshift\nshift\nexec /usr/bin/ruby "\$@"\n',
    );
    await Process.run('/bin/chmod', ['+x', executable.path]);
    provider = ModernBookNlpProvider(
      pythonPath: executable.path,
      helperPath: helper.path,
      runtimePath: root.path,
      timeout: const Duration(milliseconds: 800),
    );
  });
  tearDown(() async {
    await provider.close();
    await root.delete(recursive: true);
  });
  ModernBookNlpRequest request(String text) => ModernBookNlpRequest(
    requestId: 'r',
    ownerId: 'owner',
    workId: 'work',
    sourceRevision: 'source',
    analysisRevision: 1,
    sequence: 1,
    text: text,
  );
  Future<void> started() async {
    for (var i = 0; i < 100 && !await File('${root.path}/pid').exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await File('${root.path}/pid').exists(), isTrue);
  }

  Future<void> reaped() async {
    final pid = int.parse(await File('${root.path}/pid').readAsString());
    expect((await Process.run('/bin/kill', ['-0', '$pid'])).exitCode, isNot(0));
  }

  test(
    'bounded protocol accepts current output and rejects stale identity',
    () async {
      expect((await provider.analyze(request('valid')))['ok'], true);
      await reaped();
      await expectLater(
        provider.analyze(request('stale')),
        throwsFormatException,
      );
    },
  );
  test(
    'cancellation is out of band, reaps child, and allows next window',
    () async {
      final active = provider.analyze(request('block'));
      final check = expectLater(active, throwsA(isA<ModernBookNlpCancelled>()));
      await started();
      await expectLater(provider.analyze(request('second')), throwsStateError);
      await provider.cancel();
      await check;
      await reaped();
      expect((await provider.analyze(request('next')))['ok'], true);
    },
  );
  test('deadline kills and reaps uncooperative child', () async {
    await expectLater(
      provider.analyze(request('block')),
      throwsA(isA<TimeoutException>()),
    );
    await reaped();
  });
  test('oversized output is bounded and child is reaped', () async {
    await expectLater(provider.analyze(request('oversize')), throwsStateError);
    await reaped();
  });
  test(
    'close during process startup waits for cancellation and prevents reuse',
    () async {
      final active = provider.analyze(request('block'));
      final checked = expectLater(
        active,
        throwsA(isA<ModernBookNlpCancelled>()),
      );
      await provider.close();
      await checked;
      await expectLater(provider.analyze(request('later')), throwsStateError);
    },
  );
  test('UTF-16 admission and output coordinates preserve non-BMP text', () {
    expect(() => request('a' * 16385), throwsArgumentError);
    final output =
        jsonDecode(
              '{"entities":[{"entityId":"1","mentions":[{"startUtf16":2,"endUtf16":5,"text":"Ada"}]}],"quotes":[]}',
            )
            as Map<String, dynamic>;
    validateModernBookNlpResult(output, '😀Ada');
    output['entities'][0]['mentions'][0]['startUtf16'] = 1;
    expect(
      () => validateModernBookNlpResult(output, '😀Ada'),
      throwsFormatException,
    );
  });
}
