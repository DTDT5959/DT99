import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/constants/app_branding.dart';
import '../../core/constants/app_constants.dart';
import 'farms/farm_list_screen.dart';
import 'farms/create_farm_screen.dart';
import 'statistics/statistics_screen.dart';
import 'settings/settings_screen.dart';
import 'farms/import_farm_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<List<SharedMediaFile>>? _intentSub;
  bool _openingFarmFile = false;

  @override
  void initState() {
    super.initState();
    _setupFileListener();
  }

  Future<void> _setupFileListener() async {
    // Handles a .salsfarm file when DragonTrack is already open.
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        _handleReceivedFiles(files);
      },
      onError: (error) {
        debugPrint('File receiving error: $error');
      },
    );

    // Handles a .salsfarm file when DragonTrack was closed.
    try {
      final files =
          await ReceiveSharingIntent.instance.getInitialMedia();

      await _handleReceivedFiles(files);

      // Prevent the same file from being processed again.
      await ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('Initial file error: $e');
    }
  }

  Future<void> _handleReceivedFiles(
    List<SharedMediaFile> files,
  ) async {
    if (!mounted || _openingFarmFile || files.isEmpty) return;

    // Find the first .salsfarm file.
    SharedMediaFile? farmFile;

    for (final file in files) {
      final path = file.path;

      if (path.toLowerCase().endsWith('.salsfarm')) {
        farmFile = file;
        break;
      }
    }

    if (farmFile == null) {
      return;
    }

    final file = File(farmFile.path);

    if (!await file.exists()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access the farm file.'),
        ),
      );

      return;
    }

    if (!mounted) return;

    _openingFarmFile = true;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImportFarmPreviewScreen(file: file),
      ),
    );

    _openingFarmFile = false;
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '🐉',
                  style: TextStyle(fontSize: 34),
                ),
              ),

              const SizedBox(height: 20),

              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),

              const SizedBox(height: 6),

              Text(
                'Track flowering across every post, every season.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),

              const Spacer(),

              _HomeButton(
                icon: Icons.agriculture,
                label: 'My Farms',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FarmListScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _HomeButton(
                icon: Icons.add_circle_outline,
                label: 'Create New Farm',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateFarmScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _HomeButton(
                icon: Icons.bar_chart,
                label: 'Statistics',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StatisticsScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _HomeButton(
                icon: Icons.settings,
                label: 'Settings',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Center(
                child: Text(
                  AppBranding.copyright,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _HomeButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 12),
        Text(label),
      ],
    );

    return filled
        ? FilledButton(
            onPressed: onTap,
            child: child,
          )
        : OutlinedButton(
            onPressed: onTap,
            child: child,
          );
  }
}