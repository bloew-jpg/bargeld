import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  double get _bargeldbestand {
    return _transactions.fold<double>(0, (sum, tx) {
      if (tx.type == TransactionType.expense) {
        return sum - tx.amount;
      }
      return sum + tx.amount;
    });
  }

  Color get _balanceColor {
    return _bargeldbestand >= 0 ? const Color(0xFF3E6A50) : Colors.red;
  }

  String euro(double wert) {
    return '${wert.toStringAsFixed(2).replaceAll('.', ',')} €';
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'BARGELD',
                      style: TextStyle(
                        fontSize: 22,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF243128),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('balance-card'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 18,
                    ),
                    decoration: BoxDecoration(
                      color: _balanceColor,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aktueller Bargeldbestand',
                          style: TextStyle(
                            fontSize: 13,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          euro(_bargeldbestand),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          icon: Icons.remove_circle_outline_rounded,
                          label: 'Ausgabe erfassen',
                          onPressed: ausgabeErfassen,
                          isPrimary: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          icon: Icons.add_circle_outline_rounded,
                          label: 'Bargeld erhalten',
                          onPressed: bargeldErhalten,
                          isPrimary: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          icon: Icons.bar_chart_rounded,
                          label: 'Monatsübersicht',
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
                          isPrimary: false,
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
                                ),
                              ),
                            );
                          },
                          isPrimary: false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    final backgroundColor = isPrimary
        ? const Color(0xFFF9F5EE)
        : const Color(0xFFFCFAF6);
    final borderColor = isPrimary
        ? const Color(0xFFCAD9C8)
        : const Color(0xFFE7E1D6);
    final iconColor = const Color(0xFF3E6A50);
    final textColor = const Color(0xFF243128);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: isPrimary ? 82 : 68,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: isPrimary ? 13.5 : 12.5,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
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
  });

  final List<KaufTransaction> transactions;
  final Future<void> Function(KaufTransaction transaction) onEditTransaction;
  final Future<void> Function(KaufTransaction transaction) onDeleteTransaction;

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
        backgroundColor: const Color(0xFF35933E),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F7F3),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sortedTransactions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final tx = sortedTransactions[index];
                return Card(
                  child: InkWell(
                    onTap: () async {
                      await widget.onEditTransaction(tx);
                      if (mounted) {
                        setState(() {
                          _transactions = [...widget.transactions];
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  tx.type == TransactionType.withdrawal
                                      ? 'Abhebung'
                                      : tx.type == TransactionType.cashReceived
                                          ? 'Bar erhalten'
                                          : 'Ausgabe',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                _formatAmount(tx),
                                style: TextStyle(
                                  color: tx.type == TransactionType.expense
                                      ? Colors.red[700]
                                      : Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_formatDate(tx.date)),
                          if (tx.category != null && tx.category!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text('Kategorie: ${tx.category}'),
                          ],
                          if (tx.note != null && tx.note!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(tx.note!),
                          ],
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () async {
                                await widget.onDeleteTransaction(tx);
                                if (mounted) {
                                  setState(() {
                                    _transactions = [...widget.transactions];
                                  });
                                }
                              },
                            ),
                          ),
                        ],
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monatsübersicht'),
        backgroundColor: const Color(0xFF35933E),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF4F7F3),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedMonth = DateTime(
                              _selectedMonth.year,
                              _selectedMonth.month - 1,
                            );
                          });
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        _monthLabel(_selectedMonth),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedMonth = DateTime(
                              _selectedMonth.year,
                              _selectedMonth.month + 1,
                            );
                          });
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _summaryRow('Abgehoben', _totalWithdrawals()),
                          const SizedBox(height: 8),
                          _summaryRow('Sonstiges bar erhalten', _totalCashReceived()),
                          const SizedBox(height: 8),
                          _summaryRow('Ausgegeben', _totalExpenses()),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Bar noch da',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _formatAmount(_balanceAtMonthEnd()),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _copyMonthlyValues,
                    icon: const Icon(Icons.copy),
                    label: const Text('Für Excel kopieren'),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: monthTransactions.isEmpty
                        ? const Center(child: Text('Keine Buchungen für diesen Monat.'))
                        : ListView(
                            children: [
                              if (expensesByCategory.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Kategorien',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...expensesByCategory.entries.map((entry) {
                                  return Card(
                                    child: ListTile(
                                      title: Text(entry.key),
                                      trailing: Text(_formatAmount(entry.value)),
                                    ),
                                  );
                                }),
                              ],
                              const SizedBox(height: 12),
                              Card(
                                child: ListTile(
                                  title: const Text('Gesamt'),
                                  trailing: Text(_formatAmount(_totalExpenses())),
                                ),
                              ),
                            ],
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

  Widget _summaryRow(String label, double value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        Text(_formatAmount(value)),
      ],
    );
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
