import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../../core/constants/app_branding.dart';
import '../../utils/backup_helper.dart';
import '../../widgets/app_signature.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Stack(
        children: [
          ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Appearance'),
          Card(
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Light Mode'),
                  value: ThemeMode.light,
                  groupValue: settings.themeMode,
                  onChanged: (m) => context.read<SettingsProvider>().setThemeMode(m!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark Mode'),
                  value: ThemeMode.dark,
                  groupValue: settings.themeMode,
                  onChanged: (m) => context.read<SettingsProvider>().setThemeMode(m!),
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Match System'),
                  value: ThemeMode.system,
                  groupValue: settings.themeMode,
                  onChanged: (m) => context.read<SettingsProvider>().setThemeMode(m!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Units'),
          Card(
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Metric'),
                  value: 'metric',
                  groupValue: settings.units,
                  onChanged: (u) => context.read<SettingsProvider>().setUnits(u!),
                ),
                RadioListTile<String>(
                  title: const Text('Imperial'),
                  value: 'imperial',
                  groupValue: settings.units,
                  onChanged: (u) => context.read<SettingsProvider>().setUnits(u!),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Fruit Estimation'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Fruit Set Percentage', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${settings.fruitSetPercentage.round()}%',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Text(
                    'Share of counted flowers expected to set fruit. Updates every Fruit View instantly — never changes stored flower data.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Slider(
                    value: settings.fruitSetPercentage,
                    min: 50,
                    max: 100,
                    divisions: 50,
                    label: '${settings.fruitSetPercentage.round()}%',
                    onChanged: (v) => context.read<SettingsProvider>().setFruitSetPercentage(v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Data'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup'),
                  subtitle: const Text('Export the full database as a file'),
                  onTap: () => BackupHelper.backup(context),
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Restore'),
                  subtitle: const Text('Import a previously exported backup'),
                  onTap: () => BackupHelper.restore(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionLabel('About'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('DragonTrack'),
                  subtitle: Text('Application'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Developed by'),
                  subtitle: Text(AppBranding.developer),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.apartment_outlined),
                  title: Text('Company / Owner'),
                  subtitle: Text(AppBranding.owner),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.copyright_outlined),
                  title: Text('Copyright'),
                  subtitle: Text(AppBranding.copyright),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Text(
                    AppBranding.ownershipStatement,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          const AppSignature(alignment: Alignment.bottomCenter),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}
