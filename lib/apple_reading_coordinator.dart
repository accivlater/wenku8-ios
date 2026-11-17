import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_interactions.dart';
import 'apple_capabilities.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'listening/controller.dart';
import 'listening/models.dart';
import 'local_books.dart';
import 'offline_repository.dart';
import 'pages.dart';
import 'reader_handoff_navigation.dart';

class AppleReadingCoordinator {
  AppleReadingCoordinator({
    required this.state,
    required this.repository,
    required this.listening,
    required this.navigator,
    required this.homeShell,
    required this.readerHandoff,
    AppleCapabilities? capabilities,
    this.indexDebounce = const Duration(milliseconds: 350),
  }) : capabilities = capabilities ?? AppleCapabilities();

  final LibraryState state;
  final NovelRepository repository;
  final ListeningController? listening;
  final GlobalKey<NavigatorState> navigator;
  final GlobalKey<HomeShellState> homeShell;
  final ReaderHandoffNavigation readerHandoff;
  final AppleCapabilities capabilities;
  final Duration indexDebounce;

  LocalBookStore? get localBooks => repository is OfflineNovelRepository
      ? (repository as OfflineNovelRepository).local
      : null;

  var _started = false;
  var _disposed = false;
  var _indexRunning = false;
  var _indexDirty = false;
  var _indexFailureVisible = false;
  Timer? _indexTimer;
  Set<int>? _knownIndexedIds;
  final _indexSignatures = <int, String>{};

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    state.historyChanges.addListener(_requestIndexSync);
    localBooks?.addListener(_requestIndexSync);
    _requestIndexSync();
    try {
      await capabilities.start(_handleAction);
    } on Object {
      if (!_disposed) _showFailure('Apple 快捷动作尚未就绪，请稍后重试');
    }
    if (_disposed) return;
    try {
      await capabilities.prepareShortcuts();
    } on Object {
      if (!_disposed) _showFailure('Apple 快捷指令尚未准备好，请稍后重试');
    }
  }

  Future<AppleCapabilityActionResult> _handleAction(
    AppleCapabilityAction action,
  ) async {
    if (_disposed) return AppleCapabilityActionResult.cancelled;
    try {
      switch (action.type) {
        case AppleCapabilityActionType.openBook:
          final id = action.bookId;
          if (id == null) throw const _AppleActionFailure('这本书已无法打开');
          await _openBook(id, action.position);
        case AppleCapabilityActionType.continueReading:
          await _continueReading();
        case AppleCapabilityActionType.searchBooks:
          await _searchBooks(action.query);
        case AppleCapabilityActionType.startListening:
          await _startListening(action);
        case AppleCapabilityActionType.pauseListening:
          await _pauseListening();
      }
      return _disposed
          ? AppleCapabilityActionResult.cancelled
          : AppleCapabilityActionResult.handled;
    } on _AppleActionFailure catch (failure) {
      if (!_disposed) _showFailure(failure.message);
      return AppleCapabilityActionResult.cancelled;
    } on Object {
      if (!_disposed) _showFailure('Apple 快捷操作未完成，请重试');
      return AppleCapabilityActionResult.cancelled;
    }
  }

  Future<Novel> _resolveBook(int id) async {
    final offline = repository;
    Novel? book = offline is OfflineNovelRepository
        ? await offline.cachedBook(id)
        : null;
    book ??= await repository.find(id);
    if (book == null) {
      throw const _AppleActionFailure('这本书已不在本机，未打开其他书籍');
    }
    if (book.chapters.isEmpty) {
      book = book.withChapters(await repository.chapters(id));
    }
    if (book.chapters.isEmpty) {
      throw const _AppleActionFailure('这本书暂时没有可打开的章节');
    }
    return book;
  }

  MapEntry<int, ReadingPosition>? get _latestReading {
    final positions = state.readingPositions.entries.toList()
      ..sort((a, b) {
        final time = b.value.updatedAt.compareTo(a.value.updatedAt);
        return time != 0 ? time : b.key.compareTo(a.key);
      });
    return positions.firstOrNull;
  }

  Future<void> _continueReading() async {
    final latest = _latestReading;
    if (latest == null) {
      throw const _AppleActionFailure('还没有阅读记录，未擅自打开书籍');
    }
    await _openBook(latest.key, null);
  }

  Future<void> _openBook(int id, AppleReadingPosition? incoming) async {
    final book = await _resolveBook(id);
    if (_disposed) return;
    final position = _readingPosition(book, incoming);
    await readerHandoff.open(
      bookId: book.id,
      position: position,
      page: ReaderPage(
        novel: book,
        state: state,
        repository: repository,
        initialChapter: position.chapter,
        initialPosition: position,
        directEntry: true,
      ),
      reduceMotion: state.effectiveReduceMotion,
    );
  }

  ReadingPosition _readingPosition(Novel book, AppleReadingPosition? incoming) {
    final existing = state.positionFor(book.id);
    final requestedChapter = incoming?.chapter ?? existing?.chapter ?? 0;
    final requestedChapterId = incoming?.chapterId ?? existing?.chapterId ?? 0;
    final requested = ReadingPosition(
      chapter: requestedChapter,
      chapterId: requestedChapterId,
      offset: incoming?.offset ?? existing?.offset ?? 0,
      fraction: incoming?.fraction ?? existing?.fraction ?? 0,
      fontSize: existing?.fontSize ?? state.readerFontSizeFor(book.id),
      width: existing?.width ?? 0,
      updatedAt: existing?.updatedAt ?? 0,
    );
    final chapter = state.chapterForPosition(book, requested);
    if (chapter == null) {
      throw const _AppleActionFailure('保存的章节已变化，未打开错误章节');
    }
    final chapterId = book.chapters[chapter].id;
    final sameExistingChapter =
        existing != null &&
        (existing.chapterId > 0
            ? existing.chapterId == chapterId
            : existing.chapter == chapter);
    final keepAnchors =
        incoming == null ||
        incoming.paragraphIndex == null && incoming.textOffset == null;
    return ReadingPosition(
      chapter: chapter,
      chapterId: chapterId,
      offset: incoming?.offset ?? existing?.offset ?? 0,
      fraction: incoming?.fraction ?? existing?.fraction ?? 0,
      fontSize: existing?.fontSize ?? state.readerFontSizeFor(book.id),
      width: existing?.width ?? 0,
      updatedAt: incoming != null && incoming.updatedAt > 0
          ? incoming.updatedAt
          : existing?.updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      lineHeight: existing?.lineHeight ?? state.readerLineHeightFor(book.id),
      paragraphIndex:
          incoming?.paragraphIndex ??
          (sameExistingChapter && keepAnchors ? existing.paragraphIndex : null),
      paragraphFraction: sameExistingChapter && keepAnchors
          ? existing.paragraphFraction
          : incoming?.paragraphFraction ?? 0,
      textOffset:
          incoming?.textOffset ??
          (sameExistingChapter && keepAnchors ? existing.textOffset : null),
      textScale: existing?.textScale ?? 1,
      typeface: existing?.typeface ?? state.readerFontIdFor(book.id),
      layout: existing?.layout ?? state.readerPreferencesFor(book.id).layoutKey,
      contentRevision: existing?.contentRevision ?? '',
    );
  }

  Future<void> _searchBooks(String query) async {
    final home = homeShell.currentState;
    if (home == null) {
      throw const _AppleActionFailure('搜索页面尚未准备好，请重试');
    }
    navigator.currentState?.popUntil((route) => route.isFirst);
    await home.searchBooks(query.trim());
  }

  Future<void> _startListening(AppleCapabilityAction action) async {
    final controller = listening;
    if (controller == null) {
      throw const _AppleActionFailure('当前版本没有可用的听书播放器');
    }
    var current = controller.snapshot.value;
    if (current.active &&
        current.novel != null &&
        (action.bookId == null || current.novel!.id == action.bookId)) {
      await controller.resume();
      _verifyListeningStarted(controller, current.novel!.id);
      return;
    }

    final Novel book;
    if (action.bookId case final id?) {
      book = await _resolveBook(id);
    } else if (current.novel != null) {
      book = current.novel!;
    } else {
      final latest = _latestReading;
      if (latest == null) {
        throw const _AppleActionFailure('没有可续听的书籍或阅读记录');
      }
      book = await _resolveBook(latest.key);
    }
    if (_disposed) return;
    final position = _readingPosition(book, action.position);
    current = controller.snapshot.value;
    if (current.novel != null && current.novel!.id != book.id) {
      await controller.stop();
    }
    await controller.start(
      book,
      chapter: position.chapter,
      resume: true,
      autoplay: true,
    );
    _verifyListeningStarted(controller, book.id);
  }

  void _verifyListeningStarted(ListeningController controller, int bookId) {
    final snapshot = controller.snapshot.value;
    if (snapshot.novel?.id != bookId ||
        !snapshot.active ||
        !snapshot.playRequested ||
        snapshot.phase == ListeningPhase.failed) {
      throw const _AppleActionFailure('听书未能开始，请在阅读器中重试');
    }
  }

  Future<void> _pauseListening() async {
    final controller = listening;
    if (controller == null || controller.snapshot.value.novel == null) {
      throw const _AppleActionFailure('当前没有可暂停的听书会话');
    }
    await controller.pause();
    final snapshot = controller.snapshot.value;
    if (snapshot.playRequested || snapshot.playing) {
      throw const _AppleActionFailure('听书尚未暂停，请重试');
    }
  }

  void _requestIndexSync() {
    if (_disposed) return;
    _indexDirty = true;
    _indexTimer?.cancel();
    _indexTimer = Timer(indexDebounce, _drainIndexSync);
  }

  void _drainIndexSync() {
    _indexTimer = null;
    if (_disposed || _indexRunning || !_indexDirty) return;
    _indexDirty = false;
    _indexRunning = true;
    unawaited(
      _synchronizeIndexes().whenComplete(() {
        _indexRunning = false;
        if (_indexDirty && !_disposed) _requestIndexSync();
      }),
    );
  }

  Future<void> _synchronizeIndexes() async {
    try {
      final known = _knownIndexedIds ??= await capabilities.indexedBookIds();
      final desired = _desiredIndexes();
      final stale = known.difference(desired.keys.toSet());
      if (stale.isNotEmpty) {
        await capabilities.removeIndexes(stale);
        known.removeAll(stale);
        for (final id in stale) {
          _indexSignatures.remove(id);
        }
      }
      final changed = <AppleBookIndex>[];
      final signatures = <int, String>{};
      for (final entry in desired.entries) {
        final signature = jsonEncode(entry.value.toMap());
        signatures[entry.key] = signature;
        if (!known.contains(entry.key) ||
            _indexSignatures[entry.key] != signature) {
          changed.add(entry.value);
        }
      }
      if (changed.isNotEmpty) {
        await capabilities.indexBooks(changed);
        known.addAll(changed.map((book) => book.bookId));
        for (final book in changed) {
          _indexSignatures[book.bookId] = signatures[book.bookId]!;
        }
      }
      _indexFailureVisible = false;
    } on Object {
      if (!_disposed && !_indexFailureVisible) {
        _indexFailureVisible = true;
        _showFailure('Spotlight 书籍索引暂未更新，将在下次变化时重试');
      }
    }
  }

  Map<int, AppleBookIndex> _desiredIndexes() {
    final books = <int, Novel>{
      for (final book in localBooks?.books ?? const <Novel>[]) book.id: book,
    };
    for (final id in state.readingPositions.keys) {
      if (isLocalBook(id)) {
        final book = localBooks?.book(id);
        if (book != null) books[id] = book;
        continue;
      }
      final offline = repository;
      final book =
          state.cachedNovel(id) ??
          (offline is OfflineNovelRepository
              ? offline.cache.book(id)?.novel
              : null);
      if (book != null) books[id] = book;
    }
    return {
      for (final entry in books.entries)
        entry.key: _appleIndex(entry.value, state.positionFor(entry.key)),
    };
  }

  AppleBookIndex _appleIndex(Novel book, ReadingPosition? position) {
    final chapter = position == null
        ? null
        : state.chapterForPosition(book, position);
    return AppleBookIndex(
      bookId: book.id,
      title: book.title,
      author: book.author,
      chapterTitle: chapter == null
          ? null
          : book.readingTitleFor(
              chapter,
              paragraph: position!.paragraphIndex ?? 0,
              offset: position.textOffset ?? 0,
            ),
      position: position == null ? null : _applePosition(position),
    );
  }

  AppleReadingPosition _applePosition(ReadingPosition position) =>
      AppleReadingPosition(
        chapter: position.chapter,
        chapterId: position.chapterId,
        offset: position.offset,
        fraction: position.fraction,
        paragraphIndex: position.paragraphIndex,
        paragraphFraction: position.paragraphFraction,
        textOffset: position.textOffset,
        updatedAt: position.updatedAt,
      );

  void _showFailure(String message) {
    void show() {
      if (_disposed) return;
      final context = navigator.currentState?.overlay?.context;
      if (context != null && context.mounted) {
        showNovelFeedback(context, message);
      }
    }

    final context = navigator.currentState?.overlay?.context;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _indexTimer?.cancel();
    state.historyChanges.removeListener(_requestIndexSync);
    localBooks?.removeListener(_requestIndexSync);
    try {
      await capabilities.dispose();
    } on Object {
      return;
    }
  }
}

class _AppleActionFailure implements Exception {
  const _AppleActionFailure(this.message);
  final String message;
}
