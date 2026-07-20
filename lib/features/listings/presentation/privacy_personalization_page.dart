import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/user_preferences_service.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

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

      final rawData = jsonDecode(response.body) as Map<String, dynamic>;

      // Filter out internal backend variables (id, realadmin flags, helper fields, raw GPS) and nulls
      final cleanData = <String, Map<String, dynamic>>{
        'Personal Profile': {
          if (_cleanVal(rawData['firstName']) != null ||
              _cleanVal(rawData['lastName']) != null)
            'Name':
                '${_cleanVal(rawData['firstName']) ?? ''} ${_cleanVal(rawData['lastName']) ?? ''}'
                    .trim(),
          if (_cleanVal(rawData['email']) != null) 'Email': rawData['email'],
          if (_cleanVal(rawData['phone']) != null) 'Phone': rawData['phone'],
          if (_cleanVal(rawData['userType']) != null)
            'Account Type': rawData['userType'],
          if (_cleanVal(rawData['verificationStatus']) != null)
            'Verification Status': rawData['verificationStatus'],
        },
        'Subscription & Activity': {
          'Membership Plan': rawData['premiumActive'] == true
              ? 'Premium Account'
              : 'Standard (Free)',
          if (_cleanVal(rawData['premiumExpiresAt']) != null)
            'Premium Expires': rawData['premiumExpiresAt'],
          if (_cleanVal(rawData['lastLoginAt']) != null)
            'Last Activity': rawData['lastLoginAt'],
        },
        'Saved Location & Area': {
          if (_cleanVal(rawData['locationCounty']) != null)
            'County': rawData['locationCounty'],
          if (_cleanVal(rawData['locationConstituency']) != null)
            'Constituency': rawData['locationConstituency'],
          if (_cleanVal(rawData['locationWard']) != null)
            'Ward': rawData['locationWard'],
          if (_cleanVal(rawData['locationAreaName']) != null)
            'Area / Neighborhood': rawData['locationAreaName'],
        },
        'Security & Login': {
          'Two-Factor Auth (MFA)': rawData['mfaEnabled'] == true
              ? 'Enabled'
              : 'Disabled',
          'Passkey Login': rawData['passkeyEnabled'] == true
              ? 'Enabled'
              : 'Disabled',
        },
      };

      cleanData.removeWhere((key, value) => value.isEmpty);
      final cleanJsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(cleanData);

      await showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.folder_shared_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Account Data Summary'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: cleanData.entries.map((section) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.key,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: section.value.entries.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 140,
                                        child: Text(
                                          '${item.key}:',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${item.value}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cleanJsonString));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Clean account data copied to clipboard'),
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy JSON'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String? _cleanVal(dynamic v) {
    if (v == null) return null;
    final str = v.toString().trim();
    if (str.isEmpty || str == 'null') return null;
    return str;
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
      return const Scaffold(body: Center(child: DwellyOrbitingLoader()));
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
