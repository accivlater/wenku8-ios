import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

const maxConvertedEpubBytes = 512 * 1024 * 1024;
const maxConvertedDocumentExpansion = 1024 * 1024 * 1024;
const maxConvertedImageBytes = 8 * 1024 * 1024;
const preservedSourcePrefix = 'META-INF/wenku8-original/';

String escapeLocalEpub(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String boundedLocalMetadata(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 2048) return trimmed;
  var end = 2048;
  final last = trimmed.codeUnitAt(end - 1);
  if (last >= 0xd800 && last <= 0xdbff) end--;
  return trimmed.substring(0, end);
}

String? localRasterImageExtension(String type, List<int> bytes) {
  bool starts(List<int> signature) =>
      bytes.length >= signature.length &&
      List.generate(
        signature.length,
        (i) => bytes[i] == signature[i],
      ).every((value) => value);
  String? magic;
  if (starts(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    magic = 'png';
  } else if (starts(const [0xff, 0xd8, 0xff])) {
    magic = 'jpg';
  } else if (starts(const [0x47, 0x49, 0x46, 0x38])) {
    magic = 'gif';
  } else if (bytes.length >= 12 &&
      starts(const [0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    magic = 'webp';
  }
  final normalized = type.toLowerCase().split(';').first.trim();
  final declared = switch (normalized) {
    'image/jpeg' || 'jpg' || 'jpeg' => 'jpg',
    'image/png' || 'png' => 'png',
    'image/gif' || 'gif' => 'gif',
    'image/webp' || 'webp' => 'webp',
    _ => null,
  };
  if (magic == null || declared != null && declared != magic) return null;
  return magic;
}

class _LocalEpubChapter {
  const _LocalEpubChapter(this.title, this.file);
  final String title;
  final File file;
}

class _LocalEpubResource {
  const _LocalEpubResource(this.extension, this.file);
  final String extension;
  final File file;
}

const maxPdfPageImageBytes = 24 * 1024 * 1024;

class _PngChunk {
  const _PngChunk(this.type, this.data);
  final String type;
  final Uint8List data;
}

class _PngImage {
  const _PngImage(
    this.width,
    this.height,
    this.rowBytes,
    this.bytesPerPixel,
    this.ihdr,
    this.ancillary,
    this.pixels,
  );
  final int width, height, rowBytes, bytesPerPixel;
  final Uint8List ihdr, pixels;
  final List<_PngChunk> ancillary;
}

int _pngU32(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const FormatException('PDF PNG 数据块不完整');
  }
  return bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}

void _pngSet32(Uint8List bytes, int offset, int value) {
  bytes[offset] = value >> 24 & 0xff;
  bytes[offset + 1] = value >> 16 & 0xff;
  bytes[offset + 2] = value >> 8 & 0xff;
  bytes[offset + 3] = value & 0xff;
}

void _pngCheckRange(Uint8List bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    throw const FormatException('PDF PNG 数据块越过文件边界');
  }
}

Uint8List _pngChunkBytes(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final result = Uint8List(data.length + 12);
  _pngSet32(result, 0, data.length);
  result.setRange(4, 8, typeBytes);
  result.setRange(8, 8 + data.length, data);
  final crc = getCrc32(data, getCrc32(typeBytes));
  _pngSet32(result, result.length - 4, crc);
  return result;
}

_PngImage _decodePdfPng(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 8 ||
      !signature.indexed.every((entry) => bytes[entry.$1] == entry.$2)) {
    throw const FormatException('PDF 大页面图必须是 PNG');
  }
  final idat = BytesBuilder(copy: false);
  final ancillary = <_PngChunk>[];
  Uint8List? ihdr;
  var at = 8, chunks = 0;
  var ended = false;
  while (at < bytes.length) {
    if (++chunks > 10000) throw const FormatException('PDF PNG 数据块过多');
    final length = _pngU32(bytes, at);
    at += 4;
    final type = ascii.decode(Uint8List.sublistView(bytes, at, at + 4));
    at += 4;
    _pngCheckRange(bytes, at, length + 4);
    final data = Uint8List.sublistView(bytes, at, at + length);
    at += length;
    final expectedCrc = _pngU32(bytes, at);
    at += 4;
    if (getCrc32(data, getCrc32(ascii.encode(type))) != expectedCrc) {
      throw const FormatException('PDF PNG CRC 校验失败');
    }
    if (type == 'IHDR') {
      if (ihdr != null || length != 13 || chunks != 1) {
        throw const FormatException('PDF PNG IHDR 无效');
      }
      ihdr = data;
    } else if (type == 'IDAT') {
      if (ihdr == null) throw const FormatException('PDF PNG 缺少 IHDR');
      idat.add(data);
    } else if (type == 'IEND') {
      if (length != 0 || at != bytes.length) {
        throw const FormatException('PDF PNG IEND 无效');
      }
      ended = true;
      break;
    } else if (type == 'PLTE' || type == 'tRNS') {
      ancillary.add(_PngChunk(type, data));
    }
  }
  if (ihdr == null || !ended || idat.length == 0) {
    throw const FormatException('PDF PNG 缺少必要的图像数据');
  }
  final header = ihdr;
  final width = _pngU32(header, 0), height = _pngU32(header, 4);
  final depth = header[8], color = header[9];
  if (width <= 0 ||
      height <= 0 ||
      width > 32768 ||
      height > 32768 ||
      header[10] != 0 ||
      header[11] != 0 ||
      header[12] != 0) {
    throw const FormatException('PDF PNG 尺寸过大或使用了隔行/压缩过滤扩展');
  }
  final channels = switch (color) {
    0 => 1,
    2 => 3,
    3 => 1,
    4 => 2,
    6 => 4,
    _ => 0,
  };
  final validDepth = switch (color) {
    0 => const {1, 2, 4, 8, 16}.contains(depth),
    2 => const {8, 16}.contains(depth),
    3 => const {1, 2, 4, 8}.contains(depth),
    4 => const {8, 16}.contains(depth),
    6 => const {8, 16}.contains(depth),
    _ => false,
  };
  if (channels == 0 || !validDepth) {
    throw const FormatException('PDF PNG 颜色类型或位深暂不支持');
  }
  final rowBytes = (width * channels * depth + 7) ~/ 8;
  final expected = (rowBytes + 1) * height;
  if (rowBytes <= 0 ||
      width * height > 100000000 ||
      expected > 512 * 1024 * 1024) {
    throw const FormatException('PDF PNG 展开后超过 512 MiB');
  }
  late final Uint8List filtered;
  try {
    filtered = ZLibDecoder().decodeBytes(
      idat.toBytes(),
      verify: true,
      maxOutputSize: expected,
    );
  } on ArchiveException {
    throw const FormatException('PDF PNG 压缩数据损坏或展开后超过限制');
  }
  if (filtered.length != expected) {
    throw const FormatException('PDF PNG 扫描线长度不完整');
  }
  final bytesPerPixel = math.max(1, channels * depth ~/ 8);
  final pixels = Uint8List(rowBytes * height);
  for (var row = 0; row < height; row++) {
    final input = row * (rowBytes + 1);
    final output = row * rowBytes;
    final filter = filtered[input];
    if (filter > 4) throw const FormatException('PDF PNG 行过滤器无效');
    for (var x = 0; x < rowBytes; x++) {
      final value = filtered[input + 1 + x];
      final left = x >= bytesPerPixel ? pixels[output + x - bytesPerPixel] : 0;
      final up = row > 0 ? pixels[output - rowBytes + x] : 0;
      final upperLeft = row > 0 && x >= bytesPerPixel
          ? pixels[output - rowBytes + x - bytesPerPixel]
          : 0;
      pixels[output + x] = switch (filter) {
        0 => value,
        1 => value + left,
        2 => value + up,
        3 => value + ((left + up) >> 1),
        _ => value + _paeth(left, up, upperLeft),
      };
    }
  }
  return _PngImage(
    width,
    height,
    rowBytes,
    bytesPerPixel,
    header,
    ancillary,
    pixels,
  );
}

int _paeth(int left, int up, int upperLeft) {
  final estimate = left + up - upperLeft;
  final leftDistance = (estimate - left).abs();
  final upDistance = (estimate - up).abs();
  final upperLeftDistance = (estimate - upperLeft).abs();
  return leftDistance <= upDistance && leftDistance <= upperLeftDistance
      ? left
      : upDistance <= upperLeftDistance
      ? up
      : upperLeft;
}

Uint8List _encodePdfPngTile(_PngImage image, int start, int end) {
  final rows = end - start;
  final filtered = Uint8List((image.rowBytes + 1) * rows);
  for (var row = 0; row < rows; row++) {
    final input = (start + row) * image.rowBytes;
    final output = row * (image.rowBytes + 1);
    filtered[output] = 0;
    filtered.setRange(
      output + 1,
      output + 1 + image.rowBytes,
      image.pixels,
      input,
    );
  }
  final header = Uint8List.fromList(image.ihdr);
  _pngSet32(header, 4, rows);
  final compressed = ZLibEncoder().encodeBytes(filtered, level: 6);
  final output = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add(_pngChunkBytes('IHDR', header));
  for (final chunk in image.ancillary) {
    output.add(_pngChunkBytes(chunk.type, chunk.data));
  }
  output
    ..add(_pngChunkBytes('IDAT', compressed))
    ..add(_pngChunkBytes('IEND', const []));
  return output.toBytes();
}

class LocalEpubBuilder {
  LocalEpubBuilder(this.work, String title)
    : title = boundedLocalMetadata(title) {
    if (this.title.isEmpty) this.title = '本地书籍';
    work.createSync(recursive: true);
  }

  final Directory work;
  String title;
  String author = '';
  String? cover;
  final _chapters = <_LocalEpubChapter>[];
  final _references = <String, int>{};
  final _resources = <int, _LocalEpubResource>{};
  final _body = StringBuffer();
  var _chapterTitle = '';
  var _expanded = 0;
  var _chapterSerial = 0;

  int _reference(String key) {
    if (key.length > 4096) throw const FormatException('文档图片引用无效');
    return _references.putIfAbsent(key, () => _references.length);
  }

  String inlineResourceKey() => 'inline-${_references.length}';

  void heading(String value) {
    _flush();
    final heading = boundedLocalMetadata(value);
    _chapterTitle = heading.isEmpty ? title : heading;
  }

  void text(String value) {
    if (value.trim().isEmpty) return;
    final normalized = value.replaceAll('\u0000', '').trim();
    for (var start = 0; start < normalized.length;) {
      var end = math.min(start + 4000, normalized.length);
      if (end < normalized.length) {
        final last = normalized.codeUnitAt(end - 1);
        if (last >= 0xd800 && last <= 0xdbff) end--;
      }
      _append('<p>${escapeLocalEpub(normalized.substring(start, end))}</p>');
      start = end;
    }
  }

  void image(String key, {String style = ''}) {
    final id = _reference(key);
    _append(
      '<img src="resource:$id"${style.isEmpty ? '' : ' style="${escapeLocalEpub(style)}"'}/>',
    );
  }

  bool resource(String key, String type, List<int> bytes) {
    if (bytes.length > maxConvertedImageBytes) {
      throw const FormatException('文档单张图片超过 8 MiB');
    }
    final extension = localRasterImageExtension(type, bytes);
    if (extension == null) return false;
    final id = _reference(key);
    if (_resources.containsKey(id)) return true;
    _expanded += bytes.length;
    if (_expanded > maxConvertedDocumentExpansion) {
      throw const FormatException('文档展开后超过 1 GiB');
    }
    final file = File('${work.path}/resource-$id.$extension')
      ..writeAsBytesSync(bytes, flush: true);
    _resources[id] = _LocalEpubResource(extension, file);
    return true;
  }

  void pdfImage(String key, Uint8List bytes) {
    if (bytes.length > maxPdfPageImageBytes) {
      throw const FormatException('PDF 单张页面图超过 24 MiB');
    }
    if (bytes.length <= maxConvertedImageBytes) {
      if (!resource(key, '', bytes)) {
        throw const FormatException('PDF 页面图不是支持的 PNG / JPEG / GIF / WebP');
      }
      image(key);
      return;
    }
    final decoded = _decodePdfPng(bytes);
    var emitted = 0;
    void emit(int start, int end) {
      if (++emitted > 10000) {
        throw const FormatException('PDF 页面图分片过多');
      }
      final tile = _encodePdfPngTile(decoded, start, end);
      if (tile.length > maxConvertedImageBytes) {
        if (end - start <= 1) {
          throw const FormatException('PDF PNG 单行像素超过 8 MiB，无法安全分片');
        }
        final middle = start + (end - start) ~/ 2;
        emit(start, middle);
        emit(middle, end);
        return;
      }
      final tileKey = '$key-$start-$end';
      if (!resource(tileKey, 'png', tile)) {
        throw const FormatException('PDF PNG 分片写入失败');
      }
      image(tileKey);
    }

    emit(0, decoded.height);
  }

  void _append(String value) {
    if (_body.isNotEmpty && _body.length + value.length > 200000) _flush();
    _body.write(value);
  }

  void _flush() {
    if (_body.isEmpty) return;
    if (_chapters.length >= 10000) {
      throw const FormatException('文档章节过多，请拆分后导入');
    }
    final content = _body.toString();
    final file = File('${work.path}/chapter-${_chapterSerial++}.xhtml')
      ..writeAsStringSync(content, flush: true);
    _expanded += file.lengthSync();
    if (_expanded > maxConvertedDocumentExpansion) {
      throw const FormatException('文档展开后超过 1 GiB');
    }
    _chapters.add(
      _LocalEpubChapter(
        boundedLocalMetadata(_chapterTitle.isEmpty ? title : _chapterTitle),
        file,
      ),
    );
    _body.clear();
  }

  void write(File output, {String? originalName, Uint8List? originalBytes}) {
    _flush();
    if (_chapters.isEmpty) {
      throw const FormatException('文档中没有可阅读的正文或页面图');
    }
    if ((originalBytes == null) != (originalName == null)) {
      throw ArgumentError('原书名和原文件内容必须同时提供');
    }
    if (originalBytes != null) {
      _expanded += originalBytes.length;
      if (_expanded > maxConvertedDocumentExpansion) {
        throw const FormatException('文档与原书展开后超过 1 GiB');
      }
    }
    final encoder = ZipFileEncoder();
    var opened = false, closed = false;
    try {
      work.createSync(recursive: true);
      encoder.create(output.path, level: 6, modified: DateTime.utc(1980, 1, 1));
      opened = true;
      void bytes(String name, List<int> value, {bool store = false}) {
        final entry = store
            ? ArchiveFile.noCompress(name, value.length, value)
            : ArchiveFile(name, value.length, value);
        entry.lastModTime = 0;
        encoder.addArchiveFile(entry);
      }

      void textEntry(String name, String value) =>
          bytes(name, utf8.encode(value));
      bytes('mimetype', ascii.encode('application/epub+zip'), store: true);
      textEntry(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles></container>',
      );
      final coverId = cover == null ? null : _references[cover!];
      final manifest = StringBuffer(
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      );
      for (var i = 0; i < _chapters.length; i++) {
        manifest.write(
          '<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>',
        );
      }
      final resourceIds = _resources.keys.toList()..sort();
      for (final id in resourceIds) {
        final resource = _resources[id]!;
        manifest.write(
          '<item id="i$id" href="image-$id.${resource.extension}" '
          'media-type="image/${resource.extension == 'jpg' ? 'jpeg' : resource.extension}"'
          '${id == coverId ? ' properties="cover-image"' : ''}/>',
        );
      }
      textEntry(
        'content.opf',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="book-id">local-document</dc:identifier>'
            '<dc:title>${escapeLocalEpub(title)}</dc:title>'
            '<dc:creator>${escapeLocalEpub(boundedLocalMetadata(author))}</dc:creator>'
            '<dc:language>zh-CN</dc:language>'
            '<meta property="dcterms:modified">1980-01-01T00:00:00Z</meta>'
            '</metadata><manifest>$manifest</manifest><spine>'
            '${List.generate(_chapters.length, (i) => '<itemref idref="c$i"/>').join()}'
            '</spine></package>',
      );
      textEntry(
        'nav.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>${escapeLocalEpub(title)}</title></head><body>'
            '<nav epub:type="toc"><ol>'
            '${_chapters.indexed.map((entry) {
              final (i, chapter) = entry;
              return '<li><a href="c$i.xhtml">${escapeLocalEpub(chapter.title)}</a></li>';
            }).join()}'
            '</ol></nav></body></html>',
      );
      for (var i = 0; i < _chapters.length; i++) {
        var body = _chapters[i].file.readAsStringSync();
        body = body.replaceAllMapped(RegExp(r'resource:(\d+)'), (match) {
          final id = int.parse(match.group(1)!);
          final resource = _resources[id];
          return resource == null ? '' : 'image-$id.${resource.extension}';
        });
        textEntry(
          'c$i.xhtml',
          '<?xml version="1.0" encoding="UTF-8"?>'
              '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>'
              '${escapeLocalEpub(_chapters[i].title)}</title></head><body>$body</body></html>',
        );
      }
      for (final id in resourceIds) {
        final resource = _resources[id]!;
        final entry = ArchiveFile.stream(
          'image-$id.${resource.extension}',
          InputFileStream(resource.file.path),
        )..lastModTime = 0;
        encoder.addArchiveFile(entry);
      }
      if (originalBytes != null) {
        const chunkSize = 16 * 1024 * 1024;
        final parts = (originalBytes.length / chunkSize).ceil();
        textEntry(
          '${preservedSourcePrefix}source.json',
          jsonEncode({
            'version': 1,
            'name': originalName,
            'size': originalBytes.length,
            'parts': parts,
          }),
        );
        for (var i = 0; i < parts; i++) {
          final end = math.min((i + 1) * chunkSize, originalBytes.length);
          bytes(
            '${preservedSourcePrefix}part-${i.toString().padLeft(5, '0')}',
            Uint8List.sublistView(originalBytes, i * chunkSize, end),
          );
        }
      }
      encoder.closeSync();
      closed = true;
      if (!output.existsSync() || output.lengthSync() == 0) {
        throw const FormatException('转换后的 EPUB 写入失败');
      }
      if (output.lengthSync() > maxConvertedEpubBytes) {
        throw const FormatException('转换后的 EPUB 与原书合计超过 512 MiB');
      }
    } catch (_) {
      if (opened && !closed) {
        try {
          encoder.closeSync();
        } catch (_) {}
      }
      if (output.existsSync()) output.deleteSync();
      rethrow;
    }
  }
}
