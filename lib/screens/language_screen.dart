import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String selected = "English (India)";

  static const options = ["English (India)", "Malayalam", "Hindi", "Tamil"];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => selected = prefs.getString("app_language") ?? "English (India)");
  }

  Future<void> _select(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("app_language", lang);
    setState(() => selected = lang);
    if (!mounted) return;
    Navigator.pop(context, lang);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Language", style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
        child: Column(
          children: options
              .map((lang) => RadioListTile<String>(
                    value: lang,
                    groupValue: selected,
                    activeColor: AppColors.primary,
                    title: Text(lang),
                    onChanged: (v) => _select(v!),
                  ))
              .toList(),
        ),
      ),
    );
  }
}