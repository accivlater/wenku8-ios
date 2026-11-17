import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as markdown;
import 'package:xml/xml.dart';

import 'book_import_limits.dart';
import 'local_book_archive.dart';
import 'local_document_encoding.dart';
import 'local_epub_builder.dart';
import 'local_mobi_converter.dart';
import 'local_rtf_converter.dart';

class LocalConvertedDocument {
  const LocalConvertedDocument({required this.name, this.path, this.error})
    : assert(path == null || error == null),
      assert(path != null || error != null);
  final String name;
  final String? path, error;
}

class _ResolvedImage {
  const _ResolvedImage(this.key, this.type, this.bytes);
  final String key, type;
  final Uint8List bytes;
}

typedef _ImageResolver = _ResolvedImage? Function(html.Element image);

class LocalDocumentConverter {
  LocalDocumentConverter(this.root, {this.preserveOriginal = true}) {
    root.createSync(recursive: true);
  }
  final Directory root;
  final bool preserveOriginal;
  var _sequence = 0;

  List<LocalConvertedDocument> convert(String name, Uint8List bytes) {
    try {
      if (!supportsBookImport(name)) {
        throw const FormatException('请选择支持的电子书或文档格式');
      }
      if (bytes.isEmpty) throw const FormatException('文件为空，请重新下载原书');
      if (bytes.length > localBookByteLimit(name)) {
        throw FormatException(localBookSizeMessage(name));
      }
      final extension = name.split('.').last.toLowerCase();
      if (extension == 'zip') return _archive(bytes);
      return [_convertOne(_baseName(name), bytes)];
    } on ArchiveException {
      throw const FormatException('ZIP 已损坏、已加密或使用了不支持的压缩方式');
    }
  }

  String _outputPath() => '${root.path}/import-${_sequence++}.source';

  LocalConvertedDocument _stage(String name, Uint8List bytes) {
    final output = File(_outputPath());
    try {
      output.writeAsBytesSync(bytes, flush: true);
      return LocalConvertedDocument(name: name, path: output.path);
    } catch (_) {
      if (output.existsSync()) output.deleteSync();
      rethrow;
    }
  }

  LocalConvertedDocument _convertOne(
    String name,
    Uint8List bytes, {
    _ImageResolver? resolver,
  }) {
    final extension = name.split('.').last.toLowerCase();
    if (extension == 'txt' || extension == 'epub') return _stage(name, bytes);
    final output = File(_outputPath());
    final work = Directory('${output.path}.work');
    try {
      final builder = LocalEpubBuilder(work, _bookTitle(name));
      switch (extension) {
        case 'mobi' || 'azw' || 'azw3' || 'prc':
          _mobi(bytes, builder);
        case 'fb2':
          _fb2(bytes, builder);
        case 'html' || 'htm' || 'xhtml':
          _htmlBytes(bytes, builder, resolver);
        case 'md' || 'markdown':
          _markdown(bytes, builder, resolver);
        case 'rtf':
          convertLocalRtf(bytes, builder);
        case 'doc':
          if (bytes.length >= 5 &&
              ascii.decode(bytes.take(5).toList(), allowInvalid: true) ==
                  '{\\rtf') {
            convertLocalRtf(bytes, builder);
          } else if (bytes.length >= 8 &&
              const [
                0xd0,
                0xcf,
                0x11,
                0xe0,
                0xa1,
                0xb1,
                0x1a,
                0xe1,
              ].indexed.every((entry) => bytes[entry.$1] == entry.$2)) {
            _convertOleDoc(bytes, builder);
          } else {
            throw const FormatException(
              '此 DOC 既不是 RTF，也不是有效的 CFBF 二进制 Word 文档',
            );
          }
        case 'docx':
          _docx(bytes, builder);
        default:
          throw const FormatException('不支持的文档格式');
      }
      builder.write(
        output,
        originalName: preserveOriginal ? name : null,
        originalBytes: preserveOriginal ? bytes : null,
      );
      return LocalConvertedDocument(
        name: name.replaceFirst(RegExp(r'\.[^.]+$'), '.epub'),
        path: output.path,
      );
    } catch (_) {
      if (output.existsSync()) output.deleteSync();
      rethrow;
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  List<LocalConvertedDocument> _archive(Uint8List bytes) {
    final archive = readLocalBookArchive(
      InputMemoryStream(bytes),
      maxSize: maxConvertedDocumentExpansion,
    );
    final files = <String, ArchiveFile>{
      for (final file in archive)
        if (file.isFile) file.name: file,
    };
    bool hidden(String path) => path
        .split('/')
        .any((part) => part.startsWith('.') || part == '__MACOSX');
    final books = archive.where(
      (file) =>
          file.isFile &&
          !hidden(file.name) &&
          !file.name.toLowerCase().endsWith('.zip') &&
          supportsBookImport(file.name),
    );
    if (books.isEmpty) throw const FormatException('压缩包内没有支持的书籍或文档');
    if (books.length > 200) throw const FormatException('一个压缩包最多导入 200 本书');
    final prepared = <LocalConvertedDocument>[];
    try {
      for (final file in books) {
        final name = _baseName(file.name);
        try {
          if (file.size <= 0 || file.size > localBookByteLimit(name)) {
            throw FormatException('书籍为空或${localBookSizeMessage(name)}');
          }
          final content = _archiveBytes(file, localBookByteLimit(name));
          _ImageResolver? resolver;
          if (RegExp(
            r'\.(html?|xhtml|md|markdown)$',
            caseSensitive: false,
          ).hasMatch(name)) {
            resolver = (image) {
              final href = image.attributes['src']?.trim() ?? '';
              if (href.isEmpty || href.startsWith('#')) return null;
              final path = _resolveArchivePath(file.name, href);
              if (path == null) return null;
              final resource = files[path];
              if (resource == null || resource.isSymbolicLink) return null;
              if (resource.size > maxConvertedImageBytes) {
                throw const FormatException('压缩包中的图片超过 8 MiB');
              }
              return _ResolvedImage(
                path,
                path.split('.').last,
                _archiveBytes(resource, maxConvertedImageBytes),
              );
            };
          }
          prepared.add(_convertOne(name, content, resolver: resolver));
        } on FormatException catch (failure) {
          prepared.add(
            LocalConvertedDocument(
              name: name,
              error: failure is ArchiveException
                  ? '压缩包中的书籍损坏或使用了不支持的压缩方式'
                  : failure.message,
            ),
          );
        }
      }
      return prepared;
    } catch (_) {
      for (final item in prepared) {
        final path = item.path;
        if (path != null && File(path).existsSync()) File(path).deleteSync();
      }
      rethrow;
    }
  }

  Uint8List _archiveBytes(ArchiveFile file, int limit) {
    if (file.size < 0 || file.size > limit) {
      throw FormatException(
        limit == maxConvertedImageBytes ? '文档单张图片超过 8 MiB' : '压缩包条目超过大小限制',
      );
    }
    final output = OutputMemoryStream();
    file.writeContent(output);
    final bytes = output.getBytes();
    if (bytes.length != file.size || bytes.length > limit) {
      throw const FormatException('压缩包条目实际大小与目录不一致');
    }
    return bytes;
  }

  void _mobi(Uint8List bytes, LocalEpubBuilder builder) {
    final book = parseLocalMobi(bytes);
    if (book.title.isNotEmpty) builder.title = boundedLocalMetadata(book.title);
    builder.author = book.author;
    _ResolvedImage? resolve(html.Element image) {
      final candidates = <int>[];
      final recindex = int.tryParse(image.attributes['recindex'] ?? '');
      if (recindex != null) {
        candidates.add(recindex);
        if (recindex > 0) candidates.add(recindex - 1);
      }
      final src = image.attributes['src'] ?? '';
      if (src.startsWith('kindle:embed:')) {
        final value = src.substring('kindle:embed:'.length).split('?').first;
        final index = int.tryParse(value);
        if (index != null) candidates.add(index > 0 ? index - 1 : index);
      } else {
        final index = int.tryParse(src);
        if (index != null) candidates.add(index);
      }
      for (final index in candidates) {
        final resource = book.resources[index];
        if (resource != null) {
          return _ResolvedImage('mobi:$index', resource.type, resource.bytes);
        }
      }
      return null;
    }

    _htmlDocument(html.parse(book.markup), builder, resolve);
    final cover = book.cover == null ? null : book.resources[book.cover!];
    if (cover != null) {
      final key = 'mobi:${book.cover}';
      if (builder.resource(key, cover.type, cover.bytes)) builder.cover = key;
    }
  }

  void _htmlBytes(
    Uint8List bytes,
    LocalEpubBuilder builder,
    _ImageResolver? resolver,
  ) {
    var tags = 0;
    for (final byte in bytes) {
      if (byte == 0x3c && ++tags > 200000) {
        throw const FormatException('HTML 结构过于复杂，请转换为 EPUB 后导入');
      }
    }
    final text = decodeLocalDocumentText(bytes);
    _htmlDocument(html.parse(text), builder, resolver);
  }

  void _markdown(
    Uint8List bytes,
    LocalEpubBuilder builder,
    _ImageResolver? resolver,
  ) {
    final text = decodeLocalDocumentText(bytes);
    if (text.length > 32 * 1024 * 1024) {
      throw const FormatException('Markdown 解码后超过 32 MiB');
    }
    final rendered = markdown.markdownToHtml(
      text,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
      encodeHtml: true,
      enableTagfilter: true,
    );
    _htmlDocument(html.parse(rendered), builder, resolver);
  }

  void _htmlDocument(
    html.Document document,
    LocalEpubBuilder builder,
    _ImageResolver? resolver,
  ) {
    final title = document.querySelector('title')?.text.trim() ?? '';
    if (title.isNotEmpty) builder.title = boundedLocalMetadata(title);
    final author = document
        .querySelector('meta[name="author"]')
        ?.attributes['content']
        ?.trim();
    if (author != null) builder.author = author;
    for (final element in document.querySelectorAll(
      'script, style, nav, noscript, iframe, object, template',
    )) {
      element.remove();
    }
    final body = document.body;
    if (body == null) throw const FormatException('HTML 缺少正文');
    final paragraph = StringBuffer();
    var visited = 0;
    void flush() {
      builder.text(paragraph.toString());
      paragraph.clear();
    }

    void visit(html.Node node, int depth) {
      if (depth > 256 || ++visited > 500000) {
        throw const FormatException('HTML 嵌套过深或节点过多');
      }
      if (node is html.Text) {
        paragraph.write(node.text);
        if (paragraph.length >= 4000) flush();
        return;
      }
      if (node is! html.Element) return;
      final tag = node.localName ?? '';
      if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
        flush();
        builder.heading(node.text);
        return;
      }
      if (tag == 'img' || tag == 'image') {
        flush();
        final src = node.attributes['src'] ?? node.attributes['href'] ?? '';
        _ResolvedImage? resolved;
        if (src.startsWith('data:image/') && src.contains(';base64,')) {
          if (src.length > 12 * 1024 * 1024) {
            throw const FormatException('内嵌图片超过大小限制');
          }
          try {
            resolved = _ResolvedImage(
              builder.inlineResourceKey(),
              src.substring(5, src.indexOf(';')),
              Uint8List.fromList(
                base64Decode(src.substring(src.indexOf(',') + 1)),
              ),
            );
          } on FormatException {
            throw const FormatException('HTML 内嵌图片的 Base64 数据无效');
          }
        } else if (resolver != null) {
          resolved = resolver(node);
        }
        if (resolved != null &&
            builder.resource(resolved.key, resolved.type, resolved.bytes)) {
          builder.image(resolved.key, style: _imageStyle(node));
        }
        return;
      }
      const blocks = {
        'address',
        'article',
        'aside',
        'blockquote',
        'body',
        'br',
        'dd',
        'div',
        'dl',
        'dt',
        'figcaption',
        'figure',
        'footer',
        'header',
        'hr',
        'li',
        'main',
        'ol',
        'p',
        'pre',
        'section',
        'table',
        'tbody',
        'td',
        'tfoot',
        'th',
        'thead',
        'tr',
        'ul',
        'mbp:pagebreak',
      };
      final block = blocks.contains(tag);
      if (block) flush();
      for (final child in node.nodes) {
        visit(child, depth + 1);
      }
      if (block) flush();
    }

    visit(body, 0);
    flush();
  }

  void _fb2(Uint8List bytes, LocalEpubBuilder builder) {
    final document = _parseXml(bytes, 'FB2');
    final elements = document.descendants.whereType<XmlElement>().toList();
    XmlElement? first(Iterable<XmlElement> nodes, String name) =>
        nodes.where((element) => element.name.local == name).firstOrNull;
    final titleInfo = first(elements, 'title-info');
    final title = titleInfo == null
        ? ''
        : first(
                titleInfo.descendants.whereType<XmlElement>(),
                'book-title',
              )?.innerText ??
              '';
    if (title.trim().isNotEmpty) builder.title = boundedLocalMetadata(title);
    final author = titleInfo == null
        ? null
        : first(titleInfo.descendants.whereType<XmlElement>(), 'author');
    if (author != null) {
      builder.author = [
        for (final name in const [
          'first-name',
          'middle-name',
          'last-name',
          'nickname',
        ])
          ...author.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == name)
              .map((element) => element.innerText.trim()),
      ].where((part) => part.isNotEmpty).join(' ');
    }
    final binaries = <String, _ResolvedImage>{};
    for (final binary in elements.where(
      (element) => element.name.local == 'binary',
    )) {
      final id = binary.getAttribute('id') ?? '';
      if (id.isEmpty) continue;
      final encoded = binary.innerText;
      if (encoded.length > 12 * 1024 * 1024) {
        throw const FormatException('FB2 单张图片超过大小限制');
      }
      try {
        final content = Uint8List.fromList(
          base64Decode(base64.normalize(encoded)),
        );
        binaries[id] = _ResolvedImage(
          'fb2:$id',
          binary.getAttribute('content-type') ?? '',
          content,
        );
      } on FormatException {
        throw FormatException('FB2 图片 $id 的 Base64 数据无效');
      }
    }
    for (final image in elements.where(
      (element) =>
          element.name.local == 'image' &&
          element.ancestors.any(
            (ancestor) =>
                ancestor is XmlElement && ancestor.name.local == 'coverpage',
          ),
    )) {
      final id = _xmlImageId(image);
      if (binaries.containsKey(id)) builder.cover = 'fb2:$id';
    }
    final bodies = elements.where(
      (element) =>
          element.name.local == 'body' &&
          !element.ancestors.any(
            (ancestor) =>
                ancestor is XmlElement && ancestor.name.local == 'body',
          ),
    );
    final paragraph = StringBuffer();
    var visited = 0;
    void flush() {
      builder.text(paragraph.toString());
      paragraph.clear();
    }

    void visit(XmlNode node, int depth) {
      if (depth > 256 || ++visited > 500000) {
        throw const FormatException('FB2 嵌套过深或节点过多');
      }
      if (node is XmlText || node is XmlCDATA) {
        paragraph.write(node.value);
        if (paragraph.length >= 4000) flush();
        return;
      }
      if (node is! XmlElement) return;
      switch (node.name.local) {
        case 'title':
          flush();
          builder.heading(node.innerText);
          return;
        case 'image':
          flush();
          final id = _xmlImageId(node);
          final image = binaries[id];
          if (image != null &&
              builder.resource(image.key, image.type, image.bytes)) {
            builder.image(image.key);
          }
          return;
        case 'p' || 'v' || 'subtitle' || 'empty-line' || 'poem' || 'stanza':
          flush();
          for (final child in node.children) {
            visit(child, depth + 1);
          }
          flush();
          return;
        default:
          for (final child in node.children) {
            visit(child, depth + 1);
          }
      }
    }

    for (final body in bodies) {
      final name = body.getAttribute('name') ?? '';
      if (name.isNotEmpty) builder.heading(name);
      for (final child in body.children) {
        visit(child, 0);
      }
      flush();
    }
    final cover = builder.cover;
    if (cover != null) {
      final image = binaries[cover.substring(4)];
      if (image != null) builder.resource(image.key, image.type, image.bytes);
    }
  }

  void _docx(Uint8List bytes, LocalEpubBuilder builder) {
    final archive = readLocalBookArchive(
      InputMemoryStream(bytes),
      maxSize: maxConvertedDocumentExpansion,
    );
    final files = <String, ArchiveFile>{
      for (final file in archive)
        if (file.isFile) file.name: file,
    };
    XmlDocument xmlEntry(String name, {bool required = false}) {
      final file = files[name];
      if (file == null) {
        if (required) throw const FormatException('DOCX 缺少正文，或文件已加密');
        return XmlDocument();
      }
      if (file.size > 128 * 1024 * 1024) {
        throw const FormatException('DOCX XML 条目超过大小限制');
      }
      return _parseXml(_archiveBytes(file, 128 * 1024 * 1024), 'DOCX');
    }

    final core = xmlEntry('docProps/core.xml');
    for (final element in core.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'title' &&
          element.innerText.trim().isNotEmpty) {
        builder.title = boundedLocalMetadata(element.innerText);
      } else if (element.name.local == 'creator') {
        builder.author = boundedLocalMetadata(element.innerText);
      }
    }
    final relationships = <String, String>{};
    for (final relation
        in xmlEntry('word/_rels/document.xml.rels').descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local == 'Relationship')) {
      if (relation.getAttribute('TargetMode') == 'External') continue;
      final id = relation.getAttribute('Id'),
          target = relation.getAttribute('Target');
      if (id == null || target == null) continue;
      final path = _resolveArchivePath('word/document.xml', target);
      if (path != null && files.containsKey(path)) relationships[id] = path;
    }
    final document = xmlEntry('word/document.xml', required: true);
    final body = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'body')
        .firstOrNull;
    if (body == null) throw const FormatException('DOCX 缺少正文');
    final paragraphs = body.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'p',
    );
    if (paragraphs.length > 200000) {
      throw const FormatException('DOCX 段落过多，请拆分后导入');
    }
    for (final paragraph in paragraphs) {
      final heading = paragraph.descendants.whereType<XmlElement>().any(
        (element) =>
            element.name.local == 'pStyle' &&
            RegExp(r'heading|标题|標題|見出し', caseSensitive: false).hasMatch(
              element.getAttribute('val') ??
                  element.getAttribute(
                    'val',
                    namespaceUri:
                        'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
                  ) ??
                  '',
            ),
      );
      final text = StringBuffer();
      void flush() {
        if (heading) {
          builder.heading(text.toString());
        } else {
          builder.text(text.toString());
        }
        text.clear();
      }

      for (final node in paragraph.descendants.whereType<XmlElement>()) {
        switch (node.name.local) {
          case 't':
            text.write(node.innerText);
          case 'tab':
            text.write(' ');
          case 'br' || 'cr':
            flush();
          case 'blip' || 'imagedata':
            final id = node.attributes
                .where(
                  (attribute) =>
                      attribute.name.local == 'embed' ||
                      attribute.name.local == 'id',
                )
                .map((attribute) => attribute.value)
                .firstOrNull;
            final path = relationships[id];
            if (path != null) {
              flush();
              final image = files[path]!;
              final content = _archiveBytes(image, maxConvertedImageBytes);
              if (builder.resource(path, path.split('.').last, content)) {
                builder.image(path);
              }
            }
        }
      }
      flush();
    }
  }
}

String _baseName(String name) => name.replaceAll('\\', '/').split('/').last;
String _bookTitle(String name) =>
    _baseName(name).replaceFirst(RegExp(r'\.[^.]+$'), '');

String _xmlImageId(XmlElement image) {
  final attribute = image.attributes
      .where((attribute) => attribute.name.local == 'href')
      .firstOrNull;
  return (attribute?.value ?? '').replaceFirst('#', '');
}

String _imageStyle(html.Element image) {
  final styles = <String>[];
  for (final name in const ['width', 'height']) {
    final value = image.attributes[name] ?? '';
    if (RegExp(r'^\d+(\.\d+)?%?$').hasMatch(value)) {
      styles.add('$name:$value${value.endsWith('%') ? '' : 'px'}');
    }
  }
  return styles.join(';');
}

XmlDocument _parseXml(Uint8List bytes, String format) {
  final text = decodeLocalDocumentText(bytes);
  if (RegExp(
    r'<!\s*(?:DOCTYPE|ENTITY)\b',
    caseSensitive: false,
  ).hasMatch(text)) {
    throw FormatException('$format 不支持包含 DTD 或实体定义的文档');
  }
  try {
    final document = XmlDocument.parse(text);
    var count = 0;
    void check(XmlNode node, int depth) {
      if (depth > 256 || ++count > 500000) {
        throw FormatException('$format 嵌套过深或节点过多');
      }
      for (final child in node.children) {
        check(child, depth + 1);
      }
    }

    check(document, 0);
    return document;
  } on XmlException catch (failure) {
    throw FormatException('$format XML 无法读取：${failure.message}');
  }
}

String? _resolveArchivePath(String base, String href) {
  if (href.isEmpty || href.contains('\\') || href.contains('\u0000')) {
    return null;
  }
  try {
    final root = Uri(
      scheme: 'https',
      host: 'local',
      pathSegments: ['', ...base.split('/')],
    );
    final resolved = root.resolve(href);
    if (resolved.scheme != 'https' || resolved.host != 'local') return null;
    final path = Uri.decodeComponent(resolved.path.substring(1));
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((part) => part == '..' || part.isEmpty)) {
      return null;
    }
    return path;
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}

Never _docError(String message) => throw FormatException(message);

void _oleRange(Uint8List bytes, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > bytes.length) {
    _docError('DOC 的 CFBF 扇区或流数据不完整');
  }
}

int _oleU16(Uint8List bytes, int offset) {
  _oleRange(bytes, offset, 2);
  return bytes[offset] | bytes[offset + 1] << 8;
}

int _oleU32(Uint8List bytes, int offset) {
  _oleRange(bytes, offset, 4);
  return bytes[offset] |
      bytes[offset + 1] << 8 |
      bytes[offset + 2] << 16 |
      bytes[offset + 3] << 24;
}

class _OleEntry {
  const _OleEntry(this.name, this.type, this.start, this.size);
  final String name;
  final int type, start, size;
}

class _OleCompoundFile {
  _OleCompoundFile(this.bytes) {
    _parse();
  }
  final Uint8List bytes;
  late final int sectorSize, miniCutoff;
  late final List<int> _fat, _miniFat;
  late final Map<String, _OleEntry> _entries;
  late final _OleEntry _root;
  Uint8List? _miniStream;

  static const endOfChain = 0xfffffffe;
  static const freeSector = 0xffffffff;

  Uint8List _sector(int id) {
    final start = (id + 1) * sectorSize;
    _oleRange(bytes, start, sectorSize);
    return Uint8List.sublistView(bytes, start, start + sectorSize);
  }

  Uint8List _chain(
    int start,
    List<int> table,
    Uint8List Function(int) read,
    int maxSectors,
  ) {
    if (start == endOfChain) return Uint8List(0);
    final output = BytesBuilder(copy: false);
    final visited = <int>{};
    var current = start;
    while (current != endOfChain) {
      if (current == freeSector ||
          current < 0 ||
          current >= table.length ||
          !visited.add(current) ||
          visited.length > maxSectors) {
        _docError('DOC 的 CFBF 扇区链存在循环或越界');
      }
      output.add(read(current));
      current = table[current];
    }
    return output.toBytes();
  }

  Uint8List _regular(int start, int size) {
    if (size < 0 || size > 256 * 1024 * 1024) {
      _docError('DOC 流大小超过安全限制');
    }
    if (size == 0) return Uint8List(0);
    final sectors = (size + sectorSize - 1) ~/ sectorSize;
    final content = _chain(start, _fat, _sector, sectors);
    if (content.length < size) _docError('DOC 普通流短于声明大小');
    return Uint8List.sublistView(content, 0, size);
  }

  void _parse() {
    const signature = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
    if (bytes.length < 512 ||
        !signature.indexed.every((entry) => bytes[entry.$1] == entry.$2)) {
      _docError('DOC 缺少有效的 CFBF 文件头');
    }
    final major = _oleU16(bytes, 26);
    if (_oleU16(bytes, 28) != 0xfffe ||
        !const {3, 4}.contains(major) ||
        _oleU16(bytes, 32) != 6) {
      _docError('DOC 的 CFBF 版本或字节序不受支持');
    }
    final shift = _oleU16(bytes, 30);
    if ((major == 3 && shift != 9) || (major == 4 && shift != 12)) {
      _docError('DOC 的 CFBF 扇区大小不受支持');
    }
    sectorSize = 1 << shift;
    if (bytes.length < sectorSize) _docError('DOC 的 CFBF 文件被截断');
    final fatCount = _oleU32(bytes, 44);
    final firstDirectory = _oleU32(bytes, 48);
    miniCutoff = _oleU32(bytes, 56);
    final firstMiniFat = _oleU32(bytes, 60);
    final miniFatCount = _oleU32(bytes, 64);
    final firstDifat = _oleU32(bytes, 68);
    final difatCount = _oleU32(bytes, 72);
    final sectorCount = bytes.length ~/ sectorSize;
    if (fatCount > sectorCount ||
        miniFatCount > sectorCount ||
        difatCount > sectorCount ||
        miniCutoff != 4096) {
      _docError('DOC 的 CFBF 分配表大小无效');
    }
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < fatCount; i++) {
      final id = _oleU32(bytes, 76 + i * 4);
      if (id != freeSector) fatSectors.add(id);
    }
    var difat = firstDifat;
    final visitedDifat = <int>{};
    for (var i = 0; i < difatCount && fatSectors.length < fatCount; i++) {
      if (difat == endOfChain || !visitedDifat.add(difat)) {
        _docError('DOC 的 DIFAT 链损坏');
      }
      final sector = _sector(difat);
      final entries = sectorSize ~/ 4 - 1;
      for (var j = 0; j < entries && fatSectors.length < fatCount; j++) {
        final id = _oleU32(sector, j * 4);
        if (id != freeSector) fatSectors.add(id);
      }
      difat = _oleU32(sector, sectorSize - 4);
    }
    if (fatSectors.length != fatCount) _docError('DOC 的 DIFAT 不包含完整 FAT');
    final fat = <int>[];
    for (final id in fatSectors) {
      final sector = _sector(id);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(_oleU32(sector, i * 4));
      }
    }
    _fat = fat;
    final directory = _chain(firstDirectory, _fat, _sector, 512);
    if (directory.length % 128 != 0 || directory.length > 512 * 1024) {
      _docError('DOC 的 CFBF 目录过大或不完整');
    }
    final entries = <String, _OleEntry>{};
    _OleEntry? root;
    for (var at = 0; at < directory.length; at += 128) {
      final type = directory[at + 66];
      if (type == 0) continue;
      final nameBytes = _oleU16(directory, at + 64);
      if (nameBytes < 2 || nameBytes > 64 || nameBytes.isOdd) {
        _docError('DOC 的 CFBF 目录名称无效');
      }
      final units = <int>[
        for (var i = 0; i < nameBytes - 2; i += 2) _oleU16(directory, at + i),
      ];
      final name = String.fromCharCodes(units);
      final start = _oleU32(directory, at + 116);
      final low = _oleU32(directory, at + 120);
      final high = _oleU32(directory, at + 124);
      if (major == 3 && high != 0) _docError('DOC 的 CFBF 流大小无效');
      final size = low + (major == 4 ? high * 0x100000000 : 0);
      final entry = _OleEntry(name, type, start, size);
      if (type == 5) {
        root ??= entry;
      } else if (type == 2) {
        if (entries.containsKey(name)) _docError('DOC 的 CFBF 存在重名流');
        entries[name] = entry;
      }
    }
    if (root == null) _docError('DOC 缺少 CFBF 根目录');
    _root = root;
    _entries = entries;
    final miniFatBytes = miniFatCount == 0
        ? Uint8List(0)
        : _chain(firstMiniFat, _fat, _sector, miniFatCount);
    if (miniFatBytes.length % 4 != 0) _docError('DOC 的 MiniFAT 不完整');
    _miniFat = [
      for (var i = 0; i < miniFatBytes.length; i += 4) _oleU32(miniFatBytes, i),
    ];
  }

  Uint8List read(String name) {
    final entry = _entries[name];
    if (entry == null) _docError('DOC 缺少 $name 流');
    if (entry.size >= miniCutoff) return _regular(entry.start, entry.size);
    if (entry.size == 0) return Uint8List(0);
    _miniStream ??= _regular(_root.start, _root.size);
    final mini = _miniStream!;
    final content = _chain(entry.start, _miniFat, (id) {
      final start = id * 64;
      _oleRange(mini, start, 64);
      return Uint8List.sublistView(mini, start, start + 64);
    }, (entry.size + 63) ~/ 64);
    if (content.length < entry.size) _docError('DOC 迷你流短于声明大小');
    return Uint8List.sublistView(content, 0, entry.size);
  }

  bool contains(String name) => _entries.containsKey(name);
}

String _docStringFromUnits(List<int> units) {
  var high = false;
  for (final unit in units) {
    final low = unit >= 0xdc00 && unit <= 0xdfff;
    if (high != low) _docError('DOC 的 UTF-16 代理对不完整');
    high = unit >= 0xd800 && unit <= 0xdbff;
  }
  if (high) _docError('DOC 的 UTF-16 代理对不完整');
  return String.fromCharCodes(units);
}

String _readDocText(_OleCompoundFile ole, Uint8List word) {
  if (word.length < 64 || _oleU16(word, 0) != 0xa5ec) {
    _docError('DOC 的 WordDocument FIB 无效');
  }
  final version = _oleU16(word, 2);
  if (!const {0x00c1, 0x00d9, 0x0101, 0x010c, 0x0112}.contains(version)) {
    _docError('此 DOC 版本过旧，请另存为 Word 97–2003 DOC 或 DOCX');
  }
  final flags = _oleU16(word, 10);
  if (flags & 0x0100 != 0 || flags & 0x8000 != 0) {
    _docError('DOC 已加密或混淆，请先在 Word 中解除密码后导入');
  }
  final complex = flags & 0x0004 != 0;
  final extended = flags & 0x1000 != 0;
  final ccpText = _oleU32(word, 0x4c);
  if (ccpText <= 0 || ccpText > 128 * 1024 * 1024) {
    _docError('DOC 主文档正文为空或超过大小限制');
  }
  if (!complex) {
    final start = _oleU32(word, 0x18), end = _oleU32(word, 0x1c);
    if (start > end || end > word.length) _docError('DOC 的简单文本区间无效');
    final content = Uint8List.sublistView(word, start, end);
    if (extended) {
      if (content.length.isOdd) _docError('DOC 的 UTF-16 正文不完整');
      return _docStringFromUnits([
        for (var i = 0; i < content.length; i += 2) _oleU16(content, i),
      ]);
    }
    return decodeWindows1252(content);
  }
  var at = 32;
  final csw = _oleU16(word, at);
  at += 2;
  if (csw < 14 || at + csw * 2 + 2 > word.length) {
    _docError('DOC 的 FIB fibRgW 区无效');
  }
  at += csw * 2;
  final cslw = _oleU16(word, at);
  at += 2;
  if (cslw < 22 || at + cslw * 4 + 2 > word.length) {
    _docError('DOC 的 FIB fibRgLw 区无效');
  }
  at += cslw * 4;
  final pairCount = _oleU16(word, at);
  at += 2;
  if (pairCount < 34 || at + pairCount * 8 > word.length) {
    _docError('DOC 的 FIB 缺少 fcClx / lcbClx');
  }
  final fcClx = _oleU32(word, at + 33 * 8);
  final lcbClx = _oleU32(word, at + 33 * 8 + 4);
  if (fcClx == 0 || lcbClx == 0) _docError('DOC 缺少正文 piece table');
  final table = ole.read(flags & 0x0200 != 0 ? '1Table' : '0Table');
  _oleRange(table, fcClx, lcbClx);
  final clx = Uint8List.sublistView(table, fcClx, fcClx + lcbClx);
  at = 0;
  while (at < clx.length && clx[at] == 1) {
    if (at + 3 > clx.length) _docError('DOC 的 Clx Prc 不完整');
    final length = _oleU16(clx, at + 1);
    at += 3;
    _oleRange(clx, at, length);
    at += length;
  }
  if (at + 5 > clx.length || clx[at] != 2) _docError('DOC 的 Clx 缺少 Pcdt');
  final plcLength = _oleU32(clx, at + 1);
  at += 5;
  _oleRange(clx, at, plcLength);
  if (plcLength < 4 || (plcLength - 4) % 12 != 0) {
    _docError('DOC 的 PlcPcd 长度无效');
  }
  final count = (plcLength - 4) ~/ 12;
  if (count <= 0 || count > 1000000) _docError('DOC 的文本 piece 数量无效');
  final cpStart = at, pcdStart = at + (count + 1) * 4;
  final units = <int>[];
  var previous = 0;
  for (var i = 0; i < count; i++) {
    final first = _oleU32(clx, cpStart + i * 4);
    final last = _oleU32(clx, cpStart + (i + 1) * 4);
    if (first != previous || last < first) _docError('DOC 的 piece CP 顺序无效');
    previous = last;
    if (first >= ccpText) break;
    if (last == first) continue;
    final pcd = pcdStart + i * 8;
    _oleRange(clx, pcd, 8);
    final compressedValue = _oleU32(clx, pcd + 2);
    final compressed = compressedValue & 0x40000000 != 0;
    final position = compressedValue & 0x3fffffff;
    final take = (last > ccpText ? ccpText : last) - first;
    if (compressed) {
      final start = position ~/ 2;
      _oleRange(word, start, take);
      units.addAll(
        decodeWindows1252(
          Uint8List.sublistView(word, start, start + take),
        ).codeUnits,
      );
    } else {
      _oleRange(word, position, take * 2);
      for (var j = 0; j < take; j++) {
        units.add(_oleU16(word, position + j * 2));
      }
    }
  }
  if (units.length != ccpText) {
    _docError('DOC 的 piece table 未完整覆盖主文档正文');
  }
  return _docStringFromUnits(units);
}

void _convertOleDoc(Uint8List bytes, LocalEpubBuilder builder) {
  final ole = _OleCompoundFile(bytes);
  final word = ole.read('WordDocument');
  final hasPictures = _oleU16(word, 10) & 0x0008 != 0;
  final text = _readDocText(ole, word);
  final paragraph = StringBuffer();
  final fields = <bool>[];
  var paragraphs = 0;
  void flush() {
    final value = paragraph.toString().trim();
    paragraph.clear();
    if (value.isEmpty) return;
    if (++paragraphs > 200000) _docError('DOC 段落过多，请拆分后导入');
    final heading =
        value.length <= 120 &&
        RegExp(
          r'^(?:第[0-9零〇一二三四五六七八九十百千万两]+[章节卷回部](?:\s+.{0,80})?|chapter\s+[0-9ivxlcdm]+(?:\s+.{0,80})?|序言|序章|楔子|引子|引言|前言|后记|尾声|番外.*)$',
          caseSensitive: false,
        ).hasMatch(value);
    if (heading) {
      builder.heading(value);
    } else {
      builder.text(value);
    }
  }

  for (final unit in text.codeUnits) {
    switch (unit) {
      case 0x13:
        fields.add(false);
      case 0x14:
        if (fields.isNotEmpty) fields[fields.length - 1] = true;
      case 0x15:
        if (fields.isNotEmpty) fields.removeLast();
      default:
        if (!fields.every((visible) => visible)) continue;
        if (unit == 0x08) {
          if (hasPictures) {
            _docError('DOC 含嵌入图片，当前仅支持正文迁移；请另存 DOCX 以保留插图');
          }
        } else if (unit == 0x0d || unit == 0x0b || unit == 0x0c) {
          flush();
        } else if (unit == 0x07 || unit == 0x09) {
          paragraph.write('\t');
        } else if (unit >= 32 && unit != 0xfffc) {
          paragraph.writeCharCode(unit);
        }
    }
  }
  flush();
}

LocalConvertedDocument convertLocalPdfManifest({
  required String name,
  required String manifestPath,
  required Directory root,
  Uint8List? originalBytes,
}) {
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync() ||
      manifestFile.lengthSync() > 64 * 1024 * 1024) {
    throw const FormatException('PDF 页面清单缺失或超过 64 MiB');
  }
  final raw = jsonDecode(manifestFile.readAsStringSync());
  if (raw is! Map || raw['title'] is! String || raw['pages'] is! List) {
    throw const FormatException('PDF 页面清单格式无效');
  }
  final pages = raw['pages'] as List;
  if (pages.isEmpty || pages.length > 10000) {
    throw const FormatException('PDF 没有可读取的页面，或页数超过 10000');
  }
  final output = File('${root.path}/pdf-import.source');
  final work = Directory('${output.path}.work');
  try {
    root.createSync(recursive: true);
    final manifestTitle = (raw['title'] as String).trim();
    final builder = LocalEpubBuilder(
      work,
      manifestTitle.isEmpty ? _bookTitle(name) : manifestTitle,
    );
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page is! Map ||
          page['title'] is! String ||
          page['text'] is! String ||
          page['imagePath'] is! String) {
        throw FormatException('PDF 第 ${i + 1} 页清单格式无效');
      }
      final title = (page['title'] as String).trim();
      final text = page['text'] as String;
      final imagePath = page['imagePath'] as String;
      builder.heading(title.isEmpty ? '第 ${i + 1} 页' : title);
      builder.text(text);
      if (imagePath.isNotEmpty) {
        final image = File(imagePath);
        if (!image.existsSync() || image.lengthSync() > maxPdfPageImageBytes) {
          throw FormatException('PDF 第 ${i + 1} 页图片缺失或超过 24 MiB');
        }
        final content = image.readAsBytesSync();
        final key = 'pdf-page-$i';
        try {
          builder.pdfImage(key, content);
        } on FormatException catch (failure) {
          throw FormatException('PDF 第 ${i + 1} 页：${failure.message}');
        }
      }
      if (text.trim().isEmpty && imagePath.isEmpty) {
        throw FormatException('PDF 第 ${i + 1} 页没有真实文本或页面图');
      }
    }
    builder.write(
      output,
      originalName: originalBytes == null ? null : _baseName(name),
      originalBytes: originalBytes,
    );
    return LocalConvertedDocument(
      name: name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '.epub'),
      path: output.path,
    );
  } on FormatException {
    rethrow;
  } on FileSystemException {
    throw const FormatException('无法读取 PDF 页面清单或页面图');
  } catch (_) {
    throw const FormatException('PDF 页面清单不是有效的 JSON');
  } finally {
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}
