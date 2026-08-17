import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/fruit_calculation_service.dart';

/// Persists lightweight app-level preferences (theme, units) outside of
/// SQLite since they're key/value, not relational, data.
class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _units = 'metric'; // metric | imperial — affects future area/GPS displays
  double _fruitSetPercentage = FruitCalculationService.defaultFruitSetPercentage;

  ThemeMode get themeMode => _themeMode;
  String get units => _units;

  /// How many of the recorded flowers are expected to set fruit, as a
  /// percentage (50–100). Changing this only affects Fruit View's live
  /// calculation — it never touches stored flower counts.
  double get fruitSetPercentage => _fruitSetPercentage;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    if (saved == 'light') _themeMode = ThemeMode.light;
    if (saved == 'dark') _themeMode = ThemeMode.dark;
    _units = prefs.getString('units') ?? 'metric';
    _fruitSetPercentage = prefs.getDouble('fruit_set_percentage') ??
        FruitCalculationService.defaultFruitSetPercentage;
    notifyListeners();
  }

  Future<void> setFruitSetPercentage(double value) async {
    _fruitSetPercentage = value.clamp(
      FruitCalculationService.minFruitSetPercentage,
      FruitCalculationService.maxFruitSetPercentage,
    );
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fruit_set_percentage', _fruitSetPercentage);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      mode == ThemeMode.light ? 'light' : (mode == ThemeMode.dark ? 'dark' : 'system'),
    );
  }

  Future<void> setUnits(String units) async {
    _units = units;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('units', units);
  }
}
