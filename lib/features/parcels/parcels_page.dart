import 'package:flutter/material.dart';

import 'models/pitch.dart';
import 'services/pitch_service.dart';
import 'widgets/pitch_form_dialog.dart';

class ParcelsPage extends StatefulWidget {
  const ParcelsPage({super.key});

  @override
  State<ParcelsPage> createState() => _ParcelsPageState();
}

class _ParcelsPageState extends State<ParcelsPage> {
  final PitchService _service = PitchService();

  String _query = '';
  PitchStatus? _selectedStatus;

  Future<void> _openEditor({Pitch? pitch}) async {
    await showPitchEditor(
      context,
      pitch: pitch,
      onSave: (draft) async {
        if (draft.id.isEmpty) {
          await _service.createPitch(draft);
          return;
        }

        await _service.updatePitch(draft);
      },
    );
  }

  Future<void> _confirmDelete(Pitch pitch) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Obriši parcelu?'),
          content: Text(
            'Želiš li stvarno obrisati ${pitch.name} (${pitch.number})?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Obriši'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _service.deletePitch(pitch.id);
    }
  }

  Future<void> _seedPitches() async {
    await _service.seedDefaultPitches();
  }

  List<Pitch> _filterPitches(List<Pitch> pitches) {
    final query = _query.trim().toLowerCase();
    return pitches.where((pitch) {
      final matchesQuery =
          query.isEmpty ||
          pitch.name.toLowerCase().contains(query) ||
          pitch.number.toString().contains(query) ||
          pitch.zone.toLowerCase().contains(query);
      final matchesStatus =
          _selectedStatus == null || pitch.status == _selectedStatus;
      return matchesQuery && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parcele')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj parcelu'),
      ),
      body: StreamBuilder<List<Pitch>>(
        stream: _service.watchPitches(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline,
              title: 'Greška pri učitavanju',
              message: 'Nije moguće dohvatiti parcele iz Firestorea.',
              actionLabel: 'Pokušaj ponovno',
              onAction: () async {
                setState(() {});
              },
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allPitches = snapshot.data ?? const <Pitch>[];
          final filteredPitches = _filterPitches(allPitches);
          final availableCount = allPitches
              .where((pitch) => pitch.status == PitchStatus.available)
              .length;
          final occupiedCount = allPitches
              .where(
                (pitch) =>
                    pitch.status == PitchStatus.occupied &&
                    (pitch.currentReservationId ?? '').trim().isNotEmpty,
              )
              .length;
          final isEmptyCollection = allPitches.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Parcele',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth >= 1100 ? 4 : 2;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.8,
                    children: [
                      _SummaryCard(
                        title: 'Ukupno parcela',
                        value: allPitches.length.toString(),
                        icon: Icons.grid_view_rounded,
                      ),
                      _SummaryCard(
                        title: 'Slobodne parcele',
                        value: availableCount.toString(),
                        icon: Icons.check_circle_outline,
                      ),
                      _SummaryCard(
                        title: 'Zauzete parcele',
                        value: occupiedCount.toString(),
                        icon: Icons.block_rounded,
                      ),
                      _SummaryCard(
                        title: 'Aktivni filter',
                        value: _selectedStatus?.displayLabel ?? 'Svi',
                        icon: Icons.filter_alt_outlined,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (isEmptyCollection) ...[
                FilledButton.icon(
                  onPressed: _seedPitches,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Kreiraj početnih 45 parcela'),
                ),
                const SizedBox(height: 16),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final searchField = TextField(
                    decoration: const InputDecoration(
                      labelText: 'Tražilica',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  );

                  final filterField = DropdownButtonFormField<PitchStatus?>(
                    initialValue: _selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.tune),
                    ),
                    items: [
                      const DropdownMenuItem<PitchStatus?>(
                        value: null,
                        child: Text('Svi statusi'),
                      ),
                      ...PitchStatus.values.map(
                        (status) => DropdownMenuItem<PitchStatus?>(
                          value: status,
                          child: Text(status.displayLabel),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value;
                      });
                    },
                  );

                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 12),
                        SizedBox(width: 260, child: filterField),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      filterField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              if (filteredPitches.isEmpty)
                _StateMessage(
                  icon: Icons.inbox_outlined,
                  title: isEmptyCollection ? 'Nema parcela' : 'Nema rezultata',
                  message: isEmptyCollection
                      ? 'Kolekcija pitches je prazna. Možeš kreirati početnih 45 parcela.'
                      : 'Pokušaj promijeniti filter ili tražilicu.',
                  actionLabel: isEmptyCollection
                      ? 'Kreiraj početnih 45 parcela'
                      : null,
                  onAction: isEmptyCollection ? _seedPitches : null,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 1100 ? 4 : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredPitches.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 230,
                      ),
                      itemBuilder: (context, index) {
                        final pitch = filteredPitches[index];
                        return _PitchCard(
                          pitch: pitch,
                          onEdit: () => _openEditor(pitch: pitch),
                          onDelete: () => _confirmDelete(pitch),
                        );
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  const _PitchCard({
    required this.pitch,
    required this.onEdit,
    required this.onDelete,
  });

  final Pitch pitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}.';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = pitch.status.color;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    pitch.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: onEdit,
                      tooltip: 'Uredi parcelu',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      tooltip: 'Obriši parcelu',
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              'Broj ${pitch.number}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              pitch.zone,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _StatusChip(label: pitch.status.displayLabel, color: statusColor),
            const SizedBox(height: 8),
            if (pitch.status == PitchStatus.occupied) ...[
              Text(
                pitch.currentPrimaryGuestName?.trim().isNotEmpty == true
                    ? pitch.currentPrimaryGuestName!
                    : 'Glavni gost nije poznat',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('Broj gostiju: ${pitch.currentGuestCount}'),
              Text('Odlazak: ${_formatDate(pitch.occupiedUntil)}'),
            ],
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.groups_2_outlined, size: 18),
                const SizedBox(width: 6),
                Text('${pitch.maxGuests} gostiju'),
                const Spacer(),
                Icon(
                  pitch.hasElectricity
                      ? Icons.electric_bolt_rounded
                      : Icons.electric_bolt_outlined,
                  size: 18,
                  color: pitch.hasElectricity
                      ? Colors.amber.shade700
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Icon(
                  pitch.hasWater
                      ? Icons.water_drop_rounded
                      : Icons.water_drop_outlined,
                  size: 18,
                  color: pitch.hasWater
                      ? Colors.lightBlue
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Uredi'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Obriši'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await onAction!.call();
                    },
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
