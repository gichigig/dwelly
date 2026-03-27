import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/user_preferences_service.dart';

class PrivacyPersonalizationPage extends StatefulWidget {
  const PrivacyPersonalizationPage({super.key});

  @override
  State<PrivacyPersonalizationPage> createState() =>
      _PrivacyPersonalizationPageState();
}

class _PrivacyPersonalizationPageState
    extends State<PrivacyPersonalizationPage> {
  bool _adPersonalization = true;
  bool _analyticsSharing = true;
  bool _preciseLocation = true;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adPersonalization = prefs.getBool('pref_ad_personalization') ?? true;
      _analyticsSharing = prefs.getBool('pref_analytics_sharing') ?? true;
      _preciseLocation = prefs.getBool('pref_location_precise') ?? true;
      _loading = false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_ad_personalization', _adPersonalization);
    await prefs.setBool('pref_analytics_sharing', _analyticsSharing);
    await prefs.setBool('pref_location_precise', _preciseLocation);
  }

  Future<void> _exportAccountData() async {
    final token = AuthService.token;
    if (token == null) return;

    setState(() => _working = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export data (${response.statusCode})'),
          ),
        );
        return;
      }

      final pretty = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(response.body));
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Account Data Export'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _clearRecommendationHistory() async {
    setState(() => _working = true);
    try {
      final userPrefs = await UserPreferencesService.getInstance();
      await userPrefs.clearPreferences();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recommendation history cleared')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Personalization')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _adPersonalization,
            title: const Text('Ad personalization'),
            subtitle: const Text('Use activity to improve ad targeting'),
            onChanged: (value) async {
              setState(() => _adPersonalization = value);
              await _savePrefs();
            },
          ),
          SwitchListTile(
            value: _analyticsSharing,
            title: const Text('Analytics sharing'),
            subtitle: const Text('Help improve the app with usage analytics'),
            onChanged: (value) async {
              setState(() => _analyticsSharing = value);
              await _savePrefs();
            },
          ),
          SwitchListTile(
            value: _preciseLocation,
            title: const Text('Precise location mode'),
            subtitle: const Text('Use exact location for local relevance'),
            onChanged: (value) async {
              setState(() => _preciseLocation = value);
              await _savePrefs();
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Export account data'),
            subtitle: const Text('View and copy your profile data export'),
            onTap: _working ? null : _exportAccountData,
          ),
          ListTile(
            leading: const Icon(Icons.history_toggle_off_outlined),
            title: const Text('Clear recommendation history'),
            subtitle: const Text('Reset local ranking and interaction history'),
            onTap: _working ? null : _clearRecommendationHistory,
          ),
        ],
      ),
    );
  }
}
