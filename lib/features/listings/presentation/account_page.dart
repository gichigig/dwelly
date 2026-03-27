import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/user.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/theme_service.dart';
import '../../../core/data/kenya_locations.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/auth_gate_card.dart';
import 'rental_alerts_page.dart';
import 'donate_page.dart';
import 'notification_settings_page.dart';
import 'security_center_page.dart';
import 'security_setup_wizard_page.dart';
import 'privacy_personalization_page.dart';
import 'reports_safety_center_page.dart';

enum _SecurityWizardPromptAction { setupNow, remindLater }

class AccountPage extends StatefulWidget {
  final VoidCallback? onNavigateToSaved;
  const AccountPage({super.key, this.onNavigateToSaved});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static const String _securityWizardNextPromptPrefix =
      'security_setup_next_prompt_at_user_';
  static const Duration _securityWizardSnoozeDuration = Duration(days: 3);
  bool _securityCheckInFlight = false;
  DeviceLocationResult? _cachedDeviceLocation;
  bool _hasPendingProfileLocation = false;

  @override
  void initState() {
    super.initState();
    _loadLocalLocationFallback();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoOpenSecurityWizard();
    });
  }

  Future<void> _loadLocalLocationFallback() async {
    final cached = await DeviceLocationService.getCachedLocation();
    final pending = await DeviceLocationService.getPendingProfileLocation();
    if (!mounted) return;
    setState(() {
      _cachedDeviceLocation = cached;
      _hasPendingProfileLocation = pending != null && pending.isNotEmpty;
    });
  }

  Future<void> _maybeAutoOpenSecurityWizard() async {
    if (_securityCheckInFlight || !AuthService.isLoggedIn) {
      return;
    }

    final token = AuthService.token;
    final user = AuthService.currentUser;
    if (token == null || user == null) {
      return;
    }

    _securityCheckInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final promptKey = '$_securityWizardNextPromptPrefix${user.id}';
      final nextPromptRaw = prefs.getString(promptKey);
      if (nextPromptRaw != null) {
        final nextPromptAt = DateTime.tryParse(nextPromptRaw);
        if (nextPromptAt != null && DateTime.now().isBefore(nextPromptAt)) {
          return;
        }
      }

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/security/methods'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        return;
      }

      final isIncomplete = _isSecuritySetupIncomplete(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (!isIncomplete || !mounted) {
        await prefs.remove(promptKey);
        return;
      }

      final action = await showDialog<_SecurityWizardPromptAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Secure your account'),
          content: const Text(
            'Set up Authenticator, recovery codes, and passkey to protect your account.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  _SecurityWizardPromptAction.remindLater,
                );
              },
              child: const Text('Remind me in 3 days'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  _SecurityWizardPromptAction.setupNow,
                );
              },
              child: const Text('Set up now'),
            ),
          ],
        ),
      );
      if (action != _SecurityWizardPromptAction.setupNow) {
        await prefs.setString(
          promptKey,
          DateTime.now().add(_securityWizardSnoozeDuration).toIso8601String(),
        );
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SecuritySetupWizardPage()),
      );
      if (!mounted) return;

      final recheckResponse = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/security/methods'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (recheckResponse.statusCode != 200) {
        await prefs.setString(
          promptKey,
          DateTime.now().add(_securityWizardSnoozeDuration).toIso8601String(),
        );
        return;
      }

      final stillIncomplete = _isSecuritySetupIncomplete(
        jsonDecode(recheckResponse.body) as Map<String, dynamic>,
      );
      if (stillIncomplete) {
        await prefs.setString(
          promptKey,
          DateTime.now().add(_securityWizardSnoozeDuration).toIso8601String(),
        );
      } else {
        await prefs.remove(promptKey);
      }
      setState(() {});
    } catch (_) {
      // Silent fail: account page should still load if security pre-check fails.
    } finally {
      _securityCheckInFlight = false;
    }
  }

  bool _isSecuritySetupIncomplete(Map<String, dynamic> data) {
    final totpEnabled = data['totpEnabled'] == true;
    final recoveryRemaining =
        (data['recoveryCodesRemaining'] as num?)?.toInt() ?? 0;
    final passkeys = data['passkeys'] as List<dynamic>? ?? const [];
    return !totpEnabled || recoveryRemaining <= 0 || passkeys.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AuthService.isLoggedIn
            ? _buildLoggedInView()
            : _buildLoginView(),
      ),
    );
  }

  Widget _buildLoginView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Account",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          AuthGateCard(
            title: 'Welcome!',
            subtitle:
                'Sign in or create an account to save your favorite listings and chat with owners',
            onSignIn: () => _showLoginDialog(context),
            onCreateAccount: () => _showSignupDialog(context),
          ),
          const SizedBox(height: 24),
          _buildAppearanceCard(context),
        ],
      ),
    );
  }

  Widget _buildLoggedInView() {
    final user = AuthService.currentUser!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Account",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // Profile Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Theme.of(context).primaryColor,
                    child: Text(
                      user.firstName.isNotEmpty
                          ? user.firstName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (user.authProvider.toUpperCase() == 'GOOGLE')
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Signed in with Google',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditProfileDialog(context),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Location Section
          _buildSectionTitle('Location'),
          _buildLocationCard(user),
          const SizedBox(height: 16),

          // FYP Preferences Section
          _buildSectionTitle('For You Feed'),
          _buildFypPreferencesCard(user),
          const SizedBox(height: 16),

          // Menu Items
          _buildSectionTitle('Account'),
          _buildMenuItem(
            icon: Icons.person,
            title: 'Edit Profile',
            onTap: () => _showEditProfileDialog(context),
          ),
          _buildMenuItem(
            icon: Icons.bookmark,
            title: 'Saved Listings',
            onTap: () {
              widget.onNavigateToSaved?.call();
            },
          ),
          _buildMenuItem(
            icon: Icons.notifications_active,
            title: 'Rental Alerts',
            subtitle: 'Get notified about new listings',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const RentalAlertsPage(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.flag_outlined,
            title: 'Reports & Safety',
            subtitle: 'Reports, outcomes and appeals',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ReportsSafetyCenterPage(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.security,
            title: 'Security Center',
            subtitle: 'Password, devices and account deletion',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SecurityCenterPage(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.notifications,
            title: 'Notification Settings',
            onTap: () => _showNotificationSettingsDialog(context),
          ),
          _buildMenuItem(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & Personalization',
            subtitle: 'Ads, analytics and recommendation history',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PrivacyPersonalizationPage(),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.dark_mode_outlined,
            title: 'Appearance',
            subtitle: _themeLabel(ThemeService.instance.mode),
            onTap: () => _showThemeSheet(context),
          ),
          _buildMenuItem(
            icon: Icons.help,
            title: 'Help & Support',
            onTap: () => _showHelpDialog(context),
          ),
          _buildMenuItem(
            icon: Icons.favorite,
            title: 'Support Dwelly',
            subtitle: 'Donate via M-Pesa',
            color: const Color(0xFF4CAF50),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DonatePage()),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.info,
            title: 'About',
            onTap: () => _showAboutDialog(context),
          ),
          const Divider(height: 32),
          _buildMenuItem(
            icon: Icons.logout,
            title: 'Sign Out',
            color: Colors.red,
            onTap: () => _signOut(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.grey[700]),
      title: Text(title, style: TextStyle(fontSize: 16, color: color)),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildAppearanceCard(BuildContext context) {
    final mode = ThemeService.instance.mode;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.dark_mode_outlined, color: Colors.grey[700]),
        title: const Text('Appearance'),
        subtitle: Text(_themeLabel(mode)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showThemeSheet(context),
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Use device setting';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  void _showThemeSheet(BuildContext context) {
    final themeService = ThemeService.instance;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> updateMode(ThemeMode mode) async {
            await themeService.setMode(mode);
            setModalState(() {});
            if (mounted) setState(() {});
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Appearance',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose your preferred theme',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                RadioListTile<ThemeMode>(
                  title: const Text('Use device setting'),
                  value: ThemeMode.system,
                  groupValue: themeService.mode,
                  onChanged: (mode) => mode != null ? updateMode(mode) : null,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: themeService.mode,
                  onChanged: (mode) => mode != null ? updateMode(mode) : null,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: themeService.mode,
                  onChanged: (mode) => mode != null ? updateMode(mode) : null,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildLocationCard(User user) {
    final hasProfileLocation = user.hasLocation;
    final hasCachedLocation = _cachedDeviceLocation?.hasLocationData == true;
    final displayLocation = hasProfileLocation
        ? user.formattedLocation
        : hasCachedLocation
        ? _cachedDeviceLocation!.detailedDisplayName
        : 'Not set';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Location',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayLocation,
                        style: TextStyle(
                          color: hasProfileLocation || hasCachedLocation
                              ? Colors.grey[700]
                              : Colors.grey[500],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showLocationSettingsSheet(context),
                ),
              ],
            ),
            if (!user.hasLocation) ...[
              const SizedBox(height: 12),
              Text(
                hasCachedLocation
                    ? (_hasPendingProfileLocation
                          ? 'Detected on this device. Sync will happen after sign-in refresh.'
                          : 'Using your last device location until profile sync completes.')
                    : 'Set your location to see nearby rentals in your feed',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFypPreferencesCard(User user) {
    final hasWards = user.fypWards.isNotEmpty;
    final hasNicknames = user.fypNicknames.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feed Preferences',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Customize your rental feed',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showFypSettingsSheet(context),
                ),
              ],
            ),
            if (hasWards || hasNicknames) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              if (hasWards) ...[
                Text(
                  'Preferred Wards (${user.fypWards.length}/5)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: user.fypWards
                      .map(
                        (ward) => Chip(
                          label: Text(
                            ward,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (hasNicknames) ...[
                Text(
                  'Area Nicknames (${user.fypNicknames.length})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: user.fypNicknames
                      .map(
                        (nickname) => Chip(
                          label: Text(
                            nickname,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.orange.withOpacity(0.1),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              Text(
                'Add your preferred areas to see relevant rentals in your feed',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLocationSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _LocationSettingsSheet(
          user: AuthService.currentUser!,
          onSave: (updatedUser) async {
            await AuthService.updateUser(updatedUser);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _showFypSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FypSettingsSheet(
        user: AuthService.currentUser!,
        onSave: (updatedUser) async {
          await AuthService.updateUser(updatedUser);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showNotificationSettingsDialog(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NotificationSettingsPage()));
  }

  void _showHelpDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Help & Support',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Contact Support'),
                subtitle: const Text('ngangabildad@gmail.com'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('mailto:ngangabildad@gmail.com'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Call Us'),
                subtitle: const Text('+254 768 311 755'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse('tel:+254768311755'));
                },
              ),
              ListTile(
                leading: const Icon(Icons.question_answer),
                title: const Text('FAQs'),
                subtitle: const Text('Find answers to common questions'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://www.billygichigidev.me/faqs'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip),
                title: const Text('Privacy Policy'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse('https://www.billygichigidev.me/privacy-policy'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('Terms of Service'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(
                    Uri.parse(
                      'https://www.billygichigidev.me/terms-and-conditions',
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Platform Scope'),
                subtitle: const Text(
                  'Discover rentals, ads, and lost IDs. No in-app payments.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.home, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Real Estate App'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0'),
            SizedBox(height: 16),
            Text(
              'Find rentals, discover ads, and use lost ID upload/search workflows. Browse listings, save favorites, and connect directly with property owners.',
            ),
            SizedBox(height: 12),
            Text(
              'RealEstate does not process rent or in-app payments.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 16),
            Text(
              '© 2026 Real Estate App. All rights reserved.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    showLoginBottomSheet(
      context,
      onSuccess: () {
        setState(() {});
        _loadLocalLocationFallback();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeAutoOpenSecurityWizard();
        });
      },
    );
  }

  void _showSignupDialog(BuildContext context) {
    showSignupBottomSheet(
      context,
      onSuccess: () {
        setState(() {});
        _loadLocalLocationFallback();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeAutoOpenSecurityWizard();
        });
      },
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EditProfileForm(
        user: AuthService.currentUser!,
        onSuccess: () {
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      setState(() {});
    }
  }
}

class _EditProfileForm extends StatefulWidget {
  final User user;
  final VoidCallback onSuccess;

  const _EditProfileForm({required this.user, required this.onSuccess});

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.user.firstName);
    _lastNameController = TextEditingController(text: widget.user.lastName);
    _phoneController = TextEditingController(text: widget.user.phone ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await AuthService.updateProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );
      widget.onSuccess();
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to update profile.',
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Edit Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'First Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'Last Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone (optional)',
                prefixIcon: const Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Location Settings Sheet
class _LocationSettingsSheet extends StatefulWidget {
  final User user;
  final Function(User) onSave;

  const _LocationSettingsSheet({required this.user, required this.onSave});

  @override
  State<_LocationSettingsSheet> createState() => _LocationSettingsSheetState();
}

class _LocationSettingsSheetState extends State<_LocationSettingsSheet> {
  bool _isLoading = false;
  bool _isDetecting = false;
  DeviceLocationResult? _detectedLocation;

  String? _ward;
  String? _constituency;
  String? _county;
  String? _areaName;

  @override
  void initState() {
    super.initState();
    _ward = widget.user.locationWard;
    _constituency = widget.user.locationConstituency;
    _county = widget.user.locationCounty;
    _areaName = widget.user.locationAreaName;
  }

  Future<void> _detectLocation() async {
    if (!mounted) return;
    setState(() => _isDetecting = true);

    try {
      final result = await DeviceLocationService.getCurrentLocation();

      if (result.success && result.hasLocationData) {
        setState(() {
          _detectedLocation = result;
          _ward = result.ward;
          _constituency = result.constituency;
          _county = result.county;
          _areaName = result.areaName;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Could not detect location'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to detect location')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  Future<void> _save() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final updatedUser = widget.user.copyWith(
        locationWard: _ward,
        locationConstituency: _constituency,
        locationCounty: _county,
        locationAreaName: _areaName,
        locationLatitude: _detectedLocation?.latitude,
        locationLongitude: _detectedLocation?.longitude,
      );

      await widget.onSave(updatedUser);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your Location',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your location to see nearby rentals in your feed',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),

            // Detect location button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDetecting ? null : _detectLocation,
                icon: _isDetecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _isDetecting ? 'Detecting...' : 'Detect My Location',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            if (_ward != null || _constituency != null || _county != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Detected/Set location display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Location Set',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_areaName != null)
                      _buildLocationRow('Area', _areaName!),
                    if (_ward != null) _buildLocationRow('Ward', _ward!),
                    if (_constituency != null)
                      _buildLocationRow('Constituency', _constituency!),
                    if (_county != null) _buildLocationRow('County', _county!),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (_ward != null ||
                            _constituency != null ||
                            _county != null) &&
                        !_isLoading
                    ? _save
                    : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Location',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// FYP (For You Page) Settings Sheet
class _FypSettingsSheet extends StatefulWidget {
  final User user;
  final Function(User) onSave;

  const _FypSettingsSheet({required this.user, required this.onSave});

  @override
  State<_FypSettingsSheet> createState() => _FypSettingsSheetState();
}

class _FypSettingsSheetState extends State<_FypSettingsSheet> {
  bool _isLoading = false;
  final _nicknameController = TextEditingController();
  final _wardSearchController = TextEditingController();

  late List<String> _selectedWards;
  late List<String> _selectedNicknames;
  List<LocationSearchResult> _wardSuggestions = [];

  @override
  void initState() {
    super.initState();
    _selectedWards = List.from(widget.user.fypWards);
    _selectedNicknames = List.from(widget.user.fypNicknames);
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _wardSearchController.dispose();
    super.dispose();
  }

  void _onWardSearchChanged(String query) {
    if (query.length < 2) {
      setState(() => _wardSuggestions = []);
      return;
    }

    final results = KenyaLocations.searchLocations(query)
        .where(
          (r) => r.type == LocationType.ward || r.type == LocationType.area,
        )
        .take(10)
        .toList();

    setState(() => _wardSuggestions = results);
  }

  void _addWard(LocationSearchResult location) {
    final wardName = location.ward ?? location.name;

    if (_selectedWards.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maximum 5 wards allowed')));
      return;
    }

    if (!_selectedWards.contains(wardName)) {
      setState(() {
        _selectedWards.add(wardName);
        _wardSearchController.clear();
        _wardSuggestions = [];
      });
    }
  }

  void _removeWard(String ward) {
    setState(() => _selectedWards.remove(ward));
  }

  void _addNickname() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;

    if (!_selectedNicknames.contains(nickname)) {
      setState(() {
        _selectedNicknames.add(nickname);
        _nicknameController.clear();
      });
    }
  }

  void _removeNickname(String nickname) {
    setState(() => _selectedNicknames.remove(nickname));
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    try {
      final updatedUser = widget.user.copyWith(
        fypWards: _selectedWards,
        fypNicknames: _selectedNicknames,
      );

      await widget.onSave(updatedUser);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Feed Preferences',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Customize your feed to see rentals in your preferred areas',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),

              // Preferred Wards Section
              Row(
                children: [
                  const Icon(Icons.location_city, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Preferred Wards (${_selectedWards.length}/5)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select up to 5 wards to prioritize in your feed',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Ward search field
              TextField(
                controller: _wardSearchController,
                onChanged: _onWardSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search for a ward...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.55)
                      : Colors.grey[100],
                ),
              ),

              // Ward suggestions
              if (_wardSuggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _wardSuggestions.length,
                    itemBuilder: (context, index) {
                      final location = _wardSuggestions[index];
                      return ListTile(
                        dense: true,
                        title: Text(location.name),
                        subtitle: Text(
                          '${location.constituency ?? ''}, ${location.county ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.add_circle_outline,
                          size: 20,
                        ),
                        onTap: () => _addWard(location),
                      );
                    },
                  ),
                ),

              // Selected wards
              if (_selectedWards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedWards
                      .map(
                        (ward) => Chip(
                          label: Text(ward),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeWard(ward),
                          backgroundColor: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.1),
                        ),
                      )
                      .toList(),
                ),
              ],

              const SizedBox(height: 32),

              // Area Nicknames Section
              Row(
                children: [
                  const Icon(Icons.bookmark, size: 20, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'Area Nicknames (${_selectedNicknames.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Add common area names or nicknames (e.g., Ruaka, South B, Tena)',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 12),

              // Nickname input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nicknameController,
                      decoration: InputDecoration(
                        hintText: 'Enter area nickname...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withOpacity(0.55)
                            : Colors.grey[100],
                      ),
                      onSubmitted: (_) => _addNickname(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addNickname,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),

              // Selected nicknames
              if (_selectedNicknames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedNicknames
                      .map(
                        (nickname) => Chip(
                          label: Text(nickname),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeNickname(nickname),
                          backgroundColor: Colors.orange.withOpacity(0.1),
                        ),
                      )
                      .toList(),
                ),
              ],

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Save Preferences',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
