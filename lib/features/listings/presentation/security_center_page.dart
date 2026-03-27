import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/errors/passkey_error_mapper.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import 'security_setup_wizard_page.dart';
import '../../auth/presentation/forgot_password_screen.dart';

class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key});

  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  final PasskeyAuthenticator _passkeyAuthenticator = PasskeyAuthenticator();
  bool _loading = true;
  bool _busy = false;
  List<_DeviceSession> _sessions = [];
  String _lastLoginLabel = 'Unknown';
  _SecurityMethods? _securityMethods;
  List<String> _latestRecoveryCodes = const [];

  String _authProviderLabel(User? user) {
    final provider = (user?.authProvider ?? 'LOCAL').toUpperCase();
    if (provider == 'GOOGLE') return 'Google';
    return 'Email/Password';
  }

  Future<void> _openPasswordReset(User? user) async {
    if (user == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: user.email),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawLastLogin = prefs.getString('last_login_at');
      if (rawLastLogin != null) {
        final parsed = DateTime.tryParse(rawLastLogin);
        if (parsed != null) {
          _lastLoginLabel =
              '${parsed.day}/${parsed.month}/${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
        }
      }

      final token = AuthService.token;
      if (token != null) {
        final responses = await Future.wait([
          http.get(
            Uri.parse('${ApiService.baseUrl}/notifications/devices'),
            headers: {'Authorization': 'Bearer $token'},
          ),
          http.get(
            Uri.parse('${ApiService.baseUrl}/auth/security/methods'),
            headers: {'Authorization': 'Bearer $token'},
          ),
        ]);

        final devicesResponse = responses[0];
        final methodsResponse = responses[1];

        if (devicesResponse.statusCode == 200) {
          final List<dynamic> data = jsonDecode(devicesResponse.body);
          _sessions = data
              .map(
                (item) => _DeviceSession.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }

        if (methodsResponse.statusCode == 200) {
          _securityMethods = _SecurityMethods.fromJson(
            jsonDecode(methodsResponse.body) as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      _sessions = [];
      _securityMethods = null;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSetupWizard() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SecuritySetupWizardPage()));
    if (!mounted) return;
    await _load();
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    if (newController.text != confirmController.text) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    final token = AuthService.token;
    if (token == null) return;

    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'currentPassword': currentController.text,
          'newPassword': newController.text,
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password changed')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change password (${response.statusCode})'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revokeDevice(int deviceId) async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/notifications/device/$deviceId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        await _load();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signOutAllDevices() async {
    final token = AuthService.token;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out All Devices'),
        content: const Text(
          'This will invalidate notifications on all devices. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out All'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await http.delete(
        Uri.parse('${ApiService.baseUrl}/notifications/devices'),
        headers: {'Authorization': 'Bearer $token'},
      );
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    final token = AuthService.token;
    if (token == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('This action is permanent and cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/auth/account'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        await AuthService.logout();
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setupTotp() async {
    final token = AuthService.token;
    if (token == null) return;

    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/security/totp/setup'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception('Unable to start TOTP setup');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final setupToken = data['setupToken']?.toString();
      final qrPngBase64 = data['qrPngBase64']?.toString() ?? '';
      final otpauthUri = data['otpauthUri']?.toString() ?? '';
      final manualSecret = _extractSecretFromOtpAuthUri(otpauthUri);
      final fallbackSecret = data['secretMasked']?.toString() ?? '';

      if (!mounted || setupToken == null) return;
      final codeController = TextEditingController();
      final shouldConfirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Setup Authenticator'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scan this QR code with Google Authenticator, Microsoft Authenticator, or Authy.',
                  ),
                  const SizedBox(height: 12),
                  if (qrPngBase64.isNotEmpty)
                    Center(
                      child: Image.memory(
                        base64Decode(qrPngBase64),
                        width: 180,
                        height: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (manualSecret != null && manualSecret.isNotEmpty) ...[
                    const Text(
                      'Manual key',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      manualSecret,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                  ] else if (fallbackSecret.isNotEmpty) ...[
                    const Text(
                      'Manual key',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      fallbackSecret,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Enter 6-digit code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (shouldConfirm != true) return;

      final confirmResponse = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/security/totp/confirm'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'setupToken': setupToken,
          'code': codeController.text.trim(),
        }),
      );

      if (confirmResponse.statusCode != 200) {
        throw Exception(_extractErrorMessage(confirmResponse, 'Invalid code'));
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Authenticator enabled')));
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to setup authenticator.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerPasskey() async {
    final token = AuthService.token;
    if (token == null) return;

    final nameController = TextEditingController(
      text: 'This device ${DateTime.now().year}',
    );

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register Passkey'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Passkey name',
            hintText: 'e.g. Billy Android Phone',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (shouldContinue != true) return;

    setState(() => _busy = true);
    try {
      final optionsResponse = await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/auth/security/passkeys/registration/options',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (optionsResponse.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(optionsResponse, 'Passkey registration failed'),
        );
      }

      final options = jsonDecode(optionsResponse.body) as Map<String, dynamic>;
      final registrationId = options['registrationId']?.toString() ?? '';
      final registrationToken = options['registrationToken']?.toString() ?? '';
      final rp = options['relyingParty'] as Map<String, dynamic>? ?? const {};
      final rpId = rp['id']?.toString();
      print(
        'Passkey registration - rpId: $rpId, baseUrl: ${ApiService.baseUrl}',
      );
      if (registrationId.isEmpty || registrationToken.isEmpty) {
        throw Exception('Invalid passkey registration challenge');
      }
      _validatePasskeyRpId(rpId);

      final registerRequest = RegisterRequestType.fromJson({
        'challenge': options['challenge'],
        'rp': rp,
        'user': options['user'],
        'timeout': options['timeout'] ?? 60000,
        'attestation': options['attestation'] ?? 'none',
        'authenticatorSelection': const {
          'requireResidentKey': true,
          'residentKey': 'required',
          'userVerification': 'preferred',
        },
        'excludeCredentials': options['excludeCredentials'] ?? const [],
        'pubKeyCredParams': const [
          {'type': 'public-key', 'alg': -7},
          {'type': 'public-key', 'alg': -257},
        ],
      });

      final credential = await _passkeyAuthenticator.register(registerRequest);
      final verifyResponse = await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/auth/security/passkeys/registration/verify',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'registrationId': registrationId,
          'registrationToken': registrationToken,
          'credential': credential.toJson(),
          'name': nameController.text.trim(),
        }),
      );
      if (verifyResponse.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(verifyResponse, 'Passkey registration failed'),
        );
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passkey registered')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        PasskeyErrorMapper.fromPlatformException(e),
        fallbackMessage: 'Passkey registration failed.',
      );
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Passkey registration failed.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRecoveryCodesDialog(List<String> codes) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recovery Codes'),
        content: SizedBox(
          width: 360,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Store these codes safely. Each code can be used once.',
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    itemCount: codes.length,
                    itemBuilder: (context, index) => Text(
                      '${index + 1}. ${codes[index]}',
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: codes.join('\n')),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final path = await _downloadRecoveryCodes(codes);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Saved to $path')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        showErrorSnackBar(
                          context,
                          e,
                          fallbackMessage:
                              'Failed to download recovery codes.',
                        );
                      }
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<String> _downloadRecoveryCodes(List<String> codes) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final filename = 'recovery-codes-$timestamp.txt';
    final content =
        'Dwelly Recovery Codes\nGenerated: ${DateTime.now().toIso8601String()}\n\n${codes.join('\n')}\n';

    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } catch (_) {}

    if (directory == null && Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    }
    directory ??= await getApplicationDocumentsDirectory();

    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  String? _extractSecretFromOtpAuthUri(String uri) {
    if (uri.isEmpty) return null;
    try {
      final parsed = Uri.parse(uri);
      final value = parsed.queryParameters['secret'];
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  String _extractErrorMessage(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        final error = decoded['error']?.toString();
        if (error != null && error.isNotEmpty) {
          return error;
        }
      }
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  void _validatePasskeyRpId(String? rpId) {
    final value = (rpId ?? '').trim().toLowerCase();
    if (value.isEmpty || value == 'localhost' || value == '127.0.0.1') {
      throw Exception(
        'Passkey is not production-configured yet. Set AUTH_PASSKEY_RP_ID to a real HTTPS domain and configure Android asset links.',
      );
    }
  }

  Future<void> _disableTotp() async {
    final token = AuthService.token;
    if (token == null) return;

    final proofController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Authenticator'),
        content: TextField(
          controller: proofController,
          decoration: const InputDecoration(
            labelText: 'Password or MFA proof',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/auth/security/totp'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'passwordOrMfaProof': proofController.text.trim()}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to disable authenticator');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to disable authenticator.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _regenerateRecoveryCodes() async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse(
          '${ApiService.baseUrl}/auth/security/recovery-codes/regenerate',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Failed to regenerate recovery codes'),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _latestRecoveryCodes = (data['codes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList();
      await _load();
      if (!mounted) return;
      await _showRecoveryCodesDialog(_latestRecoveryCodes);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to regenerate recovery codes.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updatePreferredMethod(String method) async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/auth/security/preference'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'preferredMethod': method}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to update preferred method');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to update preferred method.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokePasskey(int passkeyId) async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/auth/security/passkeys/$passkeyId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to revoke passkey');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to revoke passkey.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Security Center')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(user?.email ?? 'Account'),
                    subtitle: Text(
                      'Auth provider: ${_authProviderLabel(user)}\nLast login: $_lastLoginLabel',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      if ((user?.authProvider ?? 'LOCAL').toUpperCase() == 'LOCAL')
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Change Password'),
                          onTap: _busy ? null : _changePassword,
                        )
                      else
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Set Password via Email'),
                          subtitle: const Text(
                            'Social sign-in accounts use a reset email to set a password.',
                          ),
                          onTap: _busy ? null : () => _openPasswordReset(user),
                        ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.devices_outlined),
                        title: const Text('Sign Out All Devices'),
                        onTap: _busy ? null : _signOutAllDevices,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Delete Account',
                          style: TextStyle(color: Colors.red),
                        ),
                        onTap: _busy ? null : _deleteAccount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Multi-Factor Authentication',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _openSetupWizard,
                            icon: const Icon(Icons.auto_fix_high_outlined),
                            label: const Text('Open Guided Security Setup'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _securityMethods == null
                              ? 'Unable to load MFA settings'
                              : 'Enabled: ${_securityMethods!.mfaEnabled ? "Yes" : "No"} | TOTP: ${_securityMethods!.totpEnabled ? "On" : "Off"} | Passkey: ${_securityMethods!.passkeyEnabled ? "On" : "Off"}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Recovery codes remaining: ${_securityMethods?.recoveryCodesRemaining ?? 0}',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _busy
                                    ? null
                                    : (_securityMethods?.totpEnabled ?? false)
                                    ? _disableTotp
                                    : _setupTotp,
                                child: Text(
                                  (_securityMethods?.totpEnabled ?? false)
                                      ? 'Disable Authenticator'
                                      : 'Enable Authenticator',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : _regenerateRecoveryCodes,
                                child: const Text('Regenerate Recovery'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _registerPasskey,
                            icon: const Icon(Icons.key_outlined),
                            label: const Text(
                              'Register Passkey on this device',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_securityMethods != null)
                          Builder(
                            builder: (_) {
                              final available =
                                  _securityMethods!.availablePreferenceMethods;
                              final preferred =
                                  available.contains(
                                    _securityMethods!.preferredMethod,
                                  )
                                  ? _securityMethods!.preferredMethod
                                  : available.first;
                              return DropdownButtonFormField<String>(
                                value: preferred,
                                decoration: const InputDecoration(
                                  labelText: 'Preferred method',
                                  border: OutlineInputBorder(),
                                ),
                                items: available
                                    .map(
                                      (method) => DropdownMenuItem(
                                        value: method,
                                        child: Text(method),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  _updatePreferredMethod(value);
                                },
                              );
                            },
                          ),
                        if ((_securityMethods?.passkeys ?? const [])
                            .isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Registered Passkeys',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          ...(_securityMethods?.passkeys ?? const []).map(
                            (passkey) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.key_outlined),
                              title: Text(passkey.name ?? 'Passkey'),
                              subtitle: Text(
                                'Last used: ${passkey.lastUsedAt ?? '-'}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _busy
                                    ? null
                                    : () => _revokePasskey(passkey.id),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Active Devices',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_sessions.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No devices found'),
                      subtitle: Text(
                        'Device sessions will appear here after login.',
                      ),
                    ),
                  ),
                ..._sessions.map(
                  (session) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.smartphone_outlined),
                      title: Text(
                        '${session.deviceType} ${session.deviceName ?? ''}'
                            .trim(),
                      ),
                      subtitle: Text(
                        'App: ${session.appVersion ?? '-'}\nLast active: ${session.lastActiveAt ?? '-'}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: _busy
                            ? null
                            : () => _revokeDevice(session.id),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _DeviceSession {
  final int id;
  final String? deviceType;
  final String? deviceName;
  final String? appVersion;
  final bool active;
  final String? lastActiveAt;

  const _DeviceSession({
    required this.id,
    required this.deviceType,
    required this.deviceName,
    required this.appVersion,
    required this.active,
    required this.lastActiveAt,
  });

  factory _DeviceSession.fromJson(Map<String, dynamic> json) {
    return _DeviceSession(
      id: json['id'] ?? 0,
      deviceType: json['deviceType']?.toString(),
      deviceName: json['deviceName']?.toString(),
      appVersion: json['appVersion']?.toString(),
      active: json['active'] ?? false,
      lastActiveAt: json['lastActiveAt']?.toString(),
    );
  }
}

class _SecurityMethods {
  final bool mfaEnabled;
  final bool totpEnabled;
  final bool passkeyEnabled;
  final String? preferredMethod;
  final int recoveryCodesRemaining;
  final List<_PasskeySummary> passkeys;

  const _SecurityMethods({
    required this.mfaEnabled,
    required this.totpEnabled,
    required this.passkeyEnabled,
    required this.preferredMethod,
    required this.recoveryCodesRemaining,
    required this.passkeys,
  });

  factory _SecurityMethods.fromJson(Map<String, dynamic> json) {
    return _SecurityMethods(
      mfaEnabled: json['mfaEnabled'] == true,
      totpEnabled: json['totpEnabled'] == true,
      passkeyEnabled: json['passkeyEnabled'] == true,
      preferredMethod: json['preferredMethod']?.toString(),
      recoveryCodesRemaining:
          (json['recoveryCodesRemaining'] as num?)?.toInt() ?? 0,
      passkeys: (json['passkeys'] as List<dynamic>? ?? const [])
          .map((item) => _PasskeySummary.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  List<String> get availablePreferenceMethods {
    final methods = <String>[];
    if (totpEnabled) methods.add('TOTP');
    if (passkeyEnabled) methods.add('PASSKEY');
    if (recoveryCodesRemaining > 0) methods.add('RECOVERY');
    if (methods.isEmpty) methods.add('TOTP');
    return methods;
  }
}

class _PasskeySummary {
  final int id;
  final String? name;
  final String? lastUsedAt;

  const _PasskeySummary({
    required this.id,
    required this.name,
    required this.lastUsedAt,
  });

  factory _PasskeySummary.fromJson(Map<String, dynamic> json) {
    return _PasskeySummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString(),
      lastUsedAt: json['lastUsedAt']?.toString(),
    );
  }
}
