import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/flower_count_repository.dart';

/// "Reset Counting" (farm settings menu): removes flower counting records
/// within a farmer-chosen inclusive date range. Never touches the farm
/// itself, its trees, boundary, layout, or photos — and never touches
/// records outside the chosen range. A tree that had a record inside the
/// range (including a genuine 0) goes back to "not counted" for that date,
/// because the underlying row is deleted rather than zeroed.
class ResetCountingScreen extends StatefulWidget {
  final String farmId;
  final String farmName;
  const ResetCountingScreen({super.key, required this.farmId, required this.farmName});

  @override
  State<ResetCountingScreen> createState() => _ResetCountingScreenState();
}

class _ResetCountingScreenState extends State<ResetCountingScreen> {
  final _countRepo = FlowerCountRepository();

  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  bool _working = false;

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _to = picked);
  }

  Future<void> _confirmAndReset() async {
    setState(() => _working = true);
    final preview = await _countRepo.getResetPreview(widget.farmId, from: _from, to: _to);
    if (!mounted) return;
    setState(() => _working = false);

    if (preview.recordCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No counting records found in that range')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Counting?'),
        content: Text(
          'This will remove flower counting records from:\n\n'
          '${DateFormat.yMMMMd().format(_from)}\n'
          'through\n'
          '${DateFormat.yMMMMd().format(_to)}\n\n'
          'Affected counting dates: ${preview.dateCount}\n'
          'Affected flower records: ${preview.recordCount}\n\n'
          'Your farm layout, trees, boundary and other farm information '
          'will NOT be deleted.\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Counting'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = true);
    await _countRepo.resetRange(farmId: widget.farmId, from: _from, to: _to);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset ${preview.recordCount} counting record(s)')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reset Counting · ${widget.farmName}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose the date range to reset. All flower counting records '
              'in this inclusive range will be permanently removed.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Text('From', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: InkWell(
                onTap: _pickFrom,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat.yMMMMd().format(_from),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('To', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: InkWell(
                onTap: _pickTo,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat.yMMMMd().format(_to),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _working ? null : _confirmAndReset,
              child: _working
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Reset Counting'),
            ),
          ],
        ),
      ),
    );
  }
}
