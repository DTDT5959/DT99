import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/flower_count_repository.dart';
import '../counting/counting_screen.dart';

class HistoryScreen extends StatefulWidget {
  final String farmId;
  final String farmName;
  const HistoryScreen({super.key, required this.farmId, required this.farmName});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = FlowerCountRepository();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await _repo.getSessionsForFarm(widget.farmId);
    if (mounted) setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('History · ${widget.farmName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Text('No counting sessions yet', style: TextStyle(color: Colors.grey.shade600)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final session = _sessions[i];
                    final date = DateTime.parse(session['date'] as String);
                    final total = session['total'] as int? ?? 0;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        leading: const Icon(Icons.event_note),
                        title: Text(DateFormat.yMMMMd().format(date)),
                        subtitle: Text('$total Flowers'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CountingScreen(
                              farmId: widget.farmId,
                              farmName: widget.farmName,
                              date: date,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
