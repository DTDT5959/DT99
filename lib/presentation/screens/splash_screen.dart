import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/constants/app_branding.dart';
import 'home_screen.dart';
import 'farms/import_farm_preview_screen.dart';

class SplashScreen extends StatefulWidget {
  final String? pendingFarmFile;

  const SplashScreen({
    super.key,
    this.pendingFarmFile,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;

      _finishSplash();
    });
  }

  Future<void> _finishSplash() async {
    // A .salsfarm file was used to launch the app.
    if (widget.pendingFarmFile != null) {
      final file = File(widget.pendingFarmFile!);

      if (await file.exists()) {
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ImportFarmPreviewScreen(
              file: file,
            ),
          ),
        );

        return;
      }
    }

    // Normal app launch.
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E7D32),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🐉',
                  style: TextStyle(fontSize: 56),
                ),
                const SizedBox(height: 20),
                const Text(
                  AppBranding.owner,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Developed by ${AppBranding.developer}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
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
    );
  }
}