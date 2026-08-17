import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/farm_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/farms/import_farm_preview_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DragonFruitFlowerCounterApp());
}

class DragonFruitFlowerCounterApp extends StatefulWidget {
  const DragonFruitFlowerCounterApp({super.key});

  @override
  State<DragonFruitFlowerCounterApp> createState() =>
      _DragonFruitFlowerCounterAppState();
}

class _DragonFruitFlowerCounterAppState
    extends State<DragonFruitFlowerCounterApp> {
  final _settings = SettingsProvider();

  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  String? _pendingFarmFile;

  @override
  void initState() {
    super.initState();

    _settings.load();
    _listenForFarmFiles();
  }

  void _listenForFarmFiles() {
    // App already running.
    _intentSub =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        _checkFiles(files);
      },
      onError: (error) {
        debugPrint('Sharing intent error: $error');
      },
    );

    // App launched by opening a .salsfarm file.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _checkFiles(files);

      ReceiveSharingIntent.instance.reset();
    }).catchError((error) {
      debugPrint('Initial sharing intent error: $error');
    });
  }

  void _checkFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.salsfarm')) {
        _pendingFarmFile = file.path;

        debugPrint('Received farm file: ${file.path}');
        break;
      }
    }
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => FarmProvider(),
        ),
        ChangeNotifierProvider.value(
          value: _settings,
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'DragonTrack',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,

            home: SplashScreen(
              pendingFarmFile: _pendingFarmFile,
            ),
          );
        },
      ),
    );
  }
}