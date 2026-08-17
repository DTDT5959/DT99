import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/services/farm_export_service.dart';

/// "Share Farm" (spec §1, §6): builds the .salsfarm package for [farmId]
/// off the main thread's synchronous path (the export itself is async, so
/// the UI never freezes even for a large farm — spec §6, §25), shows a
/// real calculated summary, then hands the file to the platform share
/// sheet via share_plus. Purely UI orchestration — all the actual export
/// logic lives in FarmExportService.
Future<void> showShareFarmSheet(BuildContext context, {required String farmId, required String farmName}) {
  return showModalBottomSheet(
    context: context,
    isDismissible: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _ShareFarmSheet(farmId: farmId, farmName: farmName),
  );
}

class _ShareFarmSheet extends StatefulWidget {
  final String farmId;
  final String farmName;
  const _ShareFarmSheet({required this.farmId, required this.farmName});

  @override
  State<_ShareFarmSheet> createState() => _ShareFarmSheetState();
}

class _ShareFarmSheetState extends State<_ShareFarmSheet> {
  final _exportService = FarmExportService();
  FarmExportResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final result = await _exportService.exportFarm(widget.farmId);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not prepare this farm for sharing: $e');
    }
  }

  Future<void> _share() async {
    final result = _result;
    if (result == null) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(result.file.path)], text: 'DragonTrack farm: ${widget.farmName}'),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.ios_share, size: 22),
                const SizedBox(width: 10),
                Text('Share Farm', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
            ] else if (_result == null) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Center(child: Text('Preparing farm data...')),
            ] else ...[
              Text(widget.farmName, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _SummaryRow(label: 'Trees', value: '${_result!.summary.treeCount}'),
              _SummaryRow(label: 'Counting Dates', value: '${_result!.summary.countingDateCount}'),
              _SummaryRow(label: 'Flower Records', value: '${_result!.summary.flowerRecordCount}'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
