import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/payment.dart';
import '../services/payment_service.dart';
import '../../reservations/services/reservation_service.dart';
import 'payment_editor_dialog.dart';

enum _Period { today, week, month, year }

extension _PeriodLabel on _Period {
  String get label {
    switch (this) {
      case _Period.today:
        return 'Dan';
      case _Period.week:
        return 'Tjedan';
      case _Period.month:
        return 'Mjesec';
      case _Period.year:
        return 'Godina';
    }
  }

  bool includes(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    switch (this) {
      case _Period.today:
        return d == today;
      case _Period.week:
        return d.isAfter(today.subtract(const Duration(days: 6))) || d == today;
      case _Period.month:
        return dt.year == now.year && dt.month == now.month;
      case _Period.year:
        return dt.year == now.year;
    }
  }
}

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  late final PaymentService _paymentService;
  late final ReservationService _reservationService;
  PaymentMethod? _selectedMethod;
  String _searchGuest = '';
  _Period _period = _Period.month;
  bool _didRunBackfill = false;

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService(FirebaseFirestore.instance);
    _reservationService = ReservationService(
      firestore: FirebaseFirestore.instance,
    );
    _runBackfillIfNeeded();
  }

  Future<void> _runBackfillIfNeeded() async {
    if (_didRunBackfill) {
      return;
    }
    _didRunBackfill = true;
    try {
      await _paymentService.backfillMissingPaymentsFromReservations();
    } catch (_) {
      // Do not block UI if backfill cannot run.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Povijest plaćanja'), elevation: 0),
      body: StreamBuilder<List<Payment>>(
        stream: _paymentService.watchPayments(),
        builder: (context, snapshot) {
          final allPayments = snapshot.data ?? const [];
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData;

          return Column(
            children: [
              // ── SAŽETAK PROMET ─────────────────────────────────────
              _SummaryCard(
                payments: allPayments,
                period: _period,
                isLoading: isLoading,
                onPeriodChanged: (p) => setState(() => _period = p),
              ),
              const Divider(height: 1),
              // ── FILTERI ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchGuest = value),
                        decoration: InputDecoration(
                          hintText: 'Pretraži gosta...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PopupMenuButton<PaymentMethod?>(
                      onSelected: (method) =>
                          setState(() => _selectedMethod = method),
                      initialValue: _selectedMethod,
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: null,
                          child: Text('Sve metode'),
                        ),
                        ...PaymentMethod.values.map(
                          (method) => PopupMenuItem(
                            value: method,
                            child: Text(
                              '${method.icon} ${method.displayLabel}',
                            ),
                          ),
                        ),
                      ],
                      child: Chip(
                        label: Text(
                          _selectedMethod == null
                              ? 'Sve metode'
                              : '${_selectedMethod!.icon} ${_selectedMethod!.displayLabel}',
                        ),
                        onDeleted: _selectedMethod == null
                            ? null
                            : () => setState(() => _selectedMethod = null),
                      ),
                    ),
                  ],
                ),
              ),
              // ── TABLICA DETALJA ──────────────────────────────────────
              Expanded(
                child: _buildDetailTable(context, allPayments, isLoading),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPaymentEditor(context, null),
        tooltip: 'Dodaj plaćanje',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDetailTable(
    BuildContext context,
    List<Payment> allPayments,
    bool isLoading,
  ) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allPayments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Nema plaćanja', style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );
    }

    final filtered = allPayments.where((p) {
      final matchesGuest =
          _searchGuest.isEmpty ||
          p.guestName.toLowerCase().contains(_searchGuest.toLowerCase());
      final matchesMethod =
          _selectedMethod == null || p.method == _selectedMethod;
      return matchesGuest && matchesMethod;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Nema plaćanja koja odgovaraju kriterijima',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith(
            (_) => Theme.of(context).colorScheme.primaryContainer,
          ),
          columns: const [
            DataColumn(label: Text('Gost')),
            DataColumn(label: Text('Iznos')),
            DataColumn(label: Text('Metoda')),
            DataColumn(label: Text('Datum')),
            DataColumn(label: Text('Napomena')),
            DataColumn(label: Text('Akcije')),
          ],
          rows: filtered.asMap().entries.map((entry) {
            final payment = entry.value;
            final index = entry.key;
            return DataRow(
              color: WidgetStateColor.resolveWith(
                (_) => index.isEven ? Colors.transparent : Colors.grey[50]!,
              ),
              cells: [
                DataCell(Text(payment.guestName)),
                DataCell(
                  Text(
                    '${payment.amount.toStringAsFixed(2)} €',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(
                  Text('${payment.method.icon} ${payment.method.displayLabel}'),
                ),
                DataCell(
                  Text(
                    '${payment.createdAt.day.toString().padLeft(2, '0')}.${payment.createdAt.month.toString().padLeft(2, '0')}.${payment.createdAt.year}',
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 160,
                    child: Text(
                      payment.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Uredi',
                        onPressed: () => _showPaymentEditor(context, payment),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Obriši',
                        onPressed: () =>
                            _showDeleteConfirmation(context, payment),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPaymentEditor(BuildContext context, Payment? payment) async {
    await showDialog<void>(
      context: context,
      builder: (_) => PaymentEditorDialog(
        payment: payment,
        paymentService: _paymentService,
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Payment payment) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Obriši plaćanje'),
        content: Text(
          'Želiš li obrisati plaćanje od ${payment.amount.toStringAsFixed(2)} € od ${payment.guestName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Otkaži'),
          ),
          FilledButton(
            onPressed: () async {
              await _paymentService.deletePayment(payment.id);

              var reservationId = payment.reservationId.trim();
              if (reservationId.isEmpty) {
                final matchedReservation = await _reservationService
                    .getReservationByGuestName(payment.guestName);
                reservationId = matchedReservation?.id ?? '';
              }
              if (reservationId.isNotEmpty) {
                await _reservationService
                    .reconcileReservationPaymentFromPayments(
                      reservationId: reservationId,
                      fallbackGuestName: payment.guestName,
                    );
              }

              if (context.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Plaćanje je obrisano')),
                );
              }
            },
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
  }
}

// ── WIDGET ZA SAŽETAK PROMET ────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.payments,
    required this.period,
    required this.isLoading,
    required this.onPeriodChanged,
  });

  final List<Payment> payments;
  final _Period period;
  final bool isLoading;
  final ValueChanged<_Period> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = payments
        .where((p) => period.includes(p.createdAt))
        .toList();

    // Grupiraj po metodi
    final Map<PaymentMethod, _MethodStats> stats = {
      for (final m in PaymentMethod.values) m: _MethodStats(method: m),
    };
    double grandTotal = 0;
    int grandCount = 0;
    for (final p in filtered) {
      stats[p.method]!.add(p.amount);
      grandTotal += p.amount;
      grandCount++;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Promet po načinu plaćanja',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Period selector
              SegmentedButton<_Period>(
                segments: _Period.values
                    .map(
                      (p) => ButtonSegment<_Period>(
                        value: p,
                        label: Text(p.label),
                      ),
                    )
                    .toList(),
                selected: {period},
                onSelectionChanged: (s) => onPeriodChanged(s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            )
          else
            _buildSummaryTable(context, stats, grandTotal, grandCount),
        ],
      ),
    );
  }

  Widget _buildSummaryTable(
    BuildContext context,
    Map<PaymentMethod, _MethodStats> stats,
    double grandTotal,
    int grandCount,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Sortiraj po iznosu silazno
    final sorted = stats.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          // Zaglavlje
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                _HeaderCell('Metoda plaćanja', flex: 3),
                _HeaderCell('Transakcija', flex: 2, align: TextAlign.center),
                _HeaderCell('Ukupno (€)', flex: 2, align: TextAlign.right),
                _HeaderCell('Udio', flex: 2, align: TextAlign.right),
              ],
            ),
          ),
          // Redovi po metodi
          ...sorted.map(
            (s) => _SummaryRow(
              method: s.method,
              count: s.count,
              total: s.total,
              grandTotal: grandTotal,
            ),
          ),
          // Ukupno red
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'UKUPNO',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$grandCount',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${grandTotal.toStringAsFixed(2)} €',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const Expanded(
                  flex: 2,
                  child: Text(
                    '100%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodStats {
  _MethodStats({required this.method});

  final PaymentMethod method;
  int count = 0;
  double total = 0;

  void add(double amount) {
    count++;
    total += amount;
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.flex = 1, this.align = TextAlign.left});

  final String text;
  final int flex;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          text,
          textAlign: align,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.method,
    required this.count,
    required this.total,
    required this.grandTotal,
  });

  final PaymentMethod method;
  final int count;
  final double total;
  final double grandTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = grandTotal > 0 ? (total / grandTotal * 100) : 0.0;
    final isEmpty = count == 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(method.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  method.displayLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isEmpty ? theme.colorScheme.outline : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isEmpty ? '—' : '$count',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isEmpty ? theme.colorScheme.outline : null,
                fontWeight: isEmpty ? null : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              isEmpty ? '—' : '${total.toStringAsFixed(2)} €',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isEmpty
                    ? theme.colorScheme.outline
                    : theme.colorScheme.primary,
                fontWeight: isEmpty ? null : FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: isEmpty
                ? Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: theme.colorScheme.outline),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      LinearProgressIndicator(
                        value: pct / 100,
                        backgroundColor: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.3),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
