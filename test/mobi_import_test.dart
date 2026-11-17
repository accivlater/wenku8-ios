import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/local_document_converter.dart';
import 'package:wenku8_flutter/local_epub_builder.dart';
import 'package:wenku8_flutter/local_mobi_converter.dart';
import 'package:wenku8_flutter/reader_content.dart';

const _mobiMarkup =
    '<html><body><h1>第一章</h1><p>图前中文。</p><img recindex="00000"/>'
    '<p>图后中文。</p><h1>第二章</h1><p>第二章正文。</p></body></html>';
final _mobiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6i0AAAAASUVORK5CYII=',
);

void _set16(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint16(offset, value, Endian.big);
void _set32(Uint8List bytes, int offset, int value) =>
    ByteData.sublistView(bytes).setUint32(offset, value, Endian.big);
void _writeAscii(Uint8List bytes, int offset, String value) {
  final encoded = ascii.encode(value);
  bytes.setRange(offset, offset + encoded.length, encoded);
}

Uint8List _huffRecord() {
  final record = Uint8List(24 + 256 * 4 + 64 * 4);
  _writeAscii(record, 0, 'HUFF');
  _set32(record, 4, 24);
  _set32(record, 8, 24);
  _set32(record, 12, 24 + 256 * 4);
  for (var i = 0; i < 256; i++) {
    _set32(record, 24 + i * 4, 0x181);
  }
  return record;
}

Uint8List _cdicRecord(Uint8List markup) {
  final record = Uint8List(24 + markup.length);
  _writeAscii(record, 0, 'CDIC');
  _set32(record, 4, 16);
  _set32(record, 8, 2);
  _set32(record, 12, 16);
  _set16(record, 16, 4);
  _set16(record, 18, 6);
  _set16(record, 20, 0x8000);
  _set16(record, 22, 0x8000 | markup.length);
  record.setRange(24, record.length, markup);
  return record;
}

Uint8List _mobiFixture({
  int compression = 2,
  int version = 6,
  bool trailing = false,
  Uint8List? rawMarkup,
  List<Uint8List> extraRecords = const [],
  int fragmentIndex = 0xffffffff,
  int skeletonIndex = 0xffffffff,
  int fdstRecord = 0xffffffff,
  int fdstFlowCount = 0,
}) {
  final huff = compression == 17480;
  final markup = rawMarkup ?? Uint8List.fromList(utf8.encode(_mobiMarkup));
  final textRecords = <Uint8List>[];
  if (huff) {
    textRecords.add(Uint8List.fromList(const [0x7f]));
  } else {
    for (var start = 0; start < markup.length; start += 113) {
      final end = start + 113 < markup.length ? start + 113 : markup.length;
      final plain = Uint8List.sublistView(markup, start, end);
      if (compression == 1) {
        textRecords.add(plain);
      } else {
        final compressed = BytesBuilder(copy: false);
        for (var at = 0; at < plain.length;) {
          final count = plain.length - at < 8 ? plain.length - at : 8;
          compressed.addByte(count);
          compressed.add(Uint8List.sublistView(plain, at, at + count));
          at += count;
        }
        textRecords.add(compressed.toBytes());
      }
    }
  }
  if (trailing) {
    for (var i = 0; i < textRecords.length; i++) {
      textRecords[i] = Uint8List.fromList([...textRecords[i], 0]);
    }
  }
  final firstImage =
      1 + textRecords.length + (huff ? 2 : 0) + extraRecords.length;
  final exthRecords = <(int, List<int>)>[
    (100, utf8.encode('测试作者')),
    (503, utf8.encode('MOBI 中文书名')),
    (201, Uint8List(4)),
    (125, Uint8List(4)..[3] = 1),
  ];
  final exthLength =
      12 +
      exthRecords.fold<int>(0, (sum, record) => sum + 8 + record.$2.length);
  final exth = Uint8List(exthLength);
  _writeAscii(exth, 0, 'EXTH');
  _set32(exth, 4, exthLength);
  _set32(exth, 8, exthRecords.length);
  var exthAt = 12;
  for (final record in exthRecords) {
    _set32(exth, exthAt, record.$1);
    _set32(exth, exthAt + 4, 8 + record.$2.length);
    exth.setRange(exthAt + 8, exthAt + 8 + record.$2.length, record.$2);
    exthAt += 8 + record.$2.length;
  }
  const mobiLength = 264;
  final exthOffset = 16 + mobiLength;
  final nameOffset = exthOffset + exthLength + (4 - exthLength % 4) % 4;
  final fullName = utf8.encode('MOBI 中文书名');
  final record0 = Uint8List(nameOffset + fullName.length + 2);
  _set16(record0, 0, compression);
  _set32(record0, 4, markup.length);
  _set16(record0, 8, textRecords.length);
  _set16(record0, 10, 4096);
  _writeAscii(record0, 16, 'MOBI');
  _set32(record0, 20, mobiLength);
  _set32(record0, 24, version >= 8 ? 248 : 2);
  _set32(record0, 28, 65001);
  _set32(record0, 36, version);
  _set32(record0, 84, nameOffset);
  _set32(record0, 88, fullName.length);
  _set32(record0, 108, firstImage);
  if (huff) {
    _set32(record0, 112, 2);
    _set32(record0, 116, 2);
  }
  _set32(record0, 128, 0x40);
  _set32(record0, 192, fdstRecord);
  _set32(record0, 196, fdstFlowCount);
  _set32(record0, 248, fragmentIndex);
  _set32(record0, 252, skeletonIndex);
  if (trailing) _set16(record0, 242, 1);
  record0.setRange(exthOffset, exthOffset + exth.length, exth);
  record0.setRange(nameOffset, nameOffset + fullName.length, fullName);
  final records = <Uint8List>[
    record0,
    ...textRecords,
    if (huff) ...[_huffRecord(), _cdicRecord(markup)],
    ...extraRecords,
    _mobiPng,
  ];
  final tableEnd = 78 + records.length * 8;
  final header = Uint8List(tableEnd);
  _writeAscii(header, 0, 'MOBI fixture');
  _writeAscii(header, 60, 'BOOK');
  _writeAscii(header, 64, 'MOBI');
  _set16(header, 76, records.length);
  var offset = tableEnd;
  for (var i = 0; i < records.length; i++) {
    _set32(header, 78 + i * 8, offset);
    offset += records[i].length;
  }
  final output = BytesBuilder(copy: false)..add(header);
  for (final record in records) {
    output.add(record);
  }
  return output.toBytes();
}

List<int> _vwiBytes(int value) {
  if (value == 0) return const [0x80];
  final groups = <int>[];
  while (value > 0) {
    groups.add(value & 0x7f);
    value >>= 7;
  }
  return [
    for (var i = groups.length - 1; i >= 0; i--)
      groups[i] | (i == 0 ? 0x80 : 0),
  ];
}

Uint8List _indxMeta(List<(int, int, int, int)> fields, int totalEntries) {
  final result = Uint8List(64 + 12 + fields.length * 4);
  _writeAscii(result, 0, 'INDX');
  _set32(result, 4, 64);
  _set32(result, 24, 1);
  _set32(result, 28, 65001);
  _set32(result, 36, totalEntries);
  _writeAscii(result, 64, 'TAGX');
  _set32(result, 68, result.length - 64);
  _set32(result, 72, 1);
  for (var i = 0; i < fields.length; i++) {
    final field = fields[i];
    result[76 + i * 4] = field.$1;
    result[76 + i * 4 + 1] = field.$2;
    result[76 + i * 4 + 2] = field.$3;
    result[76 + i * 4 + 3] = field.$4;
  }
  return result;
}

Uint8List _indxData(List<(String, List<int>, List<int>)> entries) {
  final encoded = <Uint8List>[];
  final offsets = <int>[];
  var offset = 28;
  for (final entry in entries) {
    offsets.add(offset);
    final label = ascii.encode(entry.$1);
    final body = BytesBuilder(copy: false)
      ..addByte(label.length)
      ..add(label)
      ..add(entry.$2);
    for (final value in entry.$3) {
      body.add(_vwiBytes(value));
    }
    final bytes = body.toBytes();
    encoded.add(bytes);
    offset += bytes.length;
  }
  final idxt = offset;
  final result = Uint8List(idxt + 4 + offsets.length * 2 + 2);
  _writeAscii(result, 0, 'INDX');
  _set32(result, 4, 28);
  _set32(result, 20, idxt);
  _set32(result, 24, entries.length);
  for (var i = 0; i < encoded.length; i++) {
    result.setRange(offsets[i], offsets[i] + encoded[i].length, encoded[i]);
    _set16(result, idxt + 4 + i * 2, offsets[i]);
  }
  _writeAscii(result, idxt, 'IDXT');
  return result;
}

Uint8List _fdst(List<(int, int)> flows) {
  final result = Uint8List(12 + flows.length * 8);
  _writeAscii(result, 0, 'FDST');
  _set32(result, 4, 12);
  _set32(result, 8, flows.length);
  for (var i = 0; i < flows.length; i++) {
    _set32(result, 12 + i * 8, flows[i].$1);
    _set32(result, 12 + i * 8 + 4, flows[i].$2);
  }
  return result;
}

Uint8List _kf8MultiFixture() {
  final skeleton0 = utf8.encode('<html><body><h1>');
  final fragment0 = utf8.encode('第一章</h1><p>图前中文。</p><img recindex="00000"/>');
  final fragment1 = utf8.encode('<p>图后中文。</p>');
  final skeleton1 = utf8.encode('<h1>');
  final fragment2 = utf8.encode('第二章</h1><p>第二章正文。</p></body></html>');
  final html = <int>[
    ...skeleton0,
    ...fragment0,
    ...fragment1,
    ...skeleton1,
    ...fragment2,
  ];
  final css = utf8.encode('/* CSS must not become prose */');
  final raw = Uint8List.fromList([...html, ...css]);
  final textRecords = (raw.length + 112) ~/ 113;
  final fragmentIndex = 1 + textRecords;
  final skeletonIndex = fragmentIndex + 2;
  final fdstIndex = skeletonIndex + 2;
  final fragmentMeta = _indxMeta(const [
    (3, 1, 1, 0),
    (4, 1, 2, 0),
    (6, 2, 4, 0),
    (0, 0, 0, 1),
  ], 3);
  final fragmentData = _indxData([
    ('${skeleton0.length}', const [7], [0, 0, 0, fragment0.length]),
    (
      '${skeleton0.length + fragment0.length}',
      const [7],
      [0, 1, fragment0.length, fragment1.length],
    ),
    (
      '${skeleton0.length + fragment0.length + fragment1.length + skeleton1.length}',
      const [7],
      [1, 2, fragment0.length + fragment1.length, fragment2.length],
    ),
  ]);
  final skeletonMeta = _indxMeta(const [
    (1, 1, 1, 0),
    (6, 2, 2, 0),
    (0, 0, 0, 1),
  ], 2);
  final skeletonData = _indxData([
    ('0', const [3], [2, 0, skeleton0.length]),
    (
      '${skeleton0.length + fragment0.length + fragment1.length}',
      const [3],
      [
        1,
        skeleton0.length + fragment0.length + fragment1.length,
        skeleton1.length,
      ],
    ),
  ]);
  return _mobiFixture(
    version: 8,
    rawMarkup: raw,
    fragmentIndex: fragmentIndex,
    skeletonIndex: skeletonIndex,
    fdstRecord: fdstIndex,
    fdstFlowCount: 2,
    extraRecords: [
      fragmentMeta,
      fragmentData,
      skeletonMeta,
      skeletonData,
      _fdst([(0, html.length), (html.length, raw.length)]),
    ],
  );
}

Future<void> _checkMobiBook(
  Directory root,
  String name,
  Uint8List source,
) async {
  final parsed = parseLocalMobi(source);
  expect(parsed.title, 'MOBI 中文书名');
  expect(parsed.author, '测试作者');
  expect(parsed.resources.keys, [0]);
  final converted = LocalDocumentConverter(
    Directory('${root.path}/converted'),
  ).convert(name, source).single;
  expect(converted.error, isNull);
  expect(converted.name, '中文样本.epub');
  final archive = ZipDecoder().decodeBytes(
    File(converted.path!).readAsBytesSync(),
  );
  expect(archive.findFile('${preservedSourcePrefix}part-00000'), isNotNull);
  final books = LocalBookStore(Directory('${root.path}/books'));
  await books.load();
  final book = await books.importFile(converted.name, converted.path!);
  expect(book.title, 'MOBI 中文书名');
  expect(book.author, '测试作者');
  expect(book.chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
  final bodies = <String>[];
  for (final chapter in book.chapters) {
    bodies.add(await books.chapterContent(book.id, chapter));
  }
  expect(
    bodies.join(),
    allOf(contains('图前中文。'), contains('图后中文。'), contains('第二章正文。')),
  );
  expect(
    ReaderContent(bodies.join('\n\n').split('\n\n')).illustrations,
    hasLength(1),
  );
  books.dispose();
  final reopened = LocalBookStore(Directory('${root.path}/books'));
  await reopened.load();
  addTearDown(reopened.dispose);
  expect(reopened.book(book.id)!.chapters.map((c) => c.title), ['第一章', '第二章']);
  for (final chapter in reopened.book(book.id)!.chapters) {
    expect(
      await reopened.chapterContent(book.id, chapter),
      bodies[chapter.id - 1],
    );
  }
}

/// Fixtures are generated by BookArchiveImportTest with the real libmobi host
/// exporter, then read by exactly the EPUB importer used by the Android app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final configuration in [
    ('mobi', 1, 6, false),
    ('azw', 2, 6, true),
    ('azw3', 2, 8, false),
    ('prc', 1, 6, false),
  ]) {
    test(
      '${configuration.$1} parses real Palm records and reopens with images',
      () async {
        final root = await Directory.systemTemp.createTemp('mobi-dart-');
        addTearDown(() => root.delete(recursive: true));
        await _checkMobiBook(
          root,
          '中文样本.${configuration.$1}',
          _mobiFixture(
            compression: configuration.$2,
            version: configuration.$3,
            trailing: configuration.$4,
          ),
        );
      },
    );
  }

  test('HUFF/CDIC decompresses the shared dictionary exactly once', () async {
    final root = await Directory.systemTemp.createTemp('mobi-huff-');
    addTearDown(() => root.delete(recursive: true));
    final source = _mobiFixture(compression: 17480, version: 8);
    final parsed = parseLocalMobi(source);
    expect(parsed.markup, _mobiMarkup);
    expect('第一章'.allMatches(parsed.markup), hasLength(1));
    await _checkMobiBook(root, '中文样本.azw3', source);
  });

  test(
    'multiple KF8 skeletons and fragments reconstruct exact readable HTML',
    () async {
      final source = _kf8MultiFixture();
      final parsed = parseLocalMobi(source);
      expect(
        parsed.markup,
        '<html><body><h1>第一章</h1><p>图前中文。</p><img recindex="00000"/>'
        '<p>图后中文。</p><h1>第二章</h1><p>第二章正文。</p></body></html>',
      );
      expect(parsed.markup, isNot(contains('CSS must not')));
      final root = await Directory.systemTemp.createTemp('mobi-multi-kf8-');
      addTearDown(() => root.delete(recursive: true));
      await _checkMobiBook(root, '中文样本.azw3', source);
      final damaged = Uint8List.fromList(source);
      for (var i = 0; i + 8 < damaged.length; i++) {
        if (damaged[i] == 0x49 &&
            damaged[i + 1] == 0x44 &&
            damaged[i + 2] == 0x58 &&
            damaged[i + 3] == 0x54) {
          _set16(damaged, i + 4, 0xffff);
          break;
        }
      }
      expect(() => parseLocalMobi(damaged), throwsFormatException);
    },
  );

  test(
    'real KF8 INDX sample reconstructs readable HTML from multiple flows',
    () async {
      final source = await File(
        'third_party/libmobi/tests/samples/sample-obfuscated-fonts.mobi',
      ).readAsBytes();
      final parsed = parseLocalMobi(source);
      expect(parsed.markup, startsWith('<?xml version="1.0"'));
      expect(
        parsed.markup,
        contains('<html xmlns="http://www.w3.org/1999/xhtml">'),
      );
      expect(parsed.markup, contains('Libmobi'));
      expect(parsed.markup, contains('Font obfuscation test'));
      expect(
        parsed.markup,
        contains('Kurier is a two-element sans-serif typeface'),
      );
      expect(parsed.markup, contains('In the current version 0.995b'));
      final root = await Directory.systemTemp.createTemp('mobi-real-kf8-');
      addTearDown(() => root.delete(recursive: true));
      final converted = LocalDocumentConverter(
        Directory('${root.path}/converted'),
      ).convert('font.azw3', source).single;
      expect(converted.error, isNull);
      final books = LocalBookStore(Directory('${root.path}/books'));
      await books.load();
      final book = await books.importFile(converted.name, converted.path!);
      expect(book.title, 'font');
      expect(book.chapters, isNotEmpty);
      final bodies = [
        for (final chapter in book.chapters)
          await books.chapterContent(book.id, chapter),
      ];
      expect(bodies.join(), contains('Font obfuscation test'));
      expect(
        bodies.join(),
        contains('Kurier is a two-element sans-serif typeface'),
      );
      books.dispose();
      final reopened = LocalBookStore(Directory('${root.path}/books'));
      await reopened.load();
      addTearDown(reopened.dispose);
      for (final chapter in reopened.book(book.id)!.chapters) {
        expect(
          await reopened.chapterContent(book.id, chapter),
          bodies[chapter.id - 1],
        );
      }
    },
  );

  test(
    'conversion is deterministic across independent staging directories',
    () {
      final source = _mobiFixture(compression: 2, trailing: true);
      final first = LocalDocumentConverter(
        Directory('${Directory.systemTemp.path}/mobi-deterministic-a'),
      );
      final second = LocalDocumentConverter(
        Directory('${Directory.systemTemp.path}/mobi-deterministic-b'),
      );
      addTearDown(() {
        for (final directory in [first.root, second.root]) {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        }
      });
      final a = first.convert('中文样本.mobi', source).single;
      final b = second.convert('中文样本.mobi', source).single;
      expect(File(a.path!).readAsBytesSync(), File(b.path!).readAsBytesSync());
    },
  );

  test(
    'invalid Palm boundaries, DRM and extension-only fakes are rejected',
    () {
      final boundary = _mobiFixture();
      _set32(boundary, 78, boundary.length + 1);
      expect(() => parseLocalMobi(boundary), throwsFormatException);
      final drm = _mobiFixture();
      final record0 = ByteData.sublistView(drm).getUint32(78, Endian.big);
      _set16(drm, record0 + 12, 1);
      expect(
        () => parseLocalMobi(drm),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('DRM'),
          ),
        ),
      );
      expect(
        () => parseLocalMobi(Uint8List.fromList(utf8.encode(_mobiMarkup))),
        throwsFormatException,
      );
    },
  );

  for (final name in [
    'sample-cp1252',
    'sample-unicode-uncompressed',
    'sample-unicode-huffdic',
    'sample-ncx',
    'sample-textread',
    'sample-multimedia',
  ]) {
    test(
      'direct libmobi corpus $name converts and reopens readable prose',
      () async {
        final source = await File(
          'third_party/libmobi/tests/samples/$name.mobi',
        ).readAsBytes();
        final parsed = parseLocalMobi(source);
        expect(parsed.title, isNotEmpty);
        expect(parsed.markup.trim(), isNotEmpty);
        if (name == 'sample-unicode-huffdic') {
          expect(parsed.markup, contains('Libmobi'));
        }
        final root = await Directory.systemTemp.createTemp('mobi-corpus-');
        addTearDown(() => root.delete(recursive: true));
        final converted = LocalDocumentConverter(
          Directory('${root.path}/converted'),
        ).convert('$name.mobi', source).single;
        expect(converted.error, isNull);
        final books = LocalBookStore(Directory('${root.path}/books'));
        await books.load();
        final book = await books.importFile(converted.name, converted.path!);
        expect(book.chapters, isNotEmpty);
        final bodies = [
          for (final chapter in book.chapters)
            await books.chapterContent(book.id, chapter),
        ];
        expect(bodies.join().trim(), isNotEmpty);
        books.dispose();
        final reopened = LocalBookStore(Directory('${root.path}/books'));
        await reopened.load();
        addTearDown(reopened.dispose);
        for (final chapter in reopened.book(book.id)!.chapters) {
          expect(
            await reopened.chapterContent(book.id, chapter),
            bodies[chapter.id - 1],
          );
        }
      },
    );
  }

  const fixtures = String.fromEnvironment('MOBI_EPUB_FIXTURES');
  for (final name in [
    'sample-cp1252',
    'sample-unicode-uncompressed',
    'sample-unicode-huffdic',
    'sample-ncx',
    'sample-textread',
    'sample-multimedia',
    'sample-obfuscated-fonts',
  ]) {
    test(
      'reconstructed $name keeps metadata, chapters and readable content',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'wenku-mobi-import-',
        );
        final store = LocalBookStore(root);
        addTearDown(() async {
          store.dispose();
          await root.delete(recursive: true);
        });
        await store.load();
        final book = await store.importFile(
          '$name.epub',
          '$fixtures/$name.epub',
        );
        expect(book.title, isNotEmpty);
        expect(book.chapters, isNotEmpty);
        final bodies = [
          for (final chapter in book.chapters)
            await store.chapterContent(book.id, chapter),
        ];
        expect(bodies.any((body) => body.trim().isNotEmpty), isTrue);
        expect(
          bodies.join().contains('<!--image-->'),
          {
            'sample-cp1252',
            'sample-unicode-uncompressed',
            'sample-unicode-huffdic',
            'sample-multimedia',
          }.contains(name),
        );
      },
      skip: fixtures.isEmpty
          ? 'Requires real libmobi corpus generated by native BookArchiveImportTest'
          : false,
    );
  }
}
