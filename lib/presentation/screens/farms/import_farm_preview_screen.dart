import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/farm_import_service.dart';
import '../../providers/farm_provider.dart';
import 'farm_detail_screen.dart';

/// "Import Farm" step 2 (spec §9-10): reads and validates the picked
/// .salsfarm file, shows the farmer exactly what they're about to bring
/// in — real, calculated numbers, never hard-coded — and only writes
/// anything to the database once they explicitly tap "Save Farm".
/// Tapping "Cancel" (or just leaving) never touches the database at all.
class ImportFarmPreviewScreen extends StatefulWidget {
  final File file;
  const ImportFarmPreviewScreen({super.key, required this.file});

  @override
  State<ImportFarmPreviewScreen> createState() => _ImportFarmPreviewScreenState();
}

class _ImportFarmPreviewScreenState extends State<ImportFarmPreviewScreen> {
  final _importService = FarmImportService();
  ParsedFarmImport? _parsed;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final parsed = await _importService.readPackage(widget.file);
      if (mounted) setState(() => _parsed = parsed);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _saveFarm() async {
    final parsed = _parsed;
    if (parsed == null || _saving) return;
    setState(() => _saving = true);
    try {
      final newFarmId = await _importService.saveFarm(parsed);
      if (!mounted) return;
      await context.read<FarmProvider>().loadFarms();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FarmDetailScreen(farmId: newFarmId)),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import this farm: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Farm')),
      body: _error != null
          ? _ErrorState(message: _error!)
          : _parsed == null
              ? const Center(child: CircularProgressIndicator())
              : _PreviewBody(preview: _parsed!.preview),
      bottomNavigationBar: (_error == null && _parsed != null)
          ? SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _saveFarm,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Farm'),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _PreviewBody extends StatelessWidget {
  final FarmImportPreview preview;
  const _PreviewBody({required this.preview});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.park, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(preview.farmName, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                _StatRow(icon: Icons.park_outlined, label: 'Trees', value: '${preview.treeCount}'),
                const Divider(height: 1),
                _StatRow(
                  icon: Icons.event_outlined,
                  label: 'Counting Dates',
                  value: '${preview.countingDateCount}',
                ),
                const Divider(height: 1),
                _StatRow(
                  icon: Icons.local_florist_outlined,
                  label: 'Flower Records',
                  value: '${preview.flowerRecordCount}',
                ),
                const Divider(height: 1),
                _StatRow(
                  icon: Icons.hexagon_outlined,
                  label: 'Boundary',
                  value: preview.hasBoundary ? 'Custom field boundary' : 'None',
                ),
                if (preview.photoCount > 0) ...[
                  const Divider(height: 1),
                  _StatRow(icon: Icons.photo_outlined, label: 'Photos', value: '${preview.photoCount}'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'This becomes a new, independent farm in your app. It will not stay '
          'connected to the sender — editing it here never changes their copy.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
