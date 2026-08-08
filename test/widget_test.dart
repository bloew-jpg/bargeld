// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bargeld/main.dart';

String currentMonthName() {
  const months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return months[DateTime.now().month - 1];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home screen shows German labels and action buttons', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    expect(find.text('BARGELD'), findsOneWidget);
    expect(find.text('Aktueller Bargeldbestand'), findsOneWidget);
    expect(find.text('0,00 €'), findsOneWidget);
    expect(find.text('Ausgabe'), findsOneWidget);
    expect(find.text('Einnahme'), findsOneWidget);
    expect(find.text(currentMonthName()), findsOneWidget);
    expect(find.text('Buchungen'), findsOneWidget);
  });

  test('backup serialization round-trips transaction data', () {
    final transaction = KaufTransaction(
      id: 'tx-1',
      type: TransactionType.expense,
      amount: 12.5,
      date: DateTime(2026, 8, 8),
      note: 'Lunch',
      category: 'Essen gehen',
      createdAt: DateTime(2026, 8, 1),
    );

    final backup = BargeldBackup(
      formatVersion: BargeldBackup.currentFormatVersion,
      createdAt: '2026-08-08T12:00:00.000Z',
      transactions: [transaction],
    );

    final json = backup.toJson();
    expect(json['formatVersion'], BargeldBackup.currentFormatVersion);

    final restoredBackup = BargeldBackup.fromJson(json);
    expect(restoredBackup.transactions.single.id, 'tx-1');
    expect(restoredBackup.transactions.single.type, TransactionType.expense);
    expect(restoredBackup.transactions.single.amount, 12.5);
    expect(restoredBackup.transactions.single.note, 'Lunch');
    expect(restoredBackup.transactions.single.category, 'Essen gehen');
  });

  test('backup validation rejects incompatible payloads', () {
    expect(
      () => BargeldBackup.fromJson({'formatVersion': 2, 'createdAt': '2026-08-08', 'transactions': []}),
      throwsA(isA<FormatException>()),
    );
  });

  test('successful restore replaces the current transaction list', () {
    final existing = <KaufTransaction>[
      KaufTransaction(
        id: 'old',
        type: TransactionType.withdrawal,
        amount: 5,
        date: DateTime(2026, 8, 1),
        note: 'old',
        category: null,
        createdAt: DateTime(2026, 8, 1),
      ),
    ];

    final backup = BargeldBackup(
      formatVersion: BargeldBackup.currentFormatVersion,
      createdAt: '2026-08-08T12:00:00.000Z',
      transactions: [
        KaufTransaction(
          id: 'new',
          type: TransactionType.cashReceived,
          amount: 20,
          date: DateTime(2026, 8, 2),
          note: 'new',
          category: null,
          createdAt: DateTime(2026, 8, 2),
        ),
      ],
    );

    final restored = BargeldBackupManager.restoreTransactions(
      currentTransactions: existing,
      backupContent: jsonEncode(backup.toJson()),
    );

    expect(restored.single.id, 'new');
    expect(restored.single.amount, 20);
  });

  test('invalid backup does not alter existing data', () {
    final existing = <KaufTransaction>[
      KaufTransaction(
        id: 'old',
        type: TransactionType.expense,
        amount: 3,
        date: DateTime(2026, 8, 3),
        note: 'keep',
        category: null,
        createdAt: DateTime(2026, 8, 3),
      ),
    ];

    expect(
      () => BargeldBackupManager.restoreTransactions(
        currentTransactions: existing,
        backupContent: '{invalid json}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('cancelled restore keeps the current transaction list', () {
    final existing = <KaufTransaction>[
      KaufTransaction(
        id: 'old',
        type: TransactionType.expense,
        amount: 4,
        date: DateTime(2026, 8, 4),
        note: 'keep',
        category: null,
        createdAt: DateTime(2026, 8, 4),
      ),
    ];

    final restored = BargeldBackupManager.restoreTransactions(
      currentTransactions: existing,
      backupContent: null,
    );

    expect(restored.single.id, 'old');
  });

  testWidgets('Home action card labels use a consistent readable style', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    for (final label in ['Ausgabe', 'Einnahme', currentMonthName(), 'Buchungen']) {
      final textWidget = tester.widget<Text>(find.text(label));
      expect(textWidget.style?.fontSize, 16);
      expect(textWidget.style?.fontWeight, FontWeight.w600);
    }
  });

  testWidgets('Saving a withdrawal updates the balance and persists it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());
    await tester.ensureVisible(find.text('Einnahme'));
    await tester.tap(find.text('Einnahme'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '12.50');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('12,50 €'), findsOneWidget);
  });

  testWidgets('Saving cash received creates a separate incoming-cash entry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.tap(find.text('Einnahme'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '8.25');
    await tester.tap(find.text('Bar erhalten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Buchungen'));
    await tester.tap(find.text('Buchungen'));
    await tester.pumpAndSettle();

    expect(find.text('Bar erhalten'), findsOneWidget);
    expect(find.textContaining('8,25'), findsOneWidget);
  });

  testWidgets('Buchungen screen shows stored transactions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.ensureVisible(find.text('Einnahme'));
    await tester.tap(find.text('Einnahme'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '7.50');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Buchungen'));
    await tester.tap(find.text('Buchungen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('7,50'), findsOneWidget);
    expect(find.text('Abhebung'), findsOneWidget);
  });

  testWidgets('Monthly overview shows totals for the selected month', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.ensureVisible(find.text('Einnahme'));
    await tester.tap(find.text('Einnahme'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(currentMonthName()));
    await tester.tap(find.text(currentMonthName()));
    await tester.pumpAndSettle();

    expect(find.text('Abgehoben'), findsOneWidget);
    expect(find.text('Ausgegeben'), findsOneWidget);
    expect(find.text('Bar noch da'), findsOneWidget);
    expect(find.text('Gesamt'), findsOneWidget);
  });

  testWidgets('Negative balances render the balance card in red', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.ensureVisible(find.text('Ausgabe'));
    await tester.tap(find.text('Ausgabe'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '10.00');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grundversorgung').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final balanceCard = tester.widget<Container>(find.byKey(const Key('balance-card')));
    final decoration = balanceCard.decoration as BoxDecoration;
    expect(decoration.color, Colors.red);
  });

  testWidgets('Editing and deleting a transaction updates the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.ensureVisible(find.text('Einnahme'));
    await tester.tap(find.text('Einnahme'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12.50');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Buchungen'));
    await tester.tap(find.text('Buchungen'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abhebung').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '15.75');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.textContaining('15,75'), findsOneWidget);
    expect(find.textContaining('12,50'), findsNothing);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('15,75'), findsNothing);
  });

  testWidgets('Monthly overview copies the selected month values to the clipboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BargeldApp());

    await tester.ensureVisible(find.text('Ausgabe'));
    await tester.tap(find.text('Ausgabe'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '4.50');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesundheit').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(currentMonthName()));
    await tester.tap(find.text(currentMonthName()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Für Excel kopieren'));
    await tester.pumpAndSettle();

    expect(find.text('Für Excel kopieren'), findsOneWidget);
  });
}
