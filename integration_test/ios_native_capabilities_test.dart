import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wenku8_flutter/listening/cache.dart';
import 'package:wenku8_flutter/listening/edge_tts.dart';
import 'package:wenku8_flutter/listening/models.dart';
import 'package:wenku8_flutter/local_platform.dart';
import 'package:wenku8_flutter/network_status.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native network path emits a real online state', (tester) async {
    final current = await NetworkStatus.methods.invokeMethod<String>('current');
    expect(current, 'online');
    final event = await NetworkStatus.events
        .receiveBroadcastStream()
        .first
        .timeout(const Duration(seconds: 5));
    expect(event, 'online');
  });

  testWidgets('cloud connection vault survives a new channel client', (
    tester,
  ) async {
    const channel = MethodChannel('org.mewx.wenku8/cloud_sources');
    addTearDown(() => channel.invokeMethod<void>('write', null));
    const fixture = '[{"kind":"quark","cookie":"__puus=native-test"}]';
    await channel.invokeMethod<void>('write', fixture);
    expect(
      await const MethodChannel(
        'org.mewx.wenku8/cloud_sources',
      ).invokeMethod<String>('read'),
      fixture,
    );
    await channel.invokeMethod<void>('write', null);
    expect(await channel.invokeMethod<String>('read'), isNull);
  });

  testWidgets(
    'Apple Chinese speech is synthesized and played to completion',
    (tester) async {
      final root = await getTemporaryDirectory();
      final directory = Directory('${root.path}/native-speech-test');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final cache = SpeechAudioCache(directory, EdgeSpeechClient());
      const text = '这是苹果系统语音测试。';
      const voice = SpeechVoice(
        id: '@default',
        label: 'Apple',
        source: ListeningSource.system,
        engine: '@default',
      );
      final file = await cache.prepare(
        SpeechSegment(0, 0, text.length, text, language: 'zh'),
        voice,
        SpeechCancellation(),
      );
      expect(await file.length(), greaterThan(100));
      final bytes = await file.readAsBytes();
      expect(['RIFF', 'caff'], contains(String.fromCharCodes(bytes.take(4))));
      final player = AudioPlayer();
      addTearDown(player.dispose);
      final duration = await player.setFilePath(file.path);
      expect(duration, isNotNull);
      expect(duration, greaterThan(Duration.zero));
      await player.setSpeed(2);
      await player.play().timeout(const Duration(seconds: 20));
      expect(player.processingState, ProcessingState.completed);
      final replay = await cache.prepare(
        SpeechSegment(0, 0, text.length, text, language: 'zh'),
        voice,
        SpeechCancellation(),
      );
      expect(replay.path, file.path);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets('native sync channel disconnects cleanly without a selection', (
    tester,
  ) async {
    const channel = MethodChannel('org.mewx.wenku8/book_documents');
    await channel.invokeMethod<void>('disconnectSync');
    expect(
      await channel.invokeMapMethod<String, dynamic>('syncInfo'),
      isNull,
    );
  });

  testWidgets('native keep-screen state applies and releases', (tester) async {
    await LocalPlatform.channel.invokeMethod<void>('keepScreenOn', true);
    expect(await LocalPlatform.getKeepScreenOn(), isTrue);
    await LocalPlatform.channel.invokeMethod<void>('keepScreenOn', false);
    expect(await LocalPlatform.getKeepScreenOn(), isFalse);
  });
}
