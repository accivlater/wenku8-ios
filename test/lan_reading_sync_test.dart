import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/catalog.dart';
import 'package:wenku8_flutter/lan_reading_sync.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/local_books.dart';

const _aId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _bId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _novel = Novel(
  id: 424242,
  title: '回环续读测试',
  author: '测试',
  genre: '',
  summary: '',
  colors: const [Colors.black],
  chapters: const [
    NovelChapter('第一章', '第一段正文。', id: 1),
    NovelChapter('第二章', '第二段正文。', id: 2),
  ],
);

class _MemoryPairings extends LanPairingStore {
  _MemoryPairings(this.value);
  Map<String, dynamic> value;

  @override
  Future<Map<String, dynamic>> read() async =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  @override
  Future<void> write(Map<String, dynamic> next) async {
    final encoded = jsonEncode(next);
    if (encoded.length > 20000) throw const FormatException('配对记录过大');
    value = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
  }
}

class _FakeDiscovery extends LanDiscovery {
  final _controller = StreamController<List<LanNearbyDevice>>.broadcast();

  @override
  Stream<List<LanNearbyDevice>> get changes => _controller.stream;

  @override
  Future<void> start(String id, int port) async {
    name = '测试设备 ${id.substring(0, 2)}';
    error = null;
    available = true;
  }

  @override
  Future<void> stop() async {
    available = false;
    error = null;
  }

  void emit(List<LanNearbyDevice> devices) => _controller.add(devices);

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}

class _Device {
  _Device(this.sync, this.state, this.books, this.discovery);
  final LanReadingSync sync;
  final LibraryState state;
  final LocalBookStore books;
  final _FakeDiscovery discovery;

  int get port => Uri.parse(sync.codeFor('127.0.0.1')!).port;
  LanNearbyDevice get nearby => LanNearbyDevice(
    id: sync.deviceId!,
    name: sync.deviceName,
    host: '127.0.0.1',
    port: port,
  );
}

Future<_Device> _makeDevice(
  Directory root,
  String folder,
  String id,
  int keyByte,
) async {
  SharedPreferences.setMockInitialValues({'lanReading.enabled.v1': true});
  final preferences = await SharedPreferences.getInstance();
  final state = LibraryState(preferences);
  final books = LocalBookStore(Directory('${root.path}/$folder'));
  await books.load();
  final discovery = _FakeDiscovery();
  final sync = LanReadingSync(
    state: state,
    preferences: preferences,
    books: books,
    port: 0,
    address: InternetAddress.loopbackIPv4,
    pairings: _MemoryPairings({
      'device': id,
      'key': base64Url.encode(List.filled(32, keyByte)),
    }),
    discovery: discovery,
  );
  final device = _Device(sync, state, books, discovery);
  addTearDown(() async {
    sync.closePairing();
    await sync.stop();
    sync.dispose();
    state.dispose();
    books.dispose();
  });
  await sync.initialize();
  if (sync.error != null) throw StateError(sync.error!);
  return device;
}

Future<void> _pair(_Device a, _Device b) async {
  a.sync.openPairing();
  b.sync.openPairing();
  await a.sync.pairNearby(b.nearby);
  await _waitFor(() => b.sync.pendingPairing != null);
  expect(a.sync.pendingPairing?.digits, b.sync.pendingPairing?.digits);
  await a.sync.confirmPairing();
  await b.sync.confirmPairing();
  await _waitFor(() => a.sync.peers.length == 1 && b.sync.peers.length == 1);
  expect(a.sync.peers.single.deviceId, b.sync.deviceId);
  expect(b.sync.peers.single.deviceId, a.sync.deviceId);
  expect(a.sync.pendingPairing, isNull);
  expect(b.sync.pendingPairing, isNull);
  a.sync.closePairing();
  b.sync.closePairing();
}

Future<void> _waitFor(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? '等待续读状态超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _savePosition(
  _Device device,
  Novel novel,
  int chapter,
  double offset,
) => device.state.savePosition(
  novel: novel,
  chapter: chapter,
  offset: offset,
  maximum: 1000,
  width: 390,
  paragraphIndex: 0,
  textOffset: offset.toInt(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpOverrides? previousOverrides;
  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previousOverrides);

  test('私网校验同时覆盖 IPv4、IPv6，拒绝公网地址', () {
    bool valid(String value) =>
        isPrivateLanAddress(InternetAddress.tryParse(value)!);
    expect(valid('192.168.1.2'), isTrue);
    expect(valid('169.254.2.3'), isTrue);
    expect(valid('8.8.8.8'), isFalse);
    expect(valid('fc00::1'), isTrue);
    expect(valid('fe80::1'), isTrue);
    expect(valid('2001:4860:4860::8888'), isFalse);
    expect(valid('::ffff:192.168.1.2'), isTrue);
  });

  test('双向确认后增量合并进度、书签与分类，冲突可解决并在换端口后恢复', () async {
    final root = await Directory.systemTemp.createTemp('wenku-lan-sync-');
    addTearDown(() => root.delete(recursive: true));
    final a = await _makeDevice(root, 'a', _aId, 1);
    final b = await _makeDevice(root, 'b', _bId, 2);

    await _savePosition(b, _novel, 0, 10);
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await _savePosition(a, _novel, 1, 120);
    final mark = await a.state.addBookmark(
      novel: _novel,
      position: a.state.positionFor(_novel.id)!,
      quote: '第二段正文',
    );
    final group = await a.state.organization.addGroup('跨设备分类');
    await a.state.organization.assign(_novel.id, group);
    await _pair(a, b);
    await _waitFor(
      () =>
          b.state.positionFor(_novel.id)?.chapter == 1 &&
          b.state.bookmarksFor(_novel.id).length == 1 &&
          b.state.organization.groupOf(_novel.id) == group,
      reason: '首次配对后的进度、书签和分类未合并',
    );
    expect(b.state.positionFor(_novel.id)!.offset, 120);
    expect(a.state.organization.groupOf(_novel.id), group);

    await Future<void>.delayed(const Duration(milliseconds: 3));
    await a.state.categorizeBookmark(_novel.id, mark!.id, '甲');
    await b.state.categorizeBookmark(_novel.id, mark.id, '乙');
    await a.sync.sync();
    await b.sync.sync();
    final record = 'b/${_novel.id}/${Uri.encodeComponent(mark.id)}';
    await _waitFor(
      () =>
          a.sync.librarySync!.alternatives(record).length >= 2 &&
          b.sync.librarySync!.alternatives(record).length >= 2,
      reason: '两端同时修改未保留冲突版本',
    );
    final selected = a.sync.librarySync!
        .alternatives(record)
        .firstWhere((variant) => variant.value?['mark']?['category'] == '甲');
    await a.sync.librarySync!.resolve(record, selected);
    await a.sync.sync();
    await b.sync.sync();
    await _waitFor(
      () => b.state.bookmarksFor(_novel.id).single.category == '甲',
      reason: '冲突解决结果未同步到另一端',
    );

    await Future<void>.delayed(const Duration(milliseconds: 3));
    await _savePosition(a, _novel, 1, 200);
    b.discovery.error = '未获得本地网络权限';
    b.discovery.available = false;
    b.discovery.emit(const []);
    await b.sync.sync();
    await _waitFor(() => b.state.positionFor(_novel.id)?.offset == 200);
    expect(b.sync.error, '未获得本地网络权限');
    b.discovery.error = null;
    b.discovery.available = true;
    await b.sync.sync();
    expect(b.sync.error, isNull);

    await b.sync.stop();
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await _savePosition(a, _novel, 0, 260);
    await a.state.addBookmark(
      novel: _novel,
      position: a.state.positionFor(_novel.id)!,
      quote: '离线新增',
    );
    await a.sync.sync();
    expect(a.sync.error, contains('暂未连接'));
    expect(b.state.positionFor(_novel.id)!.offset, 200);

    final oldPort = a.sync.peers.single.port;
    await b.sync.start();
    expect(b.port, isNot(oldPort));
    a.discovery.emit([b.nearby]);
    await _waitFor(() => a.sync.peers.single.port == b.port);
    await _waitFor(
      () =>
          b.state.positionFor(_novel.id)?.offset == 260 &&
          b.state.bookmarksFor(_novel.id).any((mark) => mark.quote == '离线新增'),
      reason: '重新发现新端口后未恢复断线期间的增量',
    );
    await a.sync.sync();
    expect(a.sync.error, isNull);
    expect(a.sync.lastSync, isNotNull);
  });

  test('缺书时加密传书，已有同一本书时仅传续读位置', () async {
    final root = await Directory.systemTemp.createTemp('wenku-lan-handoff-');
    addTearDown(() => root.delete(recursive: true));
    final a = await _makeDevice(root, 'a', _aId, 3);
    final b = await _makeDevice(root, 'b', _bId, 4);
    const text = '第一章\n甲方正文。\n第二章\n后续正文。';
    final input = LocalBookInput(
      '续读.txt',
      Uint8List.fromList(utf8.encode(text)),
      text: text,
    );
    final local = await a.books.import(input);
    await _savePosition(a, local, 0, 20);
    await _pair(a, b);

    final firstPhases = <String>[];
    void firstListener() {
      final phase = a.sync.handoff.transfer?.phase;
      if (phase != null) firstPhases.add(phase);
    }

    a.sync.handoff.addListener(firstListener);
    await a.sync.handoff.send(
      peer: a.sync.peers.single,
      bookId: local.id,
      position: a.state.positionFor(local.id)!,
    );
    a.sync.handoff.removeListener(firstListener);
    expect(firstPhases, contains('正在传送书籍'));
    expect(b.books.book(local.id), isNotNull);
    expect(b.sync.handoff.received?.position.chapter, 0);
    expect(
      await b.books.chapterContent(
        local.id,
        b.books.book(local.id)!.chapters[0],
      ),
      contains('甲方正文'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 3));
    await _savePosition(a, local, 1, 80);
    final secondPhases = <String>[];
    void secondListener() {
      final phase = a.sync.handoff.transfer?.phase;
      if (phase != null) secondPhases.add(phase);
    }

    a.sync.handoff.addListener(secondListener);
    await a.sync.handoff.send(
      peer: a.sync.peers.single,
      bookId: local.id,
      position: a.state.positionFor(local.id)!,
    );
    a.sync.handoff.removeListener(secondListener);
    expect(secondPhases, isNot(contains('正在传送书籍')));
    expect(b.sync.handoff.received?.position.chapter, 1);
    expect(b.state.positionFor(local.id)?.chapter, 1);
  });
}
