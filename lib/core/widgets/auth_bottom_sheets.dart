import 'package:flutter/material.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../errors/ui_error.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

bool _isAuthSheetOpen = false;

Future<void> showLoginBottomSheet(
  BuildContext context, {
  required VoidCallback onSuccess,
}) {
  if (_isAuthSheetOpen) {
    return Future.value();
  }
  _isAuthSheetOpen = true;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SharedLoginForm(
      onSuccess: () {
        if (Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
        onSuccess();
      },
    ),
  ).whenComplete(() => _isAuthSheetOpen = false);
}

Future<void> showSignupBottomSheet(
  BuildContext context, {
  required VoidCallback onSuccess,
}) {
  if (_isAuthSheetOpen) {
    return Future.value();
  }
  _isAuthSheetOpen = true;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SharedSignupForm(
      onSuccess: () {
        if (Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
        onSuccess();
      },
    ),
  ).whenComplete(() => _isAuthSheetOpen = false);
}

class SharedLoginForm extends StatefulWidget {
  final VoidCallback onSuccess;

  const SharedLoginForm({super.key, required this.onSuccess});

  @override
  State<SharedLoginForm> createState() => _SharedLoginFormState();
}

class _SharedLoginFormState extends State<SharedLoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _mfaCodeController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isMfaLoading = false;
  String? _error;
  MfaChallenge? _mfaChallenge;
  String _selectedMfaMethod = 'TOTP';

  bool _requiresAccountChoice(AuthResponse authResponse) {
    final role = authResponse.role.toUpperCase();
    return role == 'ADMIN' || role == 'SUPER_ADMIN';
  }

  void _resetToPrimaryLogin() {
    _mfaCodeController.clear();
    _passwordController.clear();
    setState(() {
      _mfaChallenge = null;
      _selectedMfaMethod = 'TOTP';
      _error = null;
    });
  }

  Future<bool?> _showAdminAccountChoice(AuthResponse authResponse) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Admin account detected'),
        content: Text(
          '${authResponse.email} is an admin account. '
          'Do you want to use this same account in the Flutter app, or sign in with a different account instead?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Use Different Account'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use Current Account'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeAuthenticatedLogin(AuthResponse authResponse) async {
    if (_requiresAccountChoice(authResponse)) {
      final useCurrent = await _showAdminAccountChoice(authResponse);
      if (!mounted) return;
      if (useCurrent != true) {
        _resetToPrimaryLogin();
        return;
      }
    }

    await AuthService.persistAuthResponse(authResponse);
    if (!mounted) return;
    widget.onSuccess();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _mfaCodeController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await AuthService.loginInit(
        _emailController.text.trim(),
        _passwordController.text,
        persistAuthenticatedSession: false,
      );

      if (result.status == LoginInitStatus.authenticated) {
        if (result.authResponse == null) {
          throw Exception('Login response is missing authentication details');
        }
        await _completeAuthenticatedLogin(result.authResponse!);
        return;
      }

      if (result.challenge == null) {
        throw Exception('MFA challenge is missing');
      }

      setState(() {
        _mfaChallenge = result.challenge;
        _selectedMfaMethod =
            result.challenge!.preferredMethod ??
            result.challenge!.availableMethods.first;
      });
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Login failed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _googleLogin() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      final authResponse = await AuthService.googleLogin(persistSession: false);
      await _completeAuthenticatedLogin(authResponse);
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Google sign-in failed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _startPasskeyWithEmailPrompt() async {
    final email = await _showPasskeyEmailPrompt();
    if (!mounted || email == null) return;

    setState(() {
      _isMfaLoading = true;
      _error = null;
      _emailController.text = email;
    });

    try {
      final authResponse = await AuthService.loginWithPasskey(
        email,
        persistSession: false,
      );
      await _completeAuthenticatedLogin(authResponse);
    } catch (e) {
      if (!mounted) return;
      final noCredential = AuthService.isPasskeyNoCredentialError(e);
      final differentAccount = AuthService.isPasskeyDifferentAccountError(e);
      final message = userErrorMessage(
        e,
        fallbackMessage: 'Passkey sign-in failed. Please try again.',
      );

      if (noCredential || differentAccount) {
        final fallbackMessage = differentAccount
            ? 'A passkey is available on this device, but it belongs to a different account email.\nUse password sign-in, then register passkey for this email.'
            : 'No passkey found for this email on this device.\nUse password sign-in, then register passkey again on this phone.';
        final title = differentAccount
            ? 'Passkey belongs to another account'
            : 'No passkey found on this device';
        final usePassword = await _showPasskeyNoCredentialFallback(
          email,
          title,
          fallbackMessage,
        );
        if (!mounted) return;

        setState(() {
          _error = fallbackMessage;
        });

        if (usePassword == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            FocusScope.of(context).requestFocus(_passwordFocusNode);
          });
        }
      } else {
        if (isSilentError(e)) return;
        setState(() {
          _error = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMfaLoading = false;
        });
      }
    }
  }

  Future<String?> _showPasskeyEmailPrompt() async {
    return showDialog<String>(
      context: context,
      builder: (_) => _PasskeyEmailPromptDialog(
        initialEmail: _emailController.text.trim(),
      ),
    );
  }

  Future<bool?> _showPasskeyNoCredentialFallback(
    String email,
    String title,
    String helperMessage,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: TextStyle(color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text(helperMessage),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use Password Instead'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyMfa() async {
    if (_mfaChallenge == null) return;
    if (_selectedMfaMethod != 'PASSKEY' &&
        _mfaCodeController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your verification code');
      return;
    }

    setState(() {
      _isMfaLoading = true;
      _error = null;
    });

    try {
      late final AuthResponse authResponse;
      switch (_selectedMfaMethod) {
        case 'TOTP':
          authResponse = await AuthService.verifyTotpLogin(
            challengeId: _mfaChallenge!.challengeId,
            challengeToken: _mfaChallenge!.challengeToken,
            code: _mfaCodeController.text.trim(),
            persistSession: false,
          );
          break;
        case 'RECOVERY':
          authResponse = await AuthService.verifyRecoveryLogin(
            challengeId: _mfaChallenge!.challengeId,
            challengeToken: _mfaChallenge!.challengeToken,
            recoveryCode: _mfaCodeController.text.trim(),
            persistSession: false,
          );
          break;
        case 'PASSKEY':
          authResponse = await AuthService.completePasskeyChallenge(
            challengeId: _mfaChallenge!.challengeId,
            challengeToken: _mfaChallenge!.challengeToken,
            persistSession: false,
          );
          break;
        default:
          throw Exception('Unsupported MFA method');
      }

      await _completeAuthenticatedLogin(authResponse);
      return;
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Verification failed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isMfaLoading = false;
        });
      }
    }
  }

  String _mfaLabel(String method) {
    switch (method) {
      case 'PASSKEY':
        return 'Passkey';
      case 'RECOVERY':
        return 'Recovery Code';
      case 'TOTP':
      default:
        return 'Authenticator Code';
    }
  }

  @override
  Widget build(BuildContext context) {
    final requiresMfa = _mfaChallenge != null;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    'Sign In',
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
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: true,
                    enabled: !requiresMfa,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  if (!requiresMfa)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed:
                            (_isLoading || _isGoogleLoading || _isMfaLoading)
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordScreen(
                                      initialEmail: _emailController.text
                                          .trim(),
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  if (requiresMfa) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedMfaMethod,
                      decoration: InputDecoration(
                        labelText: 'Verification Method',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: _mfaChallenge!.availableMethods
                          .map(
                            (method) => DropdownMenuItem(
                              value: method,
                              child: Text(_mfaLabel(method)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedMfaMethod = value;
                          _mfaCodeController.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_selectedMfaMethod != 'PASSKEY')
                      TextFormField(
                        controller: _mfaCodeController,
                        decoration: InputDecoration(
                          labelText: _selectedMfaMethod == 'RECOVERY'
                              ? 'Recovery Code'
                              : 'Authenticator Code',
                          prefixIcon: const Icon(Icons.password),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Use your device passkey prompt to verify this sign in.',
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isLoading || _isMfaLoading)
                          ? null
                          : requiresMfa
                          ? _verifyMfa
                          : _login,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: (_isLoading || _isMfaLoading)
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              requiresMfa ? 'Verify & Sign In' : 'Sign In',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  if (!requiresMfa) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            (_isLoading || _isGoogleLoading || _isMfaLoading)
                            ? null
                            : _googleLogin,
                        icon: _isGoogleLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Image.network(
                                'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                height: 20,
                                width: 20,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.g_mobiledata, size: 24),
                              ),
                        label: const Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed:
                            (_isLoading || _isGoogleLoading || _isMfaLoading)
                            ? null
                            : _startPasskeyWithEmailPrompt,
                        icon: const Icon(Icons.key_outlined),
                        label: const Text(
                          'Sign In with Passkey',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasskeyEmailPromptDialog extends StatefulWidget {
  final String initialEmail;

  const _PasskeyEmailPromptDialog({required this.initialEmail});

  @override
  State<_PasskeyEmailPromptDialog> createState() =>
      _PasskeyEmailPromptDialogState();
}

class _PasskeyEmailPromptDialogState extends State<_PasskeyEmailPromptDialog> {
  late final TextEditingController _controller;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _continue() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _inputError = 'Email is required');
      return;
    }
    if (!trimmed.contains('@')) {
      setState(() => _inputError = 'Enter a valid email');
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Continue with Passkey'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) {
          if (_inputError != null) {
            setState(() => _inputError = null);
          }
        },
        decoration: InputDecoration(
          labelText: 'Email',
          border: const OutlineInputBorder(),
          errorText: _inputError,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _continue, child: const Text('Continue')),
      ],
    );
  }
}

class SharedSignupForm extends StatefulWidget {
  final VoidCallback onSuccess;

  const SharedSignupForm({super.key, required this.onSuccess});

  @override
  State<SharedSignupForm> createState() => _SharedSignupFormState();
}

class _SharedSignupFormState extends State<SharedSignupForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _error;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _googleLogin() async {
    setState(() {
      _isGoogleLoading = true;
      _error = null;
    });

    try {
      await AuthService.googleLogin();
      widget.onSuccess();
    } catch (e) {
      if (!mounted || isSilentError(e)) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Google sign-in failed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await AuthService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
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
          fallbackMessage: 'Signup failed. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
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
                    'Create Account',
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
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signup,
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
                              'Create Account',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_isLoading || _isGoogleLoading)
                          ? null
                          : _googleLogin,
                      icon: _isGoogleLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Image.network(
                              'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                              height: 20,
                              width: 20,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.g_mobiledata, size: 24),
                            ),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
