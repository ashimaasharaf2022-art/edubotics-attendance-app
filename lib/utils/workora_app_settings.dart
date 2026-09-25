import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide user preferences used by the Workora root application.
///
/// This is intentionally small so screens can update a preference without
/// owning a second, screen-local copy of the app state.
class WorkoraAppSettings {
  static final ValueNotifier<bool> isDarkMode = ValueNotifier<bool>(false);
  static final ValueNotifier<Locale> locale =
      ValueNotifier<Locale>(const Locale('en', 'IN'));

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    isDarkMode.value = prefs.getBool('workora_dark_mode') ?? false;

    final language = prefs.getString('app_language') ?? 'English (India)';
    locale.value = _localeFromLanguage(language);
  }

  static Future<void> setDarkMode(bool value) async {
    isDarkMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('workora_dark_mode', value);
  }

  static Future<void> setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', language);
    locale.value = _localeFromLanguage(language);
  }

  static Locale _localeFromLanguage(String language) {
    switch (language) {
      case 'Malayalam':
        return const Locale('ml', 'IN');
      case 'Hindi':
        return const Locale('hi', 'IN');
      case 'Tamil':
        return const Locale('ta', 'IN');
      case 'English (India)':
      default:
        return const Locale('en', 'IN');
    }
  }
}
