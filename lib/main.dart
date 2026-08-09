import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_io.dart';

const List<String> expenseCategories = [
  'Grundversorgung',
  'Gesundheit',
  'Kleidung / Schuhe',
  'Friseur',
  'Auto',
  'Fahrkarten',
  'Essen gehen',
  'Kultur',
  'Urlaub / Ausflüge',
  'Garten',
  'Handarbeiten',
  'Geschenke',
  'Spende',
  'Post',
  'Ämter',
  'Anschaffungen',
  'Yumi',
  'Sonstiges/Ungeklärt',
];

void main() {
  runApp(const BargeldApp());
}

class BargeldApp extends StatelessWidget {
  const BargeldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bargeld',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F8F3A),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<KaufTransaction> _transactions = [];
  final List<String> kategorien = expenseCategories;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('transactions') ?? <String>[];
    final transactions = raw
        .map((value) => KaufTransaction.fromJson(jsonDecode(value)))
        .toList();

    if (!mounted) return;
    setState(() {
      _transactions
        ..clear()
        ..addAll(transactions);
    });
  }

  Future<void> _saveTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = _transactions.map((tx) => jsonEncode(tx.toJson())).toList();
    await prefs.setStringList('transactions', payload);
  }

  Future<void> _persistTransactions(List<KaufTransaction> transactions) async {
    _transactions
      ..clear()
      ..addAll(transactions);
    await _saveTransactions();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _exportBackup() async {
    final backup = BargeldBackup(
      formatVersion: BargeldBackup.currentFormatVersion,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      transactions: [..._transactions],
    );

    final payload = jsonEncode(backup.toJson());
    final fileName = 'bargeld-backup-${DateTime.now().toLocal().toString().split(' ')[0]}.json';

    if (!mounted) return;

    final bytes = utf8.encode(payload);
    await downloadTextFile(bytes, fileName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup wurde erstellt.')),
      );
    }
  }

  Future<void> _restoreBackup() async {
    String? backupContent;
    try {
      backupContent = await pickTextFile();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup konnte nicht gelesen werden.')),
        );
      }
      return;
    }

    if (backupContent == null) {
      return;
    }

    try {
      BargeldBackup.fromJson(jsonDecode(backupContent));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Backup wiederherstellen?'),
          content: const Text(
            'Die vorhandenen Buchungen werden durch die Daten aus dem Backup ersetzt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Wiederherstellen'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) return;

    final restoredTransactions = BargeldBackupManager.restoreTransactions(
      currentTransactions: [..._transactions],
      backupContent: backupContent,
    );
    await _persistTransactions(restoredTransactions);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup wurde wiederhergestellt.')),
      );
    }
  }

  double get _bargeldbestand {
    return _transactions.fold<double>(0, (sum, tx) {
      if (tx.type == TransactionType.expense) {
        return sum - tx.amount;
      }
      return sum + tx.amount;
    });
  }

  Color get _balanceColor {
    return _bargeldbestand >= 0
        ? const Color(0xFF3E6A50)
      : Colors.red;
  }

  String euro(double wert) {
    return '${wert.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  String get _currentMonthName {
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

  String get _currentMonthYear {
    return '$_currentMonthName ${DateTime.now().year}';
  }

  Future<void> bargeldErhalten() async {
    final betragController = TextEditingController();
    final notizController = TextEditingController();
    DateTime datum = DateTime.now();
    TransactionType selectedType = TransactionType.withdrawal;

    final result = await showDialog<TransactionType>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Bargeld erhalten'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: betragController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Betrag in Euro',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(height: 8),
                    SegmentedButton<TransactionType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: TransactionType.withdrawal,
                          label: Text('Abhebung'),
                          icon: Icon(Icons.account_balance_wallet),
                        ),
                        ButtonSegment(
                          value: TransactionType.cashReceived,
                          label: Text('Bar erhalten'),
                          icon: Icon(Icons.add_circle_outline),
                        ),
                      ],
                      selected: {selectedType},
                      onSelectionChanged: (selection) {
                        setDialogState(() {
                          selectedType = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Datum'),
                      subtitle: Text(
                        '${datum.day.toString().padLeft(2, '0')}.'
                        '${datum.month.toString().padLeft(2, '0')}.'
                        '${datum.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final neuesDatum = await showDatePicker(
                          context: context,
                          initialDate: datum,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (neuesDatum != null) {
                          setDialogState(() {
                            datum = neuesDatum;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notizController,
                      decoration: const InputDecoration(
                        labelText: 'Notiz (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final text =
                        betragController.text.trim().replaceAll(',', '.');
                    final betrag = double.tryParse(text);

                    if (betrag == null || betrag <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bitte einen gültigen Betrag eingeben.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context, selectedType);
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final enteredAmount = double.tryParse(
        betragController.text.trim().replaceAll(',', '.'),
      );
      if (enteredAmount == null || enteredAmount <= 0) {
        return;
      }

      final transaction = KaufTransaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: result,
        amount: enteredAmount,
        date: datum,
        note: notizController.text.trim(),
        category: null,
        createdAt: DateTime.now(),
      );

      setState(() {
        _transactions.add(transaction);
      });
      await _saveTransactions();
    }
  }

  Future<void> _editTransaction(KaufTransaction transaction) async {
    final betragController = TextEditingController(
      text: transaction.amount.toString().replaceAll('.', ','),
    );
    final notizController = TextEditingController(text: transaction.note ?? '');
    DateTime datum = transaction.date;
    String? kategorie = transaction.category;
    TransactionType selectedType = transaction.type == TransactionType.expense
        ? TransactionType.withdrawal
        : transaction.type;
    final isExpense = transaction.type == TransactionType.expense;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Buchung bearbeiten'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: betragController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Betrag in Euro',
                      ),
                    ),
                    if (!isExpense) ...[
                      const SizedBox(height: 16),
                      SegmentedButton<TransactionType>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: TransactionType.withdrawal,
                            label: Text('Abhebung'),
                            icon: Icon(Icons.account_balance_wallet),
                          ),
                          ButtonSegment(
                            value: TransactionType.cashReceived,
                            label: Text('Bar erhalten'),
                            icon: Icon(Icons.add_circle_outline),
                          ),
                        ],
                        selected: {selectedType},
                        onSelectionChanged: (selection) {
                          setDialogState(() {
                            selectedType = selection.first;
                          });
                        },
                      ),
                    ],
                    if (isExpense) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: kategorie,
                        decoration: const InputDecoration(
                          labelText: 'Kategorie',
                        ),
                        isExpanded: true,
                        items: kategorien
                            .map(
                              (eintrag) => DropdownMenuItem(
                                value: eintrag,
                                child: Text(eintrag),
                              ),
                            )
                            .toList(),
                        onChanged: (wert) {
                          setDialogState(() {
                            kategorie = wert;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Datum'),
                      subtitle: Text(
                        '${datum.day.toString().padLeft(2, '0')}.'
                        '${datum.month.toString().padLeft(2, '0')}.'
                        '${datum.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final neuesDatum = await showDatePicker(
                          context: context,
                          initialDate: datum,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (neuesDatum != null) {
                          setDialogState(() {
                            datum = neuesDatum;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notizController,
                      decoration: const InputDecoration(
                        labelText: 'Notiz (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final text =
                        betragController.text.trim().replaceAll(',', '.');
                    final betrag = double.tryParse(text);

                    if (betrag == null || betrag <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bitte einen gültigen Betrag eingeben.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (isExpense && (kategorie == null || kategorie!.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bitte eine Kategorie auswählen.'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context, true);
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final enteredAmount = double.tryParse(
        betragController.text.trim().replaceAll(',', '.'),
      );
      if (enteredAmount == null || enteredAmount <= 0) {
        return;
      }

      final updatedTransaction = KaufTransaction(
        id: transaction.id,
        type: isExpense ? TransactionType.expense : selectedType,
        amount: enteredAmount,
        date: datum,
        note: notizController.text.trim(),
        category: isExpense ? kategorie : null,
        createdAt: transaction.createdAt,
      );

      setState(() {
        final index = _transactions.indexWhere((tx) => tx.id == transaction.id);
        if (index >= 0) {
          _transactions[index] = updatedTransaction;
        }
      });
      await _saveTransactions();
    }
  }

  Future<void> _deleteTransaction(KaufTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Buchung wirklich löschen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        _transactions.removeWhere((tx) => tx.id == transaction.id);
      });
      await _saveTransactions();
    }
  }

  Future<void> ausgabeErfassen() async {
    final betragController = TextEditingController();
    final notizController = TextEditingController();
    DateTime datum = DateTime.now();
    String? kategorie;

    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ausgabe erfassen'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: betragController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Betrag in Euro',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: kategorie,
                      decoration: const InputDecoration(
                        labelText: 'Kategorie',
                      ),
                      isExpanded: true,
                      items: kategorien
                          .map(
                            (eintrag) => DropdownMenuItem(
                              value: eintrag,
                              child: Text(eintrag),
                            ),
                          )
                          .toList(),
                      onChanged: (wert) {
                        setDialogState(() {
                          kategorie = wert;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Datum'),
                      subtitle: Text(
                        '${datum.day.toString().padLeft(2, '0')}.'
                        '${datum.month.toString().padLeft(2, '0')}.'
                        '${datum.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final neuesDatum = await showDatePicker(
                          context: context,
                          initialDate: datum,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (neuesDatum != null) {
                          setDialogState(() {
                            datum = neuesDatum;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notizController,
                      decoration: const InputDecoration(
                        labelText: 'Notiz (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: () {
                    final text =
                        betragController.text.trim().replaceAll(',', '.');
                    final betrag = double.tryParse(text);

                    if (betrag == null || betrag <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bitte einen gültigen Betrag eingeben.',
                          ),
                        ),
                      );
                      return;
                    }

                    if (kategorie == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bitte eine Kategorie auswählen.'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(context, betrag);

                    if (_bargeldbestand - betrag < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bargeldbestand ist jetzt negativ.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      final transaction = KaufTransaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        type: TransactionType.expense,
        amount: result,
        date: datum,
        note: notizController.text.trim(),
        category: kategorie,
        createdAt: DateTime.now(),
      );

      setState(() {
        _transactions.add(transaction);
      });
      await _saveTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F2EA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const topBottomPadding = 30.0;
                const headerHeight = 26.0;
                const headerToCardSpacing = 14.0;
                const cardToGridSpacing = 16.0;
                const interRowSpacing = 12.0;
                const balanceCardHeight = 170.0;

                final availableForGrid = constraints.maxHeight -
                    (topBottomPadding +
                        headerHeight +
                        headerToCardSpacing +
                        balanceCardHeight +
                        cardToGridSpacing +
                        interRowSpacing);
                final actionCardHeight =
                    ((availableForGrid / 2).clamp(96.0, 122.0) as num)
                        .toDouble();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          'BARGELD',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 3.2,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF243128),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildBalanceCard(),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: actionCardHeight,
                        child: Row(
                          children: [
                            Expanded(
                              child: _actionButton(
                                icon: Icons.remove_circle_outline_rounded,
                                label: 'Ausgabe',
                                onPressed: ausgabeErfassen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.add_circle_outline_rounded,
                                label: 'Einnahme',
                                onPressed: bargeldErhalten,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: actionCardHeight,
                        child: Row(
                          children: [
                            Expanded(
                              child: _actionButton(
                                icon: Icons.bar_chart_rounded,
                                label: _currentMonthName,
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MonthlyOverviewPage(
                                        transactions: _transactions,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _actionButton(
                                icon: Icons.receipt_long_rounded,
                                label: 'Buchungen',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TransactionsPage(
                                        transactions: _transactions,
                                        onEditTransaction: _editTransaction,
                                        onDeleteTransaction: _deleteTransaction,
                                        onBackupCreate: _exportBackup,
                                        onBackupRestore: _restoreBackup,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      key: const Key('balance-card'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 170),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _balanceColor,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: -8,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.2,
                child: Image.asset(
                  'assets/images/balance_branch.png',
                  width: 138,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aktueller Bargeldbestand',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.88),
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  euro(_bargeldbestand),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _currentMonthYear,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    const backgroundColor = Color(0xFFFCFAF6);
    const borderColor = Color(0xFFE1DDD3);
    final iconColor = const Color(0xFF3E6A50);
    const iconBackground = Color(0xFFE8EEE5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF243128),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.transactions,
    required this.onEditTransaction,
    required this.onDeleteTransaction,
    required this.onBackupCreate,
    required this.onBackupRestore,
  });

  final List<KaufTransaction> transactions;
  final Future<void> Function(KaufTransaction transaction) onEditTransaction;
  final Future<void> Function(KaufTransaction transaction) onDeleteTransaction;
  final Future<void> Function() onBackupCreate;
  final Future<void> Function() onBackupRestore;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late List<KaufTransaction> _transactions;

  @override
  void initState() {
    super.initState();
    _transactions = [...widget.transactions];
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transactions.length != oldWidget.transactions.length ||
        widget.transactions.any((tx) => !oldWidget.transactions.contains(tx))) {
      _transactions = [...widget.transactions];
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatAmount(KaufTransaction tx) {
    final amount = tx.amount.toStringAsFixed(2).replaceAll('.', ',');
    if (tx.type == TransactionType.expense) {
      return '- $amount €';
    }
    return '+ $amount €';
  }

  @override
  Widget build(BuildContext context) {
    final sortedTransactions = [..._transactions]
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buchungen'),
        backgroundColor: const Color(0xFFF6F2EA),
        foregroundColor: const Color(0xFF243128),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'backup_create') {
                await widget.onBackupCreate();
              } else if (value == 'backup_restore') {
                await widget.onBackupRestore();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'backup_create',
                child: Text('Backup erstellen'),
              ),
              const PopupMenuItem(
                value: 'backup_restore',
                child: Text('Backup wiederherstellen'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF6F2EA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: sortedTransactions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCFAF6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Noch keine Buchungen vorhanden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF243128),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: sortedTransactions.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final tx = sortedTransactions[index];
                      final title = tx.type == TransactionType.withdrawal
                          ? 'Abhebung'
                          : tx.type == TransactionType.cashReceived
                              ? 'Bar erhalten'
                              : 'Ausgabe';
                      final accentColor = tx.type == TransactionType.expense
                          ? const Color(0xFFB6534E)
                          : tx.type == TransactionType.cashReceived
                              ? const Color(0xFF3E6A50)
                              : const Color(0xFF243128);

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCFAF6),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              await widget.onEditTransaction(tx);
                              if (mounted) {
                                setState(() {
                                  _transactions = [...widget.transactions];
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(22),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF243128),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatAmount(tx),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: accentColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _formatDate(tx.date),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF243128).withOpacity(0.64),
                                          ),
                                        ),
                                        if (tx.category != null && tx.category!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Kategorie: ${tx.category}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: const Color(0xFF243128).withOpacity(0.72),
                                            ),
                                          ),
                                        ],
                                        if (tx.note != null && tx.note!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            tx.note!,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: const Color(0xFF243128).withOpacity(0.72),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: accentColor.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          tx.type == TransactionType.expense
                                              ? Icons.remove_circle_outline_rounded
                                              : tx.type == TransactionType.cashReceived
                                                  ? Icons.add_circle_outline_rounded
                                                  : Icons.account_balance_wallet_rounded,
                                          size: 19,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete, size: 20),
                                        color: const Color(0xFF243128).withOpacity(0.72),
                                        onPressed: () async {
                                          await widget.onDeleteTransaction(tx);
                                          if (mounted) {
                                            setState(() {
                                              _transactions = [...widget.transactions];
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class MonthlyOverviewPage extends StatefulWidget {
  const MonthlyOverviewPage({super.key, required this.transactions});

  final List<KaufTransaction> transactions;

  @override
  State<MonthlyOverviewPage> createState() => _MonthlyOverviewPageState();
}

class _MonthlyOverviewPageState extends State<MonthlyOverviewPage> {
  late DateTime _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  }

  String _monthLabel(DateTime month) {
    return '${_monthName(month.month)} ${month.year}';
  }

  String _monthName(int month) {
    const names = [
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
    return names[month - 1];
  }

  String _formatAmount(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  List<KaufTransaction> _transactionsForMonth() {
    return widget.transactions.where((tx) {
      return tx.date.year == _selectedMonth.year && tx.date.month == _selectedMonth.month;
    }).toList();
  }

  double _totalWithdrawals() {
    return _transactionsForMonth()
        .where((tx) => tx.type == TransactionType.withdrawal)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
  }

  double _totalCashReceived() {
    return _transactionsForMonth()
        .where((tx) => tx.type == TransactionType.cashReceived)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
  }

  double _totalExpenses() {
    return _transactionsForMonth()
        .where((tx) => tx.type == TransactionType.expense)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
  }

  double _balanceAtMonthEnd() {
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    return widget.transactions.fold<double>(0, (sum, tx) {
      if (tx.date.isAfter(monthEnd)) {
        return sum;
      }
      if (tx.type == TransactionType.expense) {
        return sum - tx.amount;
      }
      return sum + tx.amount;
    });
  }

  Map<String, double> _expensesByCategory() {
    final result = <String, double>{};
    for (final tx in _transactionsForMonth()) {
      if (tx.type == TransactionType.expense && tx.category != null && tx.category!.isNotEmpty) {
        result[tx.category!] = (result[tx.category!] ?? 0) + tx.amount;
      }
    }
    return result;
  }

  Future<void> _copyMonthlyValues() async {
    final buffer = StringBuffer();
    final expensesByCategory = _expensesByCategory();

    for (final category in expenseCategories) {
      final amount = expensesByCategory[category] ?? 0.0;
      if (amount <= 0) {
        buffer.writeln();
      } else {
        buffer.writeln(_formatClipboardAmount(amount));
      }
    }

    buffer.writeln(_formatClipboardAmount(_balanceAtMonthEnd()));

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Monatswerte für Excel kopiert.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatClipboardAmount(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final monthTransactions = _transactionsForMonth();
    final expensesByCategory = _expensesByCategory();
    final balanceColor = _balanceAtMonthEnd() >= 0
        ? const Color(0xFF3E6A50)
        : const Color(0xFFB6534E);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monatsübersicht'),
        backgroundColor: const Color(0xFFF6F2EA),
        foregroundColor: const Color(0xFF243128),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F2EA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFAF6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _monthButton(
                          icon: Icons.chevron_left,
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(
                                _selectedMonth.year,
                                _selectedMonth.month - 1,
                              );
                            });
                          },
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _monthLabel(_selectedMonth),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF243128),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Monatsübersicht',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF243128).withOpacity(0.64),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _monthButton(
                          icon: Icons.chevron_right,
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(
                                _selectedMonth.year,
                                _selectedMonth.month + 1,
                              );
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFAF6),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _summaryRow('Abgehoben', _totalWithdrawals()),
                        const SizedBox(height: 8),
                        _summaryRow('Sonstiges bar erhalten', _totalCashReceived()),
                        const SizedBox(height: 8),
                        _summaryRow('Ausgegeben', _totalExpenses()),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: balanceColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: balanceColor.withOpacity(0.2), width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Bar noch da',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF243128),
                                ),
                              ),
                              Text(
                                _formatAmount(_balanceAtMonthEnd()),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: balanceColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _copyMonthlyValues,
                      icon: const Icon(Icons.content_copy_rounded, size: 18),
                      label: const Text('Für Excel kopieren'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF243128),
                        backgroundColor: const Color(0xFFFCFAF6),
                        side: const BorderSide(color: Color(0xFFCAD9C8), width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: monthTransactions.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCFAF6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Keine Buchungen für diesen Monat.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF243128),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFCFAF6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ListView(
                              children: [
                                if (expensesByCategory.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Kategorien',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF243128).withOpacity(0.7),
                                      ),
                                    ),
                                  ),
                                  ...expensesByCategory.entries.map((entry) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9F5EE),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFE7E1D6),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry.key,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF243128),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _formatAmount(entry.value),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF243128),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9F5EE),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE7E1D6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Gesamt',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF243128),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatAmount(_totalExpenses()),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF243128),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCAD9C8), width: 1),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFF3E6A50)),
        splashRadius: 20,
      ),
    );
  }

  Widget _summaryRow(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E1D6), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF243128),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatAmount(value),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF243128),
            ),
          ),
        ],
      ),
    );
  }
}

class BargeldBackup {
  BargeldBackup({
    required this.formatVersion,
    required this.createdAt,
    required this.transactions,
  });

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final String createdAt;
  final List<KaufTransaction> transactions;

  factory BargeldBackup.fromJson(Map<String, dynamic> json) {
    if (json['formatVersion'] != currentFormatVersion) {
      throw const FormatException('Dieses Backup ist nicht kompatibel.');
    }

    if (json['createdAt'] is! String || json['transactions'] is! List) {
      throw const FormatException('Das Backup ist ungültig.');
    }

    final transactions = (json['transactions'] as List)
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Das Backup enthält ungültige Einträge.');
          }
          return KaufTransaction.fromJson(item);
        })
        .toList();

    return BargeldBackup(
      formatVersion: json['formatVersion'] as int,
      createdAt: json['createdAt'] as String,
      transactions: transactions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'formatVersion': formatVersion,
      'createdAt': createdAt,
      'transactions': transactions.map((tx) => tx.toJson()).toList(),
    };
  }
}

class BargeldBackupManager {
  static List<KaufTransaction> restoreTransactions({
    required List<KaufTransaction> currentTransactions,
    required String? backupContent,
  }) {
    if (backupContent == null) {
      return [...currentTransactions];
    }

    final decoded = jsonDecode(backupContent);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Das Backup ist ungültig.');
    }

    final backup = BargeldBackup.fromJson(decoded);
    return [...backup.transactions];
  }
}

class KaufTransaction {
  const KaufTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.note,
    required this.category,
    required this.createdAt,
  });

  final String id;
  final TransactionType type;
  final double amount;
  final DateTime date;
  final String? note;
  final String? category;
  final DateTime createdAt;

  factory KaufTransaction.fromJson(Map<String, dynamic> json) {
    return KaufTransaction(
      id: json['id'] as String,
      type: TransactionType.values.byName(json['type'] as String),
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      note: json['note'] as String?,
      category: json['category'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'amount': amount,
      'date': date.toIso8601String(),
      'note': note,
      'category': category,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

enum TransactionType { withdrawal, cashReceived, expense }
