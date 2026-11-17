import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/offline_cache.dart';
import 'package:wenku8_flutter/offline_repository.dart';

import 'support/offline_fixture.dart';

const _a = 'https://images.example.invalid/1/a.jpg';
const _b = 'https://images.example.invalid/1/b.jpg';
const _c = 'https://images.example.invalid/2/c.jpg';

String _image(String url) => '<!--image-->$url<!--image-->';

Novel _illustratedBook({bool missingAddress = false}) =>
    offlineFixtureBook(71).withChapters([
      NovelChapter(
        '第一章',
        [
          '第一章正文',
          _image(_a),
          _image(_b),
          if (missingAddress) '[插图]',
          '第一章结尾',
        ].join('\n\n'),
        id: 71001,
      ),
      NovelChapter(
        '第二章',
        ['第二章正文', _image(_a), _image(_c), '第二章结尾'].join('\n\n'),
        id: 71002,
      ),
      const NovelChapter('第三章', '第三章正文，前一张插图失败后仍会保存。', id: 71003),
    ]);

class _IllustrationSource {
  final calls = <String>[];
  final failures = <String, Object>{};
  final held = <String, Completer<Uint8List>>{};

  Future<Uint8List> call(String url) async {
    calls.add(url);
    final failure = failures[url];
    if (failure != null) throw failure;
    final pending = held[url];
    if (pending != null) return pending.future;
    return Uint8List.fromList(utf8.encode('image:$url'));
  }
}

void main() {
  late Directory root;
  late OfflineCacheStore cache;
  late OfflineFixtureRepository remote;
  late _IllustrationSource images;
  late OfflineNovelRepository repository;
  late Novel novel;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('novel8-image-recovery-');
    cache = OfflineCacheStore(root);
    remote = OfflineFixtureRepository();
    images = _IllustrationSource();
    novel = _illustratedBook();
    remote.books[71] = novel;
    repository = OfflineNovelRepository(
      remote: remote,
      cache: cache,
      illustrationRequest: images.call,
    );
  });

  tearDown(() async {
    repository.dispose();
    cache.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'successful bodies and unique illustrations complete independently',
    () async {
      repository.download(novel);
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.completed,
      );
      final job = repository.jobFor(71)!;
      final saved = cache.book(71)!;
      expect(job.completed, 3);
      expect(job.total, 3);
      expect(job.illustrations, 3);
      expect(job.illustrationTotal, 3);
      expect(job.illustrationFailures, isEmpty);
      expect(saved.cachedCount, 3);
      expect(saved.illustrationBytes.keys, {_a, _b, _c});
      expect(images.calls, [_a, _b, _c]);
      expect(remote.calls.where((call) => call.startsWith('text:')).length, 3);
    },
  );

  test(
    'one HTTP failure and a missing address do not stop later work',
    () async {
      novel = _illustratedBook(missingAddress: true);
      remote.books[71] = novel;
      images.failures[_a] = const LegacyIllustrationException(
        '插图服务返回 HTTP 503',
        kind: 'http',
        statusCode: 503,
      );
      repository.download(novel);
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.failed,
      );
      final job = repository.jobFor(71)!;
      final saved = cache.book(71)!;
      final failure = job.illustrationFailures[_a]!;
      expect(job.completed, 3);
      expect(job.illustrations, 2);
      expect(job.illustrationTotal, 3);
      expect(job.missingIllustrationAddresses, 1);
      expect(failure.kind, 'http');
      expect(failure.statusCode, 503);
      expect(failure.message, contains('HTTP 503'));
      expect(job.label, contains('正文 3 / 3 章'));
      expect(job.label, contains('插图 2 / 3'));
      expect(job.label, contains('1 处插图地址未返回'));
      expect(job.label, contains('HTTP 503'));
      expect(saved.cachedCount, 3);
      expect(saved.illustrationBytes.keys, {_b, _c});
      expect(saved.illustrationFailures[_a]!.statusCode, 503);
      expect(images.calls, [_a, _b, _c]);
      expect(remote.calls, contains('text:71:71002'));
      expect(remote.calls, contains('text:71:71003'));
    },
  );

  test('retry skips committed bodies and illustrations', () async {
    images.failures[_a] = const LegacyIllustrationException(
      '插图服务返回 HTTP 503',
      kind: 'http',
      statusCode: 503,
    );
    repository.download(novel);
    await offlineWaitUntil(
      () => repository.jobFor(71)!.phase == DownloadPhase.failed,
    );
    expect(cache.book(71)!.cachedCount, 3);
    images.failures.remove(_a);
    images.calls.clear();
    repository.retry(71);
    await offlineWaitUntil(
      () => repository.jobFor(71)!.phase == DownloadPhase.completed,
    );
    expect(images.calls, [_a]);
    expect(remote.calls.where((call) => call.startsWith('text:')).length, 3);
    expect(repository.jobFor(71)!.illustrations, 3);
    expect(cache.book(71)!.illustrationFailures, isEmpty);
    expect(cache.book(71)!.illustrationBytes.keys, {_a, _b, _c});
  });

  test(
    'restart restores a manifest-only repair without remote book calls',
    () async {
      images.failures[_a] = const LegacyIllustrationException(
        '插图服务返回 HTTP 503',
        kind: 'http',
        statusCode: 503,
      );
      repository.download(novel);
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.failed,
      );
      final manifest =
          jsonDecode(await File('${root.path}/b71/images.json').readAsString())
              as Map<String, dynamic>;
      expect(manifest['version'], 2);
      expect(manifest['failures'], isA<Map<String, dynamic>>());

      repository.dispose();
      cache.dispose();
      cache = OfflineCacheStore(root);
      repository = OfflineNovelRepository(
        remote: remote,
        cache: cache,
        illustrationRequest: images.call,
      );
      remote.calls.clear();
      images.calls.clear();
      images.failures.remove(_a);
      await repository.loadCache();
      final restored = repository.jobFor(71)!;
      expect(restored.phase, DownloadPhase.failed);
      expect(restored.repairsOnly, isTrue);
      expect(restored.illustrationFailures.keys, {_a});
      repository.retry(71);
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.completed,
      );
      expect(remote.calls, isEmpty);
      expect(images.calls, [_a]);
      expect(cache.book(71)!.cachedCount, 3);
      expect(cache.book(71)!.illustrationBytes.keys, {_a, _b, _c});
      expect(cache.book(71)!.illustrationFailures, isEmpty);
    },
  );

  test(
    'cancel suppresses a late illustration and stops subsequent requests',
    () async {
      final pending = Completer<Uint8List>();
      images.held[_a] = pending;
      repository.download(novel);
      await offlineWaitUntil(() => images.calls.length == 1);
      repository.cancel(71);
      pending.complete(Uint8List.fromList(const [1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repository.jobFor(71)!.phase, DownloadPhase.cancelled);
      expect(cache.book(71)!.cachedCount, 1);
      expect(await cache.hasIllustration(71, _a), isFalse);
      expect(cache.book(71)!.illustrationFailures, isEmpty);
      expect(images.calls, [_a]);
      expect(remote.calls.where((call) => call.startsWith('text:')), [
        'text:71:71001',
      ]);

      images.held.remove(_a);
      repository.retry(71);
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.completed,
      );
      expect(cache.book(71)!.cachedCount, 3);
      expect(cache.book(71)!.illustrationBytes.keys, {_a, _b, _c});
    },
  );

  test(
    'deleting during an illustration request rejects the old generation',
    () async {
      final pending = Completer<Uint8List>();
      images.held[_a] = pending;
      repository.download(novel);
      await offlineWaitUntil(() => images.calls.length == 1);
      await repository.removeCachedBook(71);
      pending.complete(Uint8List.fromList(const [1, 2, 3]));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repository.jobFor(71), isNull);
      expect(await cache.readBook(71), isNull);
      expect(await cache.readIllustration(_a), isNull);
      expect(images.calls, [_a]);
      expect(remote.calls, isNot(contains('text:71:71002')));
    },
  );

  test(
    'v1 illustration manifests remain readable and skip completed media',
    () async {
      final chapter = novel.chapters.first;
      final bytes = Uint8List.fromList(const [1, 2, 3]);
      final epoch = cache.epochFor(71);
      await cache.saveBook(novel, epoch: epoch);
      await cache.saveChapter(71, chapter.id, chapter.content, epoch: epoch);
      await cache.saveIllustration(71, _a, bytes, epoch: epoch);
      await File('${root.path}/b71/images.json').writeAsString(
        jsonEncode({
          'version': 1,
          'images': {_a: bytes.length},
        }),
      );

      repository.dispose();
      cache.dispose();
      cache = OfflineCacheStore(root);
      repository = OfflineNovelRepository(
        remote: remote,
        cache: cache,
        illustrationRequest: images.call,
      );
      await repository.loadCache();
      expect(cache.book(71)!.illustrationBytes[_a], bytes.length);
      expect(cache.book(71)!.illustrationFailures, isEmpty);
      repository.download(novel, chapterIds: {chapter.id});
      await offlineWaitUntil(
        () => repository.jobFor(71)!.phase == DownloadPhase.completed,
      );
      expect(images.calls, [_b]);
      expect(remote.calls.where((call) => call.startsWith('text:')), isEmpty);
      expect(await cache.hasIllustration(71, _a), isTrue);
      expect(await cache.hasIllustration(71, _b), isTrue);
    },
  );
}
