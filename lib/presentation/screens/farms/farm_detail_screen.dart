import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/farm.dart';
import '../../../data/repositories/farm_repository.dart';
import '../../../data/repositories/post_repository.dart';
import '../../providers/farm_provider.dart';
import '../../utils/export_helper.dart';
import '../../widgets/share_farm_sheet.dart';
import '../counting/date_select_screen.dart';
import '../counting/reset_counting_screen.dart';
import '../history/history_screen.dart';
import '../layout/layout_editor_screen.dart';
import '../statistics/statistics_screen.dart';

class FarmDetailScreen extends StatefulWidget {
  final String farmId;
  const FarmDetailScreen({super.key, required this.farmId});

  @override
  State<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends State<FarmDetailScreen> {
  final _repo = FarmRepository();
  Farm? _farm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final farm = await _repo.getFarm(widget.farmId);
    if (mounted) setState(() => _farm = farm);
  }

  @override
  Widget build(BuildContext context) {
    final farm = _farm;
    return Scaffold(
      appBar: AppBar(
        title: Text(farm?.name ?? 'Farm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename Farm',
            onPressed: farm == null ? null : () => _renameFarm(context, farm),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export today\'s counts',
            onPressed: farm == null ? null : () => _showExportOptions(context, farm),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: farm == null ? null : () => _confirmDelete(context, farm),
          ),
        ],
      ),
      body: farm == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${farm.totalPosts}', style: Theme.of(context).textTheme.headlineMedium),
                              const Text('Total posts'),
                            ],
                          ),
                        ),
                        if ((farm.description ?? '').isNotEmpty)
                          Expanded(
                            flex: 2,
                            child: Text(farm.description!, style: TextStyle(color: Colors.grey.shade600)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (farm.isImported) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('Imported'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _ActionTile(
                  icon: Icons.checklist,
                  title: 'Start Counting',
                  subtitle: 'Pick a date and count flowers post by post',
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DateSelectScreen(farmId: farm.id, farmName: farm.name)),
                  ),
                ),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.map_outlined,
                  title: 'Edit Layout',
                  subtitle: 'Add, move, or remove posts',
                  color: Colors.brown,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LayoutEditorScreen(farmId: farm.id, farmName: farm.name),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.history,
                  title: 'History',
                  subtitle: 'Browse past counting sessions',
                  color: Colors.blueGrey,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HistoryScreen(farmId: farm.id, farmName: farm.name)),
                  ),
                ),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.restart_alt,
                  title: 'Reset Counting',
                  subtitle: 'Remove counting records for a date range',
                  color: Colors.red,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ResetCountingScreen(farmId: farm.id, farmName: farm.name),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.bar_chart,
                  title: 'Statistics',
                  subtitle: 'Trends, averages, and top posts',
                  color: Colors.indigo,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => StatisticsScreen(farmId: farm.id, farmName: farm.name)),
                  ),
                ),
                const SizedBox(height: 12),
                _ActionTile(
                  icon: Icons.ios_share,
                  title: 'Share Farm',
                  subtitle: 'Send a complete, editable copy to someone else',
                  color: Colors.teal,
                  onTap: () => showShareFarmSheet(context, farmId: farm.id, farmName: farm.name),
                ),
              ],
            ),
    );
  }

  Future<void> _showExportOptions(BuildContext context, Farm farm) async {
    final posts = await PostRepository().getPostsForFarm(farm.id);
    if (posts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No posts to export yet')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final today = DateTime.now();
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export CSV'),
              subtitle: const Text("Today's counts"),
              onTap: () {
                Navigator.pop(ctx);
                ExportHelper.exportCsv(context, farm.id, posts, today);
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_on),
              title: const Text('Export Excel'),
              subtitle: const Text("Today's counts"),
              onTap: () {
                Navigator.pop(ctx);
                ExportHelper.exportExcel(context, farm.id, posts, today);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Export PDF Report'),
              subtitle: const Text("Today's counts"),
              onTap: () {
                Navigator.pop(ctx);
                ExportHelper.exportPdf(context, farm.name, farm.id, posts, today);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFarm(BuildContext context, Farm farm) async {
    final controller = TextEditingController(text: farm.name);
    final farmProvider = context.read<FarmProvider>();
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Farm'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Farm name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty) return;

    await farmProvider.renameFarm(farm.id, newName);
    // Refresh this screen's own copy — same id, same trees/boundary/
    // counting history, only the name changed.
    await _load();
  }

  void _confirmDelete(BuildContext context, Farm farm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete farm?'),
        content: Text('This permanently removes "${farm.name}" and all of its posts and history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await context.read<FarmProvider>().deleteFarm(farm.id);
              if (context.mounted) {
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(16)),
                alignment: Alignment.center,
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
