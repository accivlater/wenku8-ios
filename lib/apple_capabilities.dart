import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppleCapabilityActionType {
  openBook,
  continueReading,
  searchBooks,
  startListening,
  pauseListening,
}

enum AppleCapabilityActionResult { handled, cancelled }

@immutable
class AppleReadingPosition {
  const AppleReadingPosition({
    this.chapter = 0,
    this.chapterId = 0,
    this.offset = 0,
    this.fraction = 0,
    this.paragraphIndex,
    this.paragraphFraction = 0,
    this.textOffset,
    this.updatedAt = 0,
  });

  final int chapter;
  final int chapterId;
  final double offset;
  final double fraction;
  final int? paragraphIndex;
  final double paragraphFraction;
  final int? textOffset;
  final int updatedAt;

  Map<String, Object?> toMap() => {
    'chapter': chapter,
    'chapterId': chapterId,
    'offset': offset,
    'fraction': fraction,
    'paragraphIndex': ?paragraphIndex,
    'paragraphFraction': paragraphFraction,
    'textOffset': ?textOffset,
    'updatedAt': updatedAt,
  };

  factory AppleReadingPosition.fromMap(Map<Object?, Object?> map) {
    int integer(Object? value, [int fallback = 0]) =>
        value is num ? value.toInt() : fallback;
    double decimal(Object? value, [double fallback = 0]) {
      if (value is! num || !value.isFinite) return fallback;
      return value.toDouble();
    }

    return AppleReadingPosition(
      chapter: integer(map['chapter']).clamp(0, 1000000),
      chapterId: integer(map['chapterId']).clamp(0, 0x7fffffffffffffff),
      offset: decimal(map['offset']).clamp(0, double.infinity),
      fraction: decimal(map['fraction']).clamp(0, 1),
      paragraphIndex: map['paragraphIndex'] is num
          ? integer(map['paragraphIndex']).clamp(0, 100000000)
          : null,
      paragraphFraction: decimal(map['paragraphFraction']).clamp(0, 1),
      textOffset: map['textOffset'] is num
          ? integer(map['textOffset']).clamp(0, 0x7fffffffffffffff)
          : null,
      updatedAt: integer(map['updatedAt']).clamp(0, 0x7fffffffffffffff),
    );
  }
}

@immutable
class AppleBookIndex {
  const AppleBookIndex({
    required this.bookId,
    required this.title,
    required this.author,
    this.chapterTitle,
    this.position,
    this.keywords = const [],
  });

  final int bookId;
  final String title;
  final String author;
  final String? chapterTitle;
  final AppleReadingPosition? position;
  final List<String> keywords;

  AppleBookIndex withProgress(
    AppleReadingPosition position, {
    String? chapterTitle,
  }) => AppleBookIndex(
    bookId: bookId,
    title: title,
    author: author,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    position: position,
    keywords: keywords,
  );

  Map<String, Object?> toMap() => {
    'bookId': bookId,
    'title': title,
    'author': author,
    'chapterTitle': ?chapterTitle,
    'position': position?.toMap(),
    'keywords': List<String>.unmodifiable(keywords),
  };
}

@immutable
class AppleCapabilityAction {
  const AppleCapabilityAction({
    required this.id,
    required this.type,
    this.bookId,
    this.position,
    this.query = '',
  });

  final String id;
  final AppleCapabilityActionType type;
  final int? bookId;
  final AppleReadingPosition? position;
  final String query;

  static AppleCapabilityAction? tryFromMap(Object? value) {
    if (value is! Map) return null;
    try {
      final map = Map<Object?, Object?>.from(value);
      final id = map['id'];
      final name = map['action'];
      if (id is! String || id.isEmpty || name is! String) return null;
      final type = AppleCapabilityActionType.values.asNameMap()[name];
      if (type == null) return null;
      final rawBookId = map['bookId'];
      final bookId = rawBookId is num ? rawBookId.toInt() : null;
      if (type == AppleCapabilityActionType.openBook &&
          (bookId == null || bookId <= 0)) {
        return null;
      }
      final rawQuery = map['query'];
      return AppleCapabilityAction(
        id: id,
        type: type,
        bookId: bookId,
        position: map['position'] is Map
            ? AppleReadingPosition.fromMap(
                Map<Object?, Object?>.from(map['position'] as Map),
              )
            : null,
        query: rawQuery is String ? rawQuery : '',
      );
    } on Object {
      return null;
    }
  }
}

typedef AppleCapabilityActionHandler =
    FutureOr<AppleCapabilityActionResult> Function(
      AppleCapabilityAction action,
    );

class AppleCapabilities {
  static const channel = MethodChannel('org.mewx.wenku8/apple_capabilities');
  static const _dedupWindow = Duration(seconds: 15);

  AppleCapabilityActionHandler? _handler;
  Future<void>? _starting;
  Future<void> _dispatches = Future<void>.value();
  final _recentActions = <String, DateTime>{};
  var _active = false;
  var _generation = 0;

  bool get isActive => _active;

  Future<void> start(AppleCapabilityActionHandler handler) {
    _handler = handler;
    if (_active) return Future<void>.value();
    if (_starting case final starting?) return starting;
    final generation = ++_generation;
    late final Future<void> starting;
    starting = _activate(generation).whenComplete(() {
      if (identical(_starting, starting)) _starting = null;
    });
    return _starting = starting;
  }

  Future<void> _activate(int generation) async {
    channel.setMethodCallHandler(_onMethodCall);
    try {
      final pending = await channel.invokeMethod<List<Object?>>('activate');
      if (!_isCurrent(generation)) return;
      _active = true;
      for (final value in pending ?? const <Object?>[]) {
        final action = AppleCapabilityAction.tryFromMap(value);
        if (action != null) await _schedule(action, generation);
      }
    } on Object {
      if (_isCurrent(generation)) {
        _active = false;
        _handler = null;
        channel.setMethodCallHandler(null);
      }
      rethrow;
    }
  }

  bool _isCurrent(int generation) =>
      generation == _generation && _handler != null;

  Future<Object?> _onMethodCall(MethodCall call) async {
    if (call.method != 'performAction') {
      throw MissingPluginException('未实现的 Apple 能力调用：${call.method}');
    }
    final action = AppleCapabilityAction.tryFromMap(call.arguments);
    if (action == null) return AppleCapabilityActionResult.cancelled.name;
    final result = await _schedule(action, _generation);
    return result.name;
  }

  bool _isDuplicate(String id) {
    final now = DateTime.now();
    _recentActions.removeWhere(
      (_, receivedAt) => now.difference(receivedAt) > _dedupWindow,
    );
    if (_recentActions.containsKey(id)) return true;
    _recentActions[id] = now;
    if (_recentActions.length > 128) {
      _recentActions.remove(_recentActions.keys.first);
    }
    return false;
  }

  Future<AppleCapabilityActionResult> _schedule(
    AppleCapabilityAction action,
    int generation,
  ) {
    if (!_isCurrent(generation)) {
      return Future<AppleCapabilityActionResult>.value(
        AppleCapabilityActionResult.cancelled,
      );
    }
    if (_isDuplicate(action.id)) {
      return Future<AppleCapabilityActionResult>.value(
        AppleCapabilityActionResult.handled,
      );
    }
    final dispatched = _dispatches.then((_) => _dispatch(action, generation));
    _dispatches = dispatched.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return dispatched;
  }

  Future<AppleCapabilityActionResult> _dispatch(
    AppleCapabilityAction action,
    int generation,
  ) async {
    if (!_isCurrent(generation)) {
      _recentActions.remove(action.id);
      return AppleCapabilityActionResult.cancelled;
    }
    try {
      final result = await _handler!(action);
      if (result == AppleCapabilityActionResult.cancelled &&
          generation == _generation) {
        _recentActions.remove(action.id);
      }
      return result;
    } on Object {
      if (generation == _generation) _recentActions.remove(action.id);
      return AppleCapabilityActionResult.cancelled;
    }
  }

  Future<void> indexBook(AppleBookIndex book) => indexBooks([book]);

  Future<void> indexBooks(Iterable<AppleBookIndex> books) async {
    final items = books.map((book) => book.toMap()).toList(growable: false);
    if (items.isEmpty) return;
    await channel.invokeMethod<void>('indexBooks', {'books': items});
  }

  Future<void> updateReadingProgress(
    AppleBookIndex book,
    AppleReadingPosition position, {
    String? chapterTitle,
  }) => indexBook(book.withProgress(position, chapterTitle: chapterTitle));

  Future<void> removeIndex(int bookId) => removeIndexes([bookId]);

  Future<void> removeIndexes(Iterable<int> bookIds) async {
    final ids = bookIds.toList(growable: false);
    if (ids.isEmpty) return;
    await channel.invokeMethod<void>('removeIndexes', {'bookIds': ids});
  }

  Future<Set<int>> indexedBookIds() async {
    final ids = await channel.invokeMethod<List<Object?>>('indexedBookIDs');
    return {
      for (final id in ids ?? const <Object?>[])
        if (id is num) id.toInt(),
    };
  }

  Future<void> removeAllIndexes() =>
      channel.invokeMethod<void>('removeAllIndexes');

  Future<void> prepareShortcuts() =>
      channel.invokeMethod<void>('donateActions', const {
        'actions': [
          {'action': 'continueReading', 'title': '继续阅读', 'phrase': '继续阅读'},
          {'action': 'searchBooks', 'title': '搜索书籍', 'phrase': '搜索书籍'},
          {'action': 'startListening', 'title': '开始听书', 'phrase': '开始听书'},
          {'action': 'pauseListening', 'title': '暂停听书', 'phrase': '暂停听书'},
        ],
      });

  Future<void> dispose() async {
    if (!_active && _starting == null && _handler == null) return;
    ++_generation;
    _active = false;
    _starting = null;
    _handler = null;
    _recentActions.clear();
    channel.setMethodCallHandler(null);
    await channel.invokeMethod<void>('deactivate');
  }
}
