import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/book_documents.dart';
import 'package:wenku8_flutter/local_books.dart';
import 'package:wenku8_flutter/local_document_converter.dart';
import 'package:wenku8_flutter/local_epub_builder.dart';
import 'package:wenku8_flutter/local_import_batch.dart';
import 'package:wenku8_flutter/reader_content.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6i0AAAAASUVORK5CYII=',
);

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(entry.key, entry.value.length, entry.value)
        ..lastModTime = 1704067200,
    );
  }
  return Uint8List.fromList(
    ZipEncoder().encode(archive, modified: DateTime.utc(2024, 1, 1)),
  );
}

void _testPngSet32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value >> 24 & 0xff;
  bytes[offset + 1] = value >> 16 & 0xff;
  bytes[offset + 2] = value >> 8 & 0xff;
  bytes[offset + 3] = value & 0xff;
}

int _testPngU32(Uint8List bytes, int offset) =>
    bytes[offset] << 24 |
    bytes[offset + 1] << 16 |
    bytes[offset + 2] << 8 |
    bytes[offset + 3];

Uint8List _testPngChunk(String type, List<int> data) {
  final result = Uint8List(data.length + 12);
  _testPngSet32(result, 0, data.length);
  final name = ascii.encode(type);
  result.setRange(4, 8, name);
  result.setRange(8, 8 + data.length, data);
  _testPngSet32(result, result.length - 4, getCrc32(data, getCrc32(name)));
  return result;
}

({Uint8List bytes, Uint8List pixels, int width, int height}) _noisePng(
  int width,
  int height, {
  bool variedFilters = false,
}) {
  final pixels = Uint8List(width * height * 4);
  var state = 0x12345678;
  for (var i = 0; i < pixels.length; i++) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    pixels[i] = state & 0xff;
  }
  final filtered = Uint8List((width * 4 + 1) * height);
  int paeth(int left, int up, int upperLeft) {
    final estimate = left + up - upperLeft;
    final a = (estimate - left).abs(), b = (estimate - up).abs();
    final c = (estimate - upperLeft).abs();
    return a <= b && a <= c
        ? left
        : b <= c
        ? up
        : upperLeft;
  }

  for (var row = 0; row < height; row++) {
    final filter = variedFilters ? row % 5 : 0;
    final output = row * (width * 4 + 1);
    filtered[output] = filter;
    if (filter == 0) {
      filtered.setRange(
        output + 1,
        output + 1 + width * 4,
        pixels,
        row * width * 4,
      );
      continue;
    }
    for (var x = 0; x < width * 4; x++) {
      final at = row * width * 4 + x;
      final left = x >= 4 ? pixels[at - 4] : 0;
      final up = row > 0 ? pixels[at - width * 4] : 0;
      final upperLeft = row > 0 && x >= 4 ? pixels[at - width * 4 - 4] : 0;
      final predictor = switch (filter) {
        1 => left,
        2 => up,
        3 => (left + up) >> 1,
        _ => paeth(left, up, upperLeft),
      };
      filtered[output + 1 + x] = pixels[at] - predictor;
    }
  }
  final ihdr = Uint8List(13);
  _testPngSet32(ihdr, 0, width);
  _testPngSet32(ihdr, 4, height);
  ihdr[8] = 8;
  ihdr[9] = 6;
  final png = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_testPngChunk('IHDR', ihdr))
    ..add(_testPngChunk('IDAT', ZLibEncoder().encodeBytes(filtered, level: 6)))
    ..add(_testPngChunk('IEND', const []));
  return (bytes: png.toBytes(), pixels: pixels, width: width, height: height);
}

({Uint8List pixels, int width, int height}) _filter0PngPixels(Uint8List png) {
  final width = _testPngU32(png, 16), height = _testPngU32(png, 20);
  final idat = BytesBuilder(copy: false);
  var at = 8;
  while (at < png.length) {
    final length = _testPngU32(png, at);
    final type = ascii.decode(Uint8List.sublistView(png, at + 4, at + 8));
    if (type == 'IDAT') {
      idat.add(Uint8List.sublistView(png, at + 8, at + 8 + length));
    }
    at += length + 12;
  }
  final filtered = ZLibDecoder().decodeBytes(
    idat.toBytes(),
    maxOutputSize: (width * 4 + 1) * height,
  );
  final pixels = Uint8List(width * height * 4);
  for (var row = 0; row < height; row++) {
    final input = row * (width * 4 + 1);
    expect(filtered[input], 0);
    pixels.setRange(
      row * width * 4,
      (row + 1) * width * 4,
      filtered,
      input + 1,
    );
  }
  return (pixels: pixels, width: width, height: height);
}

String _rtfText(String text) {
  final output = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit < 128) {
      final character = String.fromCharCode(unit);
      if (const {'\\', '{', '}'}.contains(character)) output.write('\\');
      output.write(character);
    } else {
      output.write('\\u${unit > 32767 ? unit - 65536 : unit}?');
    }
  }
  return output.toString();
}

Uint8List _rtfSample() {
  final image = _png
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return ascii.encode(
    '{\\rtf1\\ansi\\ansicpg1252{\\fonttbl{\\f0 ignored;}}\\uc1'
    '${_rtfText('第一章')}\\par '
    '${_rtfText('图前中文。')}\\par '
    '{\\pict\\pngblip $image}\\par '
    '${_rtfText('图后中文。')}\\par '
    '${_rtfText('第二章')}\\par '
    '${_rtfText('第二章正文。')}\\par '
    'caf\\\'e9}',
  );
}

Uint8List _docxSample({int imageSize = 0}) {
  final image = imageSize == 0
      ? _png
      : (Uint8List(imageSize)..setRange(0, 8, const [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]));
  return _zip({
    '[Content_Types].xml': utf8.encode(
      '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    ),
    'docProps/core.xml': utf8.encode(
      '<?xml version="1.0"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>中文 DOCX 小说</dc:title><dc:creator>文档作者</dc:creator></cp:coreProperties>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="image1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/pic.png"/>'
      '<Relationship Id="external" TargetMode="External" Target="https://invalid.example/secret.png"/>'
      '</Relationships>',
    ),
    'word/styles.xml': utf8.encode(
      '<?xml version="1.0"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style></w:styles>',
    ),
    'word/document.xml': utf8.encode(
      '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>'
      '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>图前中文。</w:t><w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
      '<wp:extent cx="9525" cy="9525"/><a:graphic><a:graphicData><a:blip r:embed="image1"/></a:graphicData></a:graphic></wp:inline></w:drawing>'
      '<w:t>图后中文。</w:t></w:r></w:p>'
      '<w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>第二章</w:t></w:r></w:p>'
      '<w:p><w:r><w:t>第二章正文。</w:t></w:r></w:p><w:sectPr/></w:body></w:document>',
    ),
    'word/media/pic.png': image,
  });
}

Uint8List _preservedSource(String epubPath) {
  final archive = ZipDecoder().decodeBytes(File(epubPath).readAsBytesSync());
  final manifest =
      jsonDecode(
            utf8.decode(
              archive
                  .findFile('${preservedSourcePrefix}source.json')!
                  .readBytes()!,
            ),
          )
          as Map<String, dynamic>;
  expect(manifest['size'], isPositive);
  final output = BytesBuilder(copy: false);
  for (var i = 0; i < (manifest['parts'] as int); i++) {
    output.add(
      archive
          .findFile(
            '${preservedSourcePrefix}part-${i.toString().padLeft(5, '0')}',
          )!
          .readBytes()!,
    );
  }
  final bytes = output.toBytes();
  expect(bytes.length, manifest['size']);
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  var serial = 0;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-documents-test-');
    serial = 0;
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> checkPrepared(
    LocalConvertedDocument prepared,
    List<int> original, {
    required String title,
    required List<String> chapters,
    required int images,
    List<String> text = const ['图前中文。', '图后中文。', '第二章正文。'],
  }) async {
    expect(prepared.error, isNull);
    expect(prepared.path, isNotNull);
    expect(_preservedSource(prepared.path!), orderedEquals(original));
    final library = Directory('${root.path}/library-${serial++}');
    final books = LocalBookStore(library);
    await books.load();
    final book = await books.importFile(prepared.name, prepared.path!);
    expect(book.title, title);
    final bodies = <String>[];
    for (final chapter in book.chapters) {
      bodies.add(await books.chapterContent(book.id, chapter));
    }
    expect(
      book.chapters.map((chapter) => chapter.title),
      chapters,
      reason: bodies.join('\n'),
    );
    for (final expected in text) {
      expect(bodies.join('\n'), contains(expected));
    }
    expect(
      ReaderContent(bodies.join('\n\n').split('\n\n')).illustrations,
      hasLength(images),
    );
    books.dispose();
    final reopened = LocalBookStore(library);
    await reopened.load();
    addTearDown(reopened.dispose);
    expect(reopened.book(book.id), isNotNull);
    expect(reopened.book(book.id)!.chapters.map((c) => c.title), chapters);
    final reread = <String>[];
    for (final chapter in reopened.book(book.id)!.chapters) {
      reread.add(await reopened.chapterContent(book.id, chapter));
    }
    expect(reread, bodies);
    expect(
      (await reopened.original(book.id)).bytes,
      File(prepared.path!).readAsBytesSync(),
    );
  }

  Future<void> checkDocument(
    String name,
    List<int> source, {
    required String title,
    List<String> chapters = const ['第一章', '第二章'],
    int images = 1,
    List<String> text = const ['图前中文。', '图后中文。', '第二章正文。'],
  }) async {
    final converter = LocalDocumentConverter(
      Directory('${root.path}/convert-${serial++}'),
    );
    final before = Uint8List.fromList(source);
    final converted = converter.convert(name, Uint8List.fromList(source));
    expect(source, before, reason: '转换不得改写输入缓冲区');
    expect(converted, hasLength(1));
    await checkPrepared(
      converted.single,
      source,
      title: title,
      chapters: chapters,
      images: images,
      text: text,
    );
  }

  test('FB2 retains Chinese metadata, sections, prose and embedded image', () async {
    final source = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">'
      '<description><title-info><book-title>中文 FB2 小说</book-title><author><first-name>某位</first-name><last-name>作者</last-name></author>'
      '<coverpage><image l:href="#picture"/></coverpage></title-info></description>'
      '<body><section><title><p>第一章</p></title><p>图前中文。</p><image l:href="#picture"/><p>图后中文。</p></section>'
      '<section><title><p>第二章</p></title><p>第二章正文。</p></section></body>'
      '<binary id="picture" content-type="image/png">${base64Encode(_png)}</binary></FictionBook>',
    );
    await checkDocument('中文.fb2', source, title: '中文 FB2 小说');
  });

  test('HTML and XHTML retain headings, Chinese prose and data image', () async {
    final source = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html><head><title>中文 HTML 小说</title><meta name="author" content="网页作者"/></head><body>'
      '<h1>第一章</h1><p>图前中文。</p><img width="1" src="data:image/png;base64,${base64Encode(_png)}"/><p>图后中文。</p>'
      '<h2>第二章</h2><p>第二章正文。</p><script>badScript()</script></body></html>',
    );
    for (final extension in ['html', 'xhtml']) {
      await checkDocument('中文.$extension', source, title: '中文 HTML 小说');
    }
  });

  test('Markdown keeps real headings and embedded illustration', () async {
    final source = utf8.encode(
      '# 第一章\n\n**图前中文。**\n\n![插图](data:image/png;base64,${base64Encode(_png)})\n\n'
      '图后中文。\n\n# 第二章\n\n第二章正文。',
    );
    await checkDocument('中文.markdown', source, title: '中文');
  });

  test('RTF and RTF-bearing DOC preserve Unicode chapters and PNG', () async {
    final source = _rtfSample();
    for (final extension in ['rtf', 'doc']) {
      await checkDocument('中文.$extension', source, title: '中文');
    }
  });

  test(
    'real CFBF DOC files retain piece-table text and chapters after reopen',
    () async {
      final cases = [
        (
          'word-mixed',
          ['第一章', '第二章'],
          ['图前中文。', 'café — naïve “smart quotes”.', '第二章正文。', 'After Unicode.'],
        ),
        (
          'word-cp1252',
          ['Chapter 1', 'Chapter 2'],
          ['café — naïve “smart quotes”.', 'Second paragraph.', 'Final text.'],
        ),
        (
          'word-cp1252-compressed',
          ['Chapter 1', 'Chapter 2'],
          ['café — naïve “smart quotes”.', 'Second paragraph.', 'Final text.'],
        ),
        (
          'word-0table',
          ['第一章', '第二章'],
          ['图前中文。', 'café — naïve “smart quotes”.', '第二章正文。', 'After Unicode.'],
        ),
      ];
      for (final fixture in cases) {
        final name = fixture.$1;
        await checkDocument(
          '$name.doc',
          await File('test/fixtures/$name.doc').readAsBytes(),
          title: name,
          chapters: fixture.$2,
          images: 0,
          text: fixture.$3,
        );
      }
    },
  );

  test(
    'DOCX keeps heading styles, metadata, image order and readable text',
    () async {
      await checkDocument('中文.docx', _docxSample(), title: '中文 DOCX 小说');
    },
  );

  test(
    'ZIP resolves relative images, imports multiple books and keeps partial failures',
    () async {
      final source = _zip({
        'folder/book.html': utf8.encode(
          '<html><head><title>压缩包 HTML</title></head><body><h1>第一章</h1><p>图前中文。</p>'
          '<img src="images/pic.png"/><p>图后中文。</p><h1>第二章</h1><p>第二章正文。</p></body></html>',
        ),
        'folder/images/pic.png': _png,
        'notes.md': utf8.encode('# 第一章\n\n图前中文。\n\n# 第二章\n\n第二章正文。'),
        'broken.doc': const [
          0xd0,
          0xcf,
          0x11,
          0xe0,
          0xa1,
          0xb1,
          0x1a,
          0xe1,
          0,
          0,
        ],
        '__MACOSX/ignored.txt': utf8.encode('忽略'),
        'nested.zip': _zip({'ignored.txt': utf8.encode('忽略')}),
      });
      final converted = LocalDocumentConverter(
        Directory('${root.path}/archive-convert'),
      ).convert('合集.zip', source);
      expect(converted, hasLength(3));
      expect(converted.map((item) => item.name), [
        'book.epub',
        'notes.epub',
        'broken.doc',
      ]);
      expect(converted.last.error, contains('CFBF'));
      await checkPrepared(
        converted[0],
        utf8.encode(
          '<html><head><title>压缩包 HTML</title></head><body><h1>第一章</h1><p>图前中文。</p>'
          '<img src="images/pic.png"/><p>图后中文。</p><h1>第二章</h1><p>第二章正文。</p></body></html>',
        ),
        title: '压缩包 HTML',
        chapters: ['第一章', '第二章'],
        images: 1,
      );
      await checkPrepared(
        converted[1],
        utf8.encode('# 第一章\n\n图前中文。\n\n# 第二章\n\n第二章正文。'),
        title: 'notes',
        chapters: ['第一章', '第二章'],
        images: 0,
        text: ['图前中文。', '第二章正文。'],
      );
    },
  );

  test(
    'iOS PDF bridge packages only manifest text and real page images',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <MethodCall>[];
      final source = File('${root.path}/original.pdf')
        ..writeAsBytesSync(ascii.encode('%PDF-1.4\n%% real source bytes\n'));
      final pageImage = File('${root.path}/page-2.png')..writeAsBytesSync(_png);
      final manifest = File('${root.path}/manifest.json');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BookDocuments.pdfChannel, (call) async {
            calls.add(call);
            manifest.writeAsStringSync(
              jsonEncode({
                'title': '中文 PDF 小说',
                'pages': [
                  {'title': '第一章', 'text': '图前中文。\n图后中文。', 'imagePath': ''},
                  {'title': '第二章', 'text': '', 'imagePath': pageImage.path},
                ],
              }),
            );
            return {'manifestPath': manifest.path};
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BookDocuments.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BookDocuments.pdfChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BookDocuments.channel, null);
      });
      final documents = BookDocuments();
      final selected = BookDocumentSelection(name: '中文.pdf', path: source.path);
      final prepared = (await documents.prepareBook(selected)).single;
      expect(prepared.error, isNull);
      expect(calls.first.method, 'convert');
      expect(calls.first.arguments, {'path': source.path, 'name': '中文.pdf'});
      await checkPrepared(
        LocalConvertedDocument(name: prepared.name, path: prepared.path),
        source.readAsBytesSync(),
        title: '中文 PDF 小说',
        chapters: ['第一章', '第二章'],
        images: 1,
        text: ['图前中文。', '图后中文。'],
      );
      final derived = prepared.path!;
      await documents.releaseBooks([selected, prepared]);
      expect(File(derived).existsSync(), isFalse);
      final release = calls.last;
      expect(release.method, 'releaseBooks');
      expect(release.arguments, {
        'paths': [source.path],
      });
      expect(source.existsSync(), isTrue, reason: '平台 mock 不应替原生删除输入');
    },
  );

  test(
    'large native PDF PNG is tiled under EPUB limits without pixel loss',
    () async {
      final noise = _noisePng(1024, 4096, variedFilters: true);
      expect(noise.bytes.length, greaterThan(maxConvertedImageBytes));
      expect(noise.bytes.length, lessThan(maxPdfPageImageBytes));
      final image = File('${root.path}/large-page.png')
        ..writeAsBytesSync(noise.bytes, flush: true);
      final manifest = File('${root.path}/large-manifest.json')
        ..writeAsStringSync(
          jsonEncode({
            'title': '大图 PDF',
            'pages': [
              {'title': '大图页', 'text': '大图页真实文本', 'imagePath': image.path},
            ],
          }),
        );
      final original = ascii.encode('%PDF-1.4\n%% large image source\n');
      final prepared = convertLocalPdfManifest(
        name: '大图.pdf',
        manifestPath: manifest.path,
        root: Directory('${root.path}/large-pdf'),
        originalBytes: original,
      );
      final archive = ZipDecoder().decodeBytes(
        File(prepared.path!).readAsBytesSync(),
      );
      final tiles =
          archive
              .where((file) => RegExp(r'^image-\d+\.png$').hasMatch(file.name))
              .toList()
            ..sort(
              (a, b) => int.parse(
                a.name.substring(6).split('.').first,
              ).compareTo(int.parse(b.name.substring(6).split('.').first)),
            );
      expect(tiles.length, greaterThan(1));
      for (final tile in tiles) {
        expect(tile.size, lessThanOrEqualTo(maxConvertedImageBytes));
      }
      await checkPrepared(
        prepared,
        original,
        title: '大图 PDF',
        chapters: ['大图页'],
        images: tiles.length,
        text: ['大图页真实文本'],
      );
      var height = 0;
      final pixels = BytesBuilder(copy: false);
      for (final tile in tiles) {
        final decoded = _filter0PngPixels(tile.readBytes()!);
        expect(decoded.width, noise.width);
        height += decoded.height;
        pixels.add(decoded.pixels);
      }
      expect(height, noise.height);
      expect(pixels.toBytes(), orderedEquals(noise.pixels));

      final oversized = File('${root.path}/oversized-page.png');
      final handle = oversized.openSync(mode: FileMode.write);
      handle.truncateSync(maxPdfPageImageBytes + 1);
      handle.closeSync();
      manifest.writeAsStringSync(
        jsonEncode({
          'title': '超限 PDF',
          'pages': [
            {'title': '第一页', 'text': '正文', 'imagePath': oversized.path},
          ],
        }),
      );
      expect(
        () => convertLocalPdfManifest(
          name: '超限.pdf',
          manifestPath: manifest.path,
          root: Directory('${root.path}/oversized-pdf'),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('24 MiB'),
          ),
        ),
      );
    },
  );

  test(
    'ZIP copy import expands progress and retains native source ownership',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BookDocuments.channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(BookDocuments.channel, null);
      });
      final source = File('${root.path}/合集.zip')
        ..writeAsBytesSync(
          _zip({
            '第一卷.md': utf8.encode('# 第一章\n\n第一卷正文。'),
            '第二卷.md': utf8.encode('# 第一章\n\n第二卷正文。'),
          }),
        );
      final books = LocalBookStore(Directory('${root.path}/progress-library'));
      await books.load();
      addTearDown(books.dispose);
      final documents = BookDocuments();
      final progress = <(int, int)>[];
      final report = await importLocalDocuments(
        selections: [BookDocumentSelection(name: '合集.zip', path: source.path)],
        documents: documents,
        books: books,
        importFile: books.importFile,
        releaseSources: true,
        onProgress: (done, total) => progress.add((done, total)),
      );
      expect(report.failures, isEmpty);
      expect(report.added, 2);
      expect(books.originals, hasLength(2));
      expect(progress.first, (0, 1));
      expect(progress.last, (2, 2));
      final nativePaths = calls
          .where((call) => call.method == 'releaseBooks')
          .expand((call) => (call.arguments['paths'] as List).cast<String>());
      expect(nativePaths, [source.path]);
    },
  );

  test(
    'unsafe entities, paths, bombs, large files and OLE DOC fail explicitly',
    () async {
      final converter = LocalDocumentConverter(
        Directory('${root.path}/unsafe'),
      );
      expect(
        () => converter.convert(
          'entity.fb2',
          utf8.encode(
            '<!DOCTYPE FictionBook [<!ENTITY content "bad">]><FictionBook><body><p>&content;</p></body></FictionBook>',
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('DTD'),
          ),
        ),
      );
      expect(
        () => converter.convert(
          'traverse.zip',
          _zip({'../outside.txt': utf8.encode('路径穿越')}),
        ),
        throwsFormatException,
      );
      final bomb = Uint8List.fromList(_zip({'small.txt': utf8.encode('正文')}));
      for (var i = 0; i + 28 < bomb.length; i++) {
        if (bomb[i] == 0x50 &&
            bomb[i + 1] == 0x4b &&
            bomb[i + 2] == 0x01 &&
            bomb[i + 3] == 0x02) {
          bomb.setRange(i + 24, i + 28, const [0xff, 0xff, 0xff, 0x7f]);
          break;
        }
      }
      expect(() => converter.convert('bomb.zip', bomb), throwsFormatException);
      expect(
        () => converter.convert('large.html', Uint8List(32 * 1024 * 1024 + 1)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('32 MiB'),
          ),
        ),
      );
      expect(
        () => converter.convert(
          'oversized-image.docx',
          _docxSample(imageSize: 8 * 1024 * 1024 + 1),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('8 MiB'),
          ),
        ),
      );
      expect(
        () => converter.convert(
          'legacy.doc',
          Uint8List.fromList(const [
            0xd0,
            0xcf,
            0x11,
            0xe0,
            0xa1,
            0xb1,
            0x1a,
            0xe1,
            1,
            2,
            3,
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('CFBF'),
          ),
        ),
      );
      expect(
        () => converter.convert(
          'encrypted.doc',
          File('test/fixtures/word-encrypted-flag.doc').readAsBytesSync(),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('加密'),
          ),
        ),
      );
      expect(
        () => converter.convert(
          'picture.doc',
          File('test/fixtures/word-picture-marker.doc').readAsBytesSync(),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('图片'),
          ),
        ),
      );
    },
  );
}
