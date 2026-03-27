import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/errors/passkey_error_mapper.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';

class SecuritySetupWizardPage extends StatefulWidget {
  const SecuritySetupWizardPage({super.key});

  @override
  State<SecuritySetupWizardPage> createState() =>
      _SecuritySetupWizardPageState();
}

class _SecuritySetupWizardPageState extends State<SecuritySetupWizardPage> {
  final PasskeyAuthenticator _passkeyAuthenticator = PasskeyAuthenticator();
  final TextEditingController _totpCodeController = TextEditingController();
  final TextEditingController _passkeyNameController = TextEditingController(
    text: 'This device',
  );

  bool _loading = true;
  bool _busy = false;
  int _currentStep = 0;

  _WizardSecurityMethods? _methods;
  String? _setupToken;
  String _setupQrPngBase64 = '';
  String _setupManualSecret = '';
  List<String> _latestRecoveryCodes = const [];

  @override
  void initState() {
    super.initState();
    _loadMethods();
  }

  @override
  void dispose() {
    _totpCodeController.dispose();
    _passkeyNameController.dispose();
    super.dispose();
  }

  Future<void> _loadMethods() async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/security/methods'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Failed to load settings'),
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _methods = _WizardSecurityMethods.fromJson(data);
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to load security settings.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startTotpSetup() async {
    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/security/totp/setup'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Unable to start TOTP setup'),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final setupToken = data['setupToken']?.toString();
      if (setupToken == null || setupToken.isEmpty) {
        throw Exception('TOTP setup token was not returned');
      }

      final otpauthUri = data['otpauthUri']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _setupToken = setupToken;
        _setupQrPngBase64 = data['qrPngBase64']?.toString() ?? '';
        _setupManualSecret =
            _extractSecretFromOtpAuthUri(otpauthUri) ??
            data['secretMasked']?.toString() ??
            '';
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Unable to start authenticator setup.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _confirmTotpSetup() async {
    if (_setupToken == null || _setupToken!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generate setup QR first')));
      return;
    }
    if (_totpCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter authenticator code')));
      return;
    }

    final token = AuthService.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/security/totp/confirm'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'setupToken': _setupToken,
          'code': _totpCodeController.text.trim(),
        }),
      );
      if (response.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(response, 'Invalid authenticator code'),
        );
      }

      _totpCodeController.clear();
      _setupToken = null;
      _setupQrPngBase64 = '';
      _setupManualSecret = '';
      await _loadMethods();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Authenticator enabled')));
      _goNext();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Invalid authenticator code.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
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
      final codes = (data['codes'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList();

      if (!mounted) return;
      setState(() {
        _latestRecoveryCodes = codes;
      });
      await _loadMethods();
      _goNext();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to regenerate recovery codes.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _registerPasskey() async {
    final token = AuthService.token;
    if (token == null) return;
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
          'name': _passkeyNameController.text.trim().isEmpty
              ? 'This device'
              : _passkeyNameController.text.trim(),
        }),
      );
      if (verifyResponse.statusCode != 200) {
        throw Exception(
          _extractErrorMessage(verifyResponse, 'Passkey registration failed'),
        );
      }

      await _loadMethods();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passkey registered')));
      _goNext();
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
      if (mounted) {
        setState(() => _busy = false);
      }
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
        throw Exception(
          _extractErrorMessage(response, 'Failed to update preferred method'),
        );
      }
      await _loadMethods();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e,
        fallbackMessage: 'Failed to update preferred method.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _goNext() {
    if (_currentStep < 4) {
      setState(() {
        _currentStep += 1;
      });
    }
  }

  bool _isTotpDone() => _methods?.totpEnabled == true;

  bool _isRecoveryDone() => (_methods?.recoveryCodesRemaining ?? 0) > 0;

  bool _isPasskeyDone() => (_methods?.passkeys.isNotEmpty ?? false);

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
      return parsed.queryParameters['secret'];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Setup Wizard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stepper(
              currentStep: _currentStep,
              onStepContinue: _goNext,
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep -= 1);
                } else {
                  Navigator.of(context).pop();
                }
              },
              controlsBuilder: (context, details) {
                return const SizedBox.shrink();
              },
              steps: [
                Step(
                  isActive: _currentStep >= 0,
                  title: const Text('Overview'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Complete these steps to secure your account: Authenticator, recovery codes, passkey, then select your preferred sign-in method.',
                      ),
                      const SizedBox(height: 10),
                      if (_currentStep == 0)
                        ElevatedButton(
                          onPressed: _goNext,
                          child: const Text('Start setup'),
                        ),
                    ],
                  ),
                ),
                Step(
                  isActive: _currentStep >= 1,
                  state: _isTotpDone() ? StepState.complete : StepState.indexed,
                  title: const Text('Authenticator (2FA)'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isTotpDone())
                        const Text('Authenticator is already enabled.')
                      else ...[
                        const Text(
                          'Set up your authenticator app by scanning the QR code.',
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _busy ? null : _startTotpSetup,
                          child: const Text('Generate QR'),
                        ),
                        if (_setupQrPngBase64.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Center(
                            child: Image.memory(
                              base64Decode(_setupQrPngBase64),
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                        if (_setupManualSecret.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Manual key',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SelectableText(
                            _setupManualSecret,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _totpCodeController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Enter 6-digit code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _busy ? null : _confirmTotpSetup,
                          child: const Text('Confirm Authenticator'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_currentStep == 1)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_isTotpDone())
                              ElevatedButton(
                                onPressed: _goNext,
                                child: const Text('Continue'),
                              )
                            else
                              OutlinedButton(
                                onPressed: _busy ? null : _goNext,
                                child: const Text('Skip for now'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Step(
                  isActive: _currentStep >= 2,
                  state: _isRecoveryDone()
                      ? StepState.complete
                      : StepState.indexed,
                  title: const Text('Recovery Codes'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Codes remaining: ${_methods?.recoveryCodesRemaining ?? 0}',
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _busy ? null : _regenerateRecoveryCodes,
                        child: Text(
                          _isRecoveryDone()
                              ? 'Regenerate Recovery Codes'
                              : 'Generate Recovery Codes',
                        ),
                      ),
                      if (_latestRecoveryCodes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._latestRecoveryCodes.asMap().entries.map(
                                (entry) => Text(
                                  '${entry.key + 1}. ${entry.value}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
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
                                        ClipboardData(
                                          text: _latestRecoveryCodes.join('\n'),
                                        ),
                                      );
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Copied to clipboard'),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy),
                                    label: const Text('Copy'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      try {
                                        final path =
                                            await _downloadRecoveryCodes(
                                              _latestRecoveryCodes,
                                            );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Saved to $path'),
                                          ),
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
                      ],
                      const SizedBox(height: 8),
                      if (_currentStep == 2)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_isRecoveryDone())
                              ElevatedButton(
                                onPressed: _goNext,
                                child: const Text('Continue'),
                              )
                            else
                              OutlinedButton(
                                onPressed: _busy ? null : _goNext,
                                child: const Text('Skip for now'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                Step(
                  isActive: _currentStep >= 3,
                  state: _isPasskeyDone()
                      ? StepState.complete
                      : StepState.indexed,
                  title: const Text('Passkey'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Register passkey on this device for fast sign in.',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passkeyNameController,
                        decoration: const InputDecoration(
                          labelText: 'Passkey name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _busy ? null : _registerPasskey,
                        icon: const Icon(Icons.key_outlined),
                        label: const Text('Register Passkey'),
                      ),
                      if ((_methods?.passkeys ?? const []).isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Registered passkeys',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ...(_methods?.passkeys ?? const []).map(
                          (passkey) => Text('• ${passkey.name ?? "Passkey"}'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_currentStep == 3)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_isPasskeyDone())
                              ElevatedButton(
                                onPressed: _goNext,
                                child: const Text('Continue'),
                              )
                            OutlinedButton(
                              onPressed: _busy ? null : _goNext,
                              child: const Text('Skip for now'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Step(
                  isActive: _currentStep >= 4,
                  title: const Text('Preferred Method'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose which method should be preferred on your next login.',
                      ),
                      const SizedBox(height: 10),
                      if (_methods != null)
                        DropdownButtonFormField<String>(
                          initialValue: _methods!.selectedPreferredMethod,
                          decoration: const InputDecoration(
                            labelText: 'Preferred method',
                            border: OutlineInputBorder(),
                          ),
                          items: _methods!.availablePreferenceMethods
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  _updatePreferredMethod(value);
                                },
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(true),
                          child: const Text('Finish Setup'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _WizardSecurityMethods {
  final bool totpEnabled;
  final bool passkeyEnabled;
  final String? preferredMethod;
  final int recoveryCodesRemaining;
  final List<_WizardPasskeySummary> passkeys;

  const _WizardSecurityMethods({
    required this.totpEnabled,
    required this.passkeyEnabled,
    required this.preferredMethod,
    required this.recoveryCodesRemaining,
    required this.passkeys,
  });

  factory _WizardSecurityMethods.fromJson(Map<String, dynamic> json) {
    return _WizardSecurityMethods(
      totpEnabled: json['totpEnabled'] == true,
      passkeyEnabled: json['passkeyEnabled'] == true,
      preferredMethod: json['preferredMethod']?.toString(),
      recoveryCodesRemaining:
          (json['recoveryCodesRemaining'] as num?)?.toInt() ?? 0,
      passkeys: (json['passkeys'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                _WizardPasskeySummary.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  List<String> get availablePreferenceMethods {
    final methods = <String>[];
    if (totpEnabled) methods.add('TOTP');
    if (passkeyEnabled || passkeys.isNotEmpty) methods.add('PASSKEY');
    if (recoveryCodesRemaining > 0) methods.add('RECOVERY');
    if (methods.isEmpty) methods.add('TOTP');
    return methods;
  }

  String get selectedPreferredMethod {
    if (preferredMethod != null &&
        availablePreferenceMethods.contains(preferredMethod)) {
      return preferredMethod!;
    }
    return availablePreferenceMethods.first;
  }
}

class _WizardPasskeySummary {
  final String? name;

  const _WizardPasskeySummary({required this.name});

  factory _WizardPasskeySummary.fromJson(Map<String, dynamic> json) {
    return _WizardPasskeySummary(name: json['name']?.toString());
  }
}
