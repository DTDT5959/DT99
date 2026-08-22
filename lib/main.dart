import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/farm_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/farms/import_farm_preview_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve a cold-start .salsfarm file (Files app "Open"/"Open With" while
  // DragonTrack was fully closed), if any, BEFORE building the widget
  // tree — not inside a StatefulWidget's initState. Doing it here means
  // there is no race between this async platform-channel call and the
  // very first MaterialApp.home build: SplashScreen simply receives the
  // already-resolved answer as a constructor argument, so it can safely
  // route straight into ImportFarmPreviewScreen with zero risk of running
  // before the value exists.
  //
  // This is also the ONLY place that reads/resets the plugin's one-shot
  // getInitialMedia() value. HomeScreen (the other consumer, for files
  // opened while already running or resumed from background) only ever
  // listens to getMediaStream() — see HomeScreen — never calls
  // getInitialMedia() itself. Two callers racing to consume-and-reset the
  // same one-shot value is exactly what silently lost the file before:
  // whichever one lost the race saw an already-emptied result and fell
  // back to the ordinary Home screen, which is why the file appeared to
  // "not be received" even when the native side delivered it correctly.
  final pendingFarmFile = await _resolvePendingFarmFile();

  runApp(DragonFruitFlowerCounterApp(pendingFarmFile: pendingFarmFile));
}

Future<String?> _resolvePendingFarmFile() async {
  try {
    final files = await ReceiveSharingIntent.instance.getInitialMedia();
    // Consume it exactly once, right away, so nothing else can read it
    // again later and (correctly, but confusingly) get nothing back.
    await ReceiveSharingIntent.instance.reset();
    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.salsfarm')) return file.path;
    }
  } catch (e) {
    debugPrint('Initial sharing intent error: $e');
  }
  return null;
}

class DragonFruitFlowerCounterApp extends StatefulWidget {
  final String? pendingFarmFile;
  const DragonFruitFlowerCounterApp({super.key, this.pendingFarmFile});

  @override
  State<DragonFruitFlowerCounterApp> createState() =>
      _DragonFruitFlowerCounterAppState();
}

class _DragonFruitFlowerCounterAppState
    extends State<DragonFruitFlowerCounterApp> {
  final _settings = SettingsProvider();

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
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
              pendingFarmFile: widget.pendingFarmFile,
            ),
          );
        },
      ),
    );
  }
}