import 'package:flutter/material.dart';

import 'services/dashboard_stats_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onNewReservation});

  final VoidCallback onNewReservation;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final statsService = DashboardStatsService();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Camp Sugar Manager',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 900 ? 4 : 2;

            return StreamBuilder<DashboardStats>(
              stream: statsService.watchStats(),
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

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _StatCard(
                      title: 'Trenutno gostiju',
                      value: stats.currentGuests.toString(),
                    ),
                    _StatCard(
                      title: 'Zauzete parcele',
                      value: stats.occupiedLabel,
                    ),
                    _StatCard(
                      title: 'Dolasci danas',
                      value: stats.arrivalsToday.toString(),
                    ),
                    _StatCard(
                      title: 'Odlasci danas',
                      value: stats.departuresToday.toString(),
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

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ],
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
