import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_parser.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_import_review_sheet.dart';

class ReservationImportSheet extends StatefulWidget {
  final Function(ReservationImportResult result, List<String>? pitchIds) onSave;

  const ReservationImportSheet({required this.onSave, super.key});

  @override
  State<ReservationImportSheet> createState() => _ReservationImportSheetState();
}

class _ReservationImportSheetState extends State<ReservationImportSheet> {
  final _textController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zalijepite tekst rezervacije')),
      );
      return;
    }

    await _processImport(text);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (!mounted) return;
    if (image == null) return;

    setState(() => _isProcessing = true);

    try {
      // TODO: Implement OCR
      // For now, show a placeholder
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OCR još nije dostupan')));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _pickPDF() async {
    // TODO: Implement PDF picker
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF import još nije dostupan')),
    );
  }

  Future<void> _processImport(String text) async {
    setState(() => _isProcessing = true);

    try {
      final result = await ReservationImportParser.parseText(text);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReservationImportReviewSheet(
              result: result,
              onSave: widget.onSave,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Greška pri parsiranju: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Uvezi rezervaciju', style: textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(
              'Odaberite način unosa podataka',
              style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildOptionCard(
              icon: Icons.text_fields,
              title: 'Zalijepi tekst',
              description: 'Zalijepi tekst iz emaila ili poruke',
              onTap: () => _showTextInput(context),
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              icon: Icons.image,
              title: 'Dodaj screenshot',
              description: 'Fotografiraj ili učitaj screenshot',
              onTap: _pickImage,
              enabled: !_isProcessing,
            ),
            const SizedBox(height: 12),
            _buildOptionCard(
              icon: Icons.picture_as_pdf,
              title: 'Dodaj PDF',
              description: 'Učitaj potvrdu u PDF formatu',
              onTap: _pickPDF,
              enabled: !_isProcessing,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isProcessing
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Odustani'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTextInput(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zalijepi tekst'),
        content: TextField(
          controller: _textController,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Zalijepi tekst rezervacije...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _pasteText();
            },
            child: const Text('Prosljeđi'),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Colors.grey[600]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (_isProcessing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.arrow_forward, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
