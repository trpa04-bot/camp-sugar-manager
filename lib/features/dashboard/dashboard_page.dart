import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'services/dashboard_stats_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.onNewReservation,
    required this.onOpenDebtReservations,
  });

  final VoidCallback onNewReservation;
  final VoidCallback onOpenDebtReservations;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final dateLabel =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final statsService = DashboardStatsService();
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReceptionHero(
          dateLabel: dateLabel,
          onNewReservation: onNewReservation,
        ),
        const SizedBox(height: 18),
        Text('Operativni pregled', style: textTheme.titleLarge),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 900 ? 4 : 2;

            return StreamBuilder<DashboardStats>(
              stream: statsService.watchStats(currentUserUid: currentUserUid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _DashboardStatusCard(
                    title: 'Greška pri učitavanju',
                    message:
                        'Nije moguće dohvatiti dashboard statistiku.\n${snapshot.error}',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final stats = snapshot.data ?? DashboardStats.empty;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.55,
                      children: [
                        _StatCard(
                          title: 'Dolasci danas',
                          value: stats.arrivalsToday.toString(),
                          icon: Icons.login_rounded,
                        ),
                        _StatCard(
                          title: 'Odlasci danas',
                          value: stats.departuresToday.toString(),
                          icon: Icons.logout_rounded,
                        ),
                        _StatCard(
                          title: 'Slobodne parcele',
                          value: stats.availablePitches.toString(),
                          helper: 'Zauzete: ${stats.occupiedLabel}',
                          icon: Icons.cottage_outlined,
                        ),
                        _StatCard(
                          title: 'Otvorena dugovanja',
                          value:
                              '${stats.openDebtAmount.toStringAsFixed(2)} EUR',
                          helper: '${stats.openDebtReservations} rezervacija',
                          icon: Icons.warning_amber_rounded,
                          onTap: onOpenDebtReservations,
                        ),
                        _StatCard(
                          title: 'Trenutno gostiju',
                          value: stats.currentGuests.toString(),
                          icon: Icons.groups_2_outlined,
                        ),
                        _StatCard(
                          title: 'Ukupno kroz kamp',
                          value: stats.totalGuestsThroughCamp.toString(),
                          icon: Icons.insights_outlined,
                        ),
                        _StatCard(
                          title: 'Moje odjave danas',
                          value: stats.myCheckedOutPitchesToday.toString(),
                          icon: Icons.person_pin_circle_outlined,
                        ),
                        _StatCard(
                          title: 'Neodjavljeni odlasci',
                          value: stats.overdueCheckedOutPending.toString(),
                          icon: Icons.report_gmailerrorred_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ShiftChecklistCard(
                      stats: stats,
                      onOpenDebtReservations: onOpenDebtReservations,
                    ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onNewReservation,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Nova rezervacija'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Današnje aktivnosti',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _ActivityTile(
                  title: 'Nema novih aktivnosti',
                  subtitle: 'Sve je ažurirano za danas.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceptionHero extends StatelessWidget {
  const _ReceptionHero({
    required this.dateLabel,
    required this.onNewReservation,
  });

  final String dateLabel;
  final VoidCallback onNewReservation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F7A6B), Color(0xFF2FA58C)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.space_dashboard_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Reception Dashboard',
                style: textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  dateLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Sve ključno za smjenu na jednom mjestu: dolasci, odlasci, parcele i dugovanja.',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: colorScheme.primary,
            ),
            onPressed: onNewReservation,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Nova rezervacija'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.helper,
    this.icon,
    this.onTap,
  });

  final String title;
  final String value;
  final String? helper;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null)
                    Icon(icon, size: 18, color: colorScheme.primary),
                  if (icon != null) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              if ((helper ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  helper!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(radius: 18, child: Icon(Icons.today_rounded)),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _ShiftChecklistCard extends StatelessWidget {
  const _ShiftChecklistCard({
    required this.stats,
    required this.onOpenDebtReservations,
  });

  final DashboardStats stats;
  final VoidCallback onOpenDebtReservations;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded),
                const SizedBox(width: 8),
                Text(
                  'Checklist smjene',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ChecklistRow(
              label: 'Dolasci danas',
              value: stats.arrivalsToday,
              isWarning: false,
            ),
            _ChecklistRow(
              label: 'Odlasci danas',
              value: stats.departuresToday,
              isWarning: false,
            ),
            _ChecklistRow(
              label: 'Neodjavljeni odlasci',
              value: stats.overdueCheckedOutPending,
              isWarning: true,
            ),
            _ChecklistRow(
              label: 'Otvorena dugovanja',
              value: stats.openDebtReservations,
              isWarning: stats.openDebtReservations > 0,
            ),
            if (stats.openDebtReservations > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onOpenDebtReservations,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Otvori dugovanja'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.label,
    required this.value,
    required this.isWarning,
  });

  final String label;
  final int value;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning && value > 0 ? Colors.red.shade700 : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isWarning && value > 0)
                  ? Colors.red.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              value.toString(),
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatusCard extends StatelessWidget {
  const _DashboardStatusCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
