import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'book_import_limits.dart';
import 'local_document_converter.dart';

class BookDocumentSelection {
  const BookDocumentSelection({
    required this.name,
    this.path,
    this.error,
    this.originReference,
    this.originName,
  }) : token = null,
       reference = null,
       assert((path == null) != (error == null));
  const BookDocumentSelection.pending({required this.name, required this.token})
    : path = null,
      reference = null,
      originReference = null,
      originName = null,
      error = null;
  const BookDocumentSelection.linked({
    required this.name,
    required this.reference,
  }) : path = null,
       token = null,
       originReference = null,
       originName = null,
       error = null;
  final String name;
  final String? path, error, token, reference;
  final String? originReference, originName;

  factory BookDocumentSelection.fromMap(Map<dynamic, dynamic> value) =>
      value['reference'] is String
      ? BookDocumentSelection.linked(
          name: value['name'] as String,
          reference: value['reference'] as String,
        )
      : value['token'] is String
      ? BookDocumentSelection.pending(
          name: value['name'] as String,
          token: value['token'] as String,
        )
      : BookDocumentSelection(
          name: value['name'] as String,
          path: value['path'] as String?,
          error: value['error'] as String?,
        );
}

class BookScanFolder {
  const BookScanFolder({
    required this.name,
    required this.automatic,
    required this.readable,
    this.allStorage = false,
  });
  factory BookScanFolder.fromMap(Map<dynamic, dynamic> value) => BookScanFolder(
    name: value['name'] as String,
    automatic: value['automatic'] == true,
    readable: value['readable'] == true,
    allStorage: value['all'] == true,
  );
  final String name;
  final bool automatic, readable;
  final bool allStorage;
}

class BookOpenRequest {
  const BookOpenRequest({
    required this.id,
    required this.name,
    required this.canLink,
    this.error,
  });
  factory BookOpenRequest.fromMap(Map<dynamic, dynamic> value) =>
      BookOpenRequest(
        id: value['id'] as String,
        name: value['name'] as String,
        canLink: value['canLink'] == true,
        error: value['error'] as String?,
      );
  final String id, name;
  final bool canLink;
  final String? error;
}

typedef BookScanEntry = ({String token, String name});

class BookScanSnapshot {
  const BookScanSnapshot({
    required this.books,
    this.total = 0,
    this.unchanged = 0,
    this.warnings = const [],
    this.details = const {},
  });
  final List<BookScanEntry> books;
  final int total, unchanged;
  final List<String> warnings;
  final Map<String, ({int? size, String folder})> details;
}

class BookDocuments {
  static const channel = MethodChannel('org.mewx.wenku8/book_documents');
  Future<BookOpenRequest?> pendingOpen() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pendingBookOpen',
    );
    return value == null ? null : BookOpenRequest.fromMap(value);
  }

  Future<BookDocumentSelection> resolveOpen(
    String id, {
    bool copy = false,
  }) async => BookDocumentSelection.fromMap(
    (await channel.invokeMapMethod<String, dynamic>('resolveBookOpen', {
      'id': id,
      'copy': copy,
    }))!,
  );

  Future<BookDocumentSelection?> authorizeOpen(String id) async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickBookOpenReference',
      {'id': id},
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<void> finishOpen(String id) =>
      channel.invokeMethod<void>('finishBookOpen', {'id': id});

  Future<BookDocumentSelection?> pickImage() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickImage');
    return value == null
        ? null
        : BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String,
          );
  }

  Future<BookDocumentSelection?> pickFont() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickFont');
    return value == null
        ? null
        : BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String,
          );
  }

  Future<BookScanFolder?> scanFolderInfo() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'scanFolderInfo',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<BookScanFolder?> selectScanFolder() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'selectScanFolder',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<void> setScanAutomatic(bool value) =>
      channel.invokeMethod<void>('setScanAutomatic', {'value': value});
  Future<BookScanFolder?> selectAllScan() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'selectAllScan',
    );
    return value == null ? null : BookScanFolder.fromMap(value);
  }

  Future<void> disconnectScanFolder() =>
      channel.invokeMethod<void>('disconnectScanFolder');
  Future<Set<String>> scanFormats() async {
    final extensions = await channel.invokeListMethod<String>('scanFormats');
    return extensions == null
        ? bookFormatLabels.keys.toSet()
        : extensions.map((e) => bookFormatKey('book.$e')).toSet();
  }

  Future<void> setScanFormats(Set<String> formats) =>
      channel.invokeMethod<void>('setScanFormats', {
        'extensions': bookFormatExtensions(formats).toList(),
      });
  Future<BookScanSnapshot> scanBooks() async {
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'scanBooks',
    ))!;
    return BookScanSnapshot(
      books: [
        for (final book in value['books'] as List)
          (token: book['token'] as String, name: book['name'] as String),
      ],
      total: value['total'] as int,
      unchanged: value['unchanged'] as int,
      warnings: (value['warnings'] as List).cast<String>(),
      details: {
        for (final book in value['books'] as List)
          book['token'] as String: (
            size: book['size'] as int?,
            folder: book['folder'] as String? ?? '',
          ),
      },
    );
  }

  Future<BookDocumentSelection> stageScanBook(String token) async {
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'stageScanBook',
      {'token': token},
    ))!;
    return BookDocumentSelection(
      name: value['name'] as String,
      path: value['path'] as String,
    );
  }

  Future<BookDocumentSelection> linkScanBook(String token) async =>
      BookDocumentSelection.fromMap(
        (await channel.invokeMapMethod<String, dynamic>('linkScanBook', {
          'token': token,
        }))!,
      );

  Future<BookDocumentSelection?> pickTextReference() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickTextReference',
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<BookDocumentSelection?> pickOriginalReference() async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'pickOriginalReference',
    );
    return value == null ? null : BookDocumentSelection.fromMap(value);
  }

  Future<String> stagedTextReference(String path) async => (await channel
      .invokeMethod<String>('stagedTextReference', {'path': path}))!;

  Future<void> markScanBook(String token) =>
      channel.invokeMethod<void>('markScanBook', {'token': token});
  Future<void> finishBookScan() => channel.invokeMethod<void>('finishBookScan');
  Future<({String name, String path})?> pickBook() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickBook');
    return value == null
        ? null
        : (name: value['name'] as String, path: value['path'] as String);
  }

  Future<List<BookDocumentSelection>> pickBooks() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks');
    return [
      for (final value in values ?? const [])
        BookDocumentSelection(
          name: value['name'] as String,
          path: value['path'] as String?,
          error: value['error'] as String?,
        ),
    ];
  }

  /// Select references, not copies of an entire library. Existing pickBooks
  /// callers retain their ready-to-read path contract.
  Future<List<BookDocumentSelection>> pickForImport() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks', {
      'deferred': true,
      'linkOriginals': true,
    });
    return [
      for (final value in values ?? const [])
        BookDocumentSelection.fromMap(value),
    ];
  }

  Future<List<BookDocumentSelection>> pickCopiesForImport() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks', {
      'deferred': true,
    });
    return [
      for (final value in values ?? const [])
        BookDocumentSelection.fromMap(value),
    ];
  }

  Future<BookDocumentSelection> stageForImport(
    BookDocumentSelection book,
  ) async {
    if (book.token == null) return book;
    final value = (await channel.invokeMapMethod<String, dynamic>(
      'stageImportBook',
      {'token': book.token},
    ))!;
    return BookDocumentSelection.fromMap(value);
  }

  static const pdfChannel = MethodChannel('org.mewx.wenku8/pdf_import');
  static final _dartStaging = <String, Directory>{};

  static Future<List<LocalConvertedDocument>> _convertJob(
    (String, String, String) job,
  ) async {
    final (name, path, root) = job;
    final file = File(path);
    final size = await file.length();
    if (size <= 0) throw const FormatException('文件为空，请重新下载原书');
    if (size > localBookByteLimit(name)) {
      throw FormatException(localBookSizeMessage(name));
    }
    return LocalDocumentConverter(
      Directory(root),
    ).convert(name, await file.readAsBytes());
  }

  static Future<LocalConvertedDocument> _pdfJob(
    (String, String, String, String) job,
  ) async {
    final (name, manifestPath, root, sourcePath) = job;
    final source = File(sourcePath);
    final size = await source.length();
    if (size <= 0 || size > localBookByteLimit(name)) {
      throw FormatException(localBookSizeMessage(name));
    }
    return convertLocalPdfManifest(
      name: name,
      manifestPath: manifestPath,
      root: Directory(root),
      originalBytes: await source.readAsBytes(),
    );
  }

  static final _dartStagingRetired = <String, Directory>{};

  Future<void> releaseBooks(Iterable<BookDocumentSelection> books) async {
    final items = books.toList();
    final nativePaths = <String>{};
    Object? failure;
    for (final path in items.map((book) => book.path).whereType<String>()) {
      final root = _dartStaging[path] ?? _dartStagingRetired[path];
      if (root == null) {
        nativePaths.add(path);
        continue;
      }
      if (_dartStaging.containsKey(path)) {
        _dartStaging.remove(path);
        _dartStagingRetired[path] = root;
      }
      if (_dartStaging.values.contains(root)) continue;
      try {
        if (await root.exists()) await root.delete(recursive: true);
        _dartStagingRetired.removeWhere((_, directory) => directory == root);
      } catch (error) {
        _dartStagingRetired.remove(path);
        _dartStaging[path] = root;
        failure ??= error;
      }
    }
    try {
      await channel.invokeMethod<void>('releaseBooks', {
        'paths': nativePaths.toList(),
        if (items.any((book) => book.token != null))
          'tokens': items
              .map((book) => book.token)
              .whereType<String>()
              .toSet()
              .toList(),
      });
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }

  Future<List<BookDocumentSelection>> _convertCopiedBook(
    BookDocumentSelection book,
  ) async {
    Directory? root;
    var retain = false;
    try {
      final source = File(book.path!);
      final size = await source.length();
      if (size <= 0) throw const FormatException('文件为空，请重新下载原书');
      if (size > localBookByteLimit(book.name)) {
        throw FormatException(localBookSizeMessage(book.name));
      }
      root = await Directory.systemTemp.createTemp('wenku8-dart-import-');
      final converted = <LocalConvertedDocument>[];
      if (book.name.toLowerCase().endsWith('.pdf')) {
        final result = await pdfChannel.invokeMapMethod<String, dynamic>(
          'convert',
          {'path': book.path, 'name': book.name},
        );
        final manifestPath = result?['manifestPath'];
        if (manifestPath is! String || manifestPath.isEmpty) {
          throw const FormatException('PDF 转换未返回页面清单');
        }
        converted.add(
          await compute(_pdfJob, (
            book.name,
            manifestPath,
            root.path,
            book.path!,
          )),
        );
      } else {
        converted.addAll(
          await compute(_convertJob, (book.name, book.path!, root.path)),
        );
      }
      for (final item in converted) {
        if (item.path != null) _dartStaging[item.path!] = root;
      }
      retain = converted.any((item) => item.path != null);
      return [
        for (final item in converted)
          BookDocumentSelection(
            name: item.name,
            path: item.path,
            error: item.error,
          ),
      ];
    } on PlatformException catch (failure) {
      return [
        BookDocumentSelection(
          name: book.name,
          error: failure.message ?? '无法解析这本书',
        ),
      ];
    } on FormatException catch (failure) {
      return [BookDocumentSelection(name: book.name, error: failure.message)];
    } on FileSystemException {
      return [
        BookDocumentSelection(
          name: book.name,
          error: '无法读取原文件或写入转换结果，请检查文件与剩余空间',
        ),
      ];
    } on Exception {
      return [
        BookDocumentSelection(name: book.name, error: '无法解析这本书，请确认文件完整且格式受支持'),
      ];
    } finally {
      if (!retain && root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }

  /// Existing TXT/EPUB callers keep their original, platform-independent path.
  /// Other copied documents become real EPUBs; linked Android documents retain
  /// the existing native lease and origin semantics.
  Future<List<BookDocumentSelection>> prepareBook(
    BookDocumentSelection book,
  ) async {
    if (book.error != null ||
        book.path == null && book.reference == null ||
        RegExp(r'\.(txt|epub)$', caseSensitive: false).hasMatch(book.name)) {
      return [book];
    }
    if (book.reference == null &&
        (!book.name.toLowerCase().endsWith('.pdf') ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return _convertCopiedBook(book);
    }
    try {
      final values = await channel.invokeListMethod<dynamic>(
        book.reference == null ? 'prepareBook' : 'prepareLinkedDocument',
        {
          'name': book.name,
          if (book.reference == null)
            'path': book.path
          else
            'reference': book.reference,
        },
      );
      return [
        for (final value in values ?? const [])
          BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String?,
            error: value['error'] as String?,
            originReference: book.reference,
            originName: book.reference == null ? null : book.name,
          ),
      ];
    } on PlatformException catch (failure) {
      return [
        BookDocumentSelection(
          name: book.name,
          error: failure.message ?? '无法解析这本书',
        ),
      ];
    }
  }

  Future<String> decodeText(String path, {String encoding = 'auto'}) async =>
      (await channel.invokeMethod<String>('decodeText', {
        'path': path,
        'encoding': encoding,
      }))!;
  Future<String> decodeTextFile(
    String path, {
    String encoding = 'auto',
  }) async => (await channel.invokeMethod<String>('decodeTextFile', {
    'path': path,
    'encoding': encoding,
  }))!;
  Future<Map<String, dynamic>?> connect({required bool create}) => channel
      .invokeMapMethod<String, dynamic>(create ? 'createSync' : 'openSync');
  Future<Map<String, dynamic>?> info() =>
      channel.invokeMapMethod<String, dynamic>('syncInfo');
  Future<({File before, File output})> read() async {
    final value = await channel.invokeMapMethod<String, dynamic>('readSync');
    if (value == null) throw const FormatException('无法读取云同步文件');
    return (before: File(value['path']), output: File(value['outputPath']));
  }

  Future<void> write(File before, File next) => channel.invokeMethod<void>(
    'writeSync',
    {'path': next.path, 'expectedPath': before.path},
  );
  Future<void> disconnect() => channel.invokeMethod<void>('disconnectSync');
  Future<File?> recovery(String which) async {
    final path = await channel.invokeMethod<String>('recoverSync', {
      'which': which,
    });
    return path == null ? null : File(path);
  }
}
