import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wenku8_flutter/main.dart' as app;
import 'package:wenku8_flutter/pages.dart';
import 'package:wenku8_flutter/wenku_features.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('cloud books merge into the real main shelf', (tester) async {
    await app.main();
    await tester.pump();
    final context = tester.element(find.byType(HomeShell));
    final features = WenkuFeaturesScope.maybeOf(context)!;
    final account = features.account;
    final sync = features.shelfSync!;
    final state = sync.library;
    var completed = false, mainShelfVisible = false;
    final file = File(
      '${(await getTemporaryDirectory()).path}/cloud-shelf-device.json',
    );
    Future<void> save() => file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'completed': completed,
        'authenticated': account.authenticated,
        'remoteCount': account.cloudBooks?.length,
        'localCount': state.shelf.length,
        'missingRemoteIds': account.cloudBooks
            ?.where((book) => !state.contains(book.id))
            .map((book) => book.id)
            .toList(),
        'syncError': sync.error,
        'mainShelfVisible': mainShelfVisible,
      }),
    );
    await save();
    addTearDown(save);

    await account.initialize();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 120; attempt++) {
        if (!sync.syncing && sync.syncedAt == null) {
          await sync.synchronize();
        }
        if (!sync.syncing && sync.syncedAt != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    });
    await tester.pump();

    expect(account.authenticated, isTrue);
    expect(sync.error, isNull);
    expect(sync.syncedAt, isNotNull);
    expect(account.cloudBooks, isNotNull);
    expect(account.cloudBooks, isNotEmpty);
    expect(
      account.cloudBooks!.where((book) => !state.contains(book.id)),
      isEmpty,
    );

    Navigator.of(context).popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dock-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ShelfPage), findsOneWidget);
    mainShelfVisible = true;
    completed = true;
    await save();
    debugPrint('CLOUD_SHELF_DEVICE_RESULT=${file.path}');
  });
}
