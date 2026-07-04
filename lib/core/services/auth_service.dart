import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../errors/app_error.dart';
import '../errors/passkey_error_mapper.dart';
import '../models/user.dart';
import 'ad_service.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'device_location_service.dart';
import 'notification_service.dart';
import 'contact_service.dart';
import 'premium_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'auth_refresh_token';
  static const String _userKey = 'auth_user';
  static const String _passkeyEmailKey = 'device_recorded_passkey_email';
  static const String _tenantModeKey = 'is_tenant_mode';

  static String? _token;
  static String? _refreshToken;
  static User? _currentUser;
  static bool _isTenantMode = false;
  static Completer<bool>? _refreshInFlight;

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  static final PasskeyAuthenticator _passkeyAuthenticator =
      PasskeyAuthenticator();
  static const String _bluvberryCallbackScheme = String.fromEnvironment(
    'BLUVBERRY_CALLBACK_SCHEME',
    defaultValue: 'dwelly',
  );

  static String? get token => _token;
  static User? get currentUser => _currentUser;
  static bool get isLoggedIn => _token != null && _currentUser != null;
  static bool get isTenantMode {
    if (_currentUser?.primaryRole?.toLowerCase() == 'tenant') return true;
    return _isTenantMode;
  }

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isTenantMode = prefs.getBool(_tenantModeKey) ?? false;
    _token = prefs.getString(_tokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson == null || userJson.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(userJson);
      if (decoded is Map<String, dynamic>) {
        _currentUser = User.fromJson(decoded);
        PremiumService.notifyPremiumStatusChanged();
        if (_token != null) {
          unawaited(_syncPendingLocationIfAny());
          unawaited(ContactService.loadContacts());
        }
        return;
      }
      if (decoded is Map) {
        _currentUser = User.fromJson(decoded.cast<String, dynamic>());
        PremiumService.notifyPremiumStatusChanged();
        if (_token != null) {
          unawaited(_syncPendingLocationIfAny());
          unawaited(ContactService.loadContacts());
        }
        return;
      }
      throw const FormatException('Cached user is not a JSON object');
    } catch (e) {
      // Avoid startup crash when old/corrupt auth payload exists in local storage.
      _logDebug('Auth cache restore failed; clearing stored session', e);
      _token = null;
      _refreshToken = null;
      _currentUser = null;
      await prefs.remove(_tokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userKey);
    }
  }

  static Future<bool> refreshAuthToken() async {
    // Mutex: if a refresh is already in flight, all concurrent callers
    // share the same result instead of each triggering a separate refresh
    // (which rotates the session-id and invalidates in-flight requests).
    if (_refreshInFlight != null) {
      return _refreshInFlight!.future;
    }

    if (_refreshToken == null) return false;

    _refreshInFlight = Completer<bool>();
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        await _saveAuth(authResponse);
        _refreshInFlight!.complete(true);
        return true;
      }
      // If refresh fails (expired or revoked), clear everything.
      await logout();
      _refreshInFlight!.complete(false);
      return false;
    } catch (e) {
      _logDebug('Failed to refresh token', e);
      _refreshInFlight?.complete(false);
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }

  static Future<AuthResponse> login(String email, String password, {bool forceLogin = false}) async {
    final initResult = await loginInit(email, password, forceLogin: forceLogin);
    if (initResult.status == LoginInitStatus.authenticated &&
        initResult.authResponse != null) {
      return initResult.authResponse!;
    }
    throw const AppError(
      code: AppErrorCode.unknown,
      message: 'Additional verification is required.',
    );
  }

  static Future<LoginInitResult> loginInit(
    String email,
    String password,
    {
    bool persistAuthenticatedSession = true,
    bool forceLogin = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/init'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'clientType': _resolveClientType(),
          'forceLogin': forceLogin,
        }),
      );

      if (response.statusCode == 200) {
        final result = LoginInitResult.fromJson(jsonDecode(response.body));
        if (result.status == LoginInitStatus.authenticated &&
            result.authResponse != null &&
            persistAuthenticatedSession) {
          await _saveAuth(result.authResponse!);
        }
        return result;
      }
      if (response.statusCode == 409) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['error'] == 'CONCURRENT_LOGIN_DETECTED') {
            throw AppError(
              code: AppErrorCode.concurrentLogin,
              message: decoded['message'] ?? 'You are already logged in on another device.',
              statusCode: 409,
            );
          }
        } catch (_) {}
      }
      if (response.statusCode == 401) {
        throw const AppError(
          code: AppErrorCode.authInvalidCredentials,
          message: 'Invalid email or password.',
          statusCode: 401,
        );
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Login failed. Please try again.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Login failed. Please try again.',
      );
      _logDebug('Login init error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<MfaChallenge> passkeyLoginInit(String email, {bool forceLogin = false}) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/passkey/init'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, 
          'clientType': _resolveClientType(),
          'forceLogin': forceLogin,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final challenge = MfaChallenge.fromJson(decoded);
        if (!challenge.availableMethods.contains('PASSKEY')) {
          throw const AppError.passkeyNoCredential(
            message: 'Passkey is not available for this account.',
          );
        }
        return challenge;
      }
      if (response.statusCode == 409) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['error'] == 'CONCURRENT_LOGIN_DETECTED') {
            throw AppError(
              code: AppErrorCode.concurrentLogin,
              message: decoded['message'] ?? 'You are already logged in on another device.',
              statusCode: 409,
            );
          }
        } catch (_) {}
      }

      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Passkey login could not be started.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Passkey login could not be started.',
      );
      _logDebug('Passkey login init error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<AuthResponse> completePasskeyChallenge({
    required String challengeId,
    required String challengeToken,
    bool persistSession = true,
  }) async {
    try {
      final options = await fetchPasskeyLoginOptions(
        challengeId: challengeId,
        challengeToken: challengeToken,
      );
      final rpId = options['rpId']?.toString().trim().toLowerCase();
      if (rpId == null ||
          rpId.isEmpty ||
          rpId == 'localhost' ||
          rpId == '127.0.0.1') {
        throw const AppError.passkeyDomainMismatch(
          message:
              'Passkey is not available for this app domain on this device.',
        );
      }
      final requestOptions = Map<String, dynamic>.from(options);
      final allowedCredentialIds = _extractAllowedCredentialIds(requestOptions);

      final assertion = await _authenticatePasskeyWithFallback(
        requestOptions,
        allowedCredentialIds,
      );

      return verifyPasskeyLogin(
        challengeId: challengeId,
        challengeToken: challengeToken,
        credential: assertion.toJson(),
        persistSession: persistSession,
      );
    } on PlatformException catch (e) {
      throw PasskeyErrorMapper.fromPlatformException(e);
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Passkey sign-in failed. Please try again.',
      );
      _logDebug(
        'Complete passkey challenge error',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<AuthenticateResponseType> _authenticatePasskeyWithFallback(
    Map<String, dynamic> requestOptions,
    Set<String> allowedCredentialIds,
  ) async {
    try {
      final strictImmediateRequest = AuthenticateRequestType.fromJson(
        requestOptions,
        preferImmediatelyAvailableCredentials: true,
      );
      return await _passkeyAuthenticator.authenticate(strictImmediateRequest);
    } on PlatformException catch (e) {
      if (!_isNoCredentialException(e)) rethrow;
    }

    try {
      final strictBroadenedRequest = AuthenticateRequestType.fromJson(
        requestOptions,
        preferImmediatelyAvailableCredentials: false,
      );
      return await _passkeyAuthenticator.authenticate(strictBroadenedRequest);
    } on PlatformException catch (e) {
      if (!_isNoCredentialException(e)) rethrow;
    }

    final unfilteredOptions = Map<String, dynamic>.from(requestOptions)
      ..remove('allowCredentials');
    try {
      final unfilteredRequest = AuthenticateRequestType.fromJson(
        unfilteredOptions,
        preferImmediatelyAvailableCredentials: false,
      );
      final discoveredCredential = await _passkeyAuthenticator.authenticate(
        unfilteredRequest,
      );

      if (allowedCredentialIds.isNotEmpty &&
          !_matchesAllowedCredential(
            discoveredCredential,
            allowedCredentialIds,
          )) {
        throw const AppError(
          code: AppErrorCode.passkeyNoCredential,
          message:
              'A passkey is available on this device, but it belongs to a different account email.',
        );
      }

      return discoveredCredential;
    } on PlatformException catch (e) {
      if (_isNoCredentialException(e)) {
        throw const AppError.passkeyNoCredential();
      }
      rethrow;
    }
  }

  static Future<AuthResponse> loginWithPasskey(
    String email, {
    bool persistSession = true,
    bool forceLogin = false,
  }) async {
    final challenge = await passkeyLoginInit(email, forceLogin: forceLogin);
    return completePasskeyChallenge(
      challengeId: challenge.challengeId,
      challengeToken: challenge.challengeToken,
      persistSession: persistSession,
    );
  }

  static Future<AuthResponse> verifyTotpLogin({
    required String challengeId,
    required String challengeToken,
    required String code,
    bool persistSession = true,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/verify-totp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengeId': challengeId,
          'challengeToken': challengeToken,
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Invalid authenticator code.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Invalid authenticator code.',
      );
      _logDebug('Verify TOTP login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<AuthResponse> verifyRecoveryLogin({
    required String challengeId,
    required String challengeToken,
    required String recoveryCode,
    bool persistSession = true,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/verify-recovery'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengeId': challengeId,
          'challengeToken': challengeToken,
          'recoveryCode': recoveryCode,
        }),
      );

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Invalid recovery code.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Invalid recovery code.',
      );
      _logDebug('Verify recovery login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<Map<String, dynamic>> fetchPasskeyLoginOptions({
    required String challengeId,
    required String challengeToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/passkey/options'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengeId': challengeId,
          'challengeToken': challengeToken,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Passkey options could not be loaded.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Passkey options could not be loaded.',
      );
      _logDebug(
        'Fetch passkey login options error',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<AuthResponse> verifyPasskeyLogin({
    required String challengeId,
    required String challengeToken,
    required Map<String, dynamic> credential,
    bool persistSession = true,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login/passkey/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'challengeId': challengeId,
          'challengeToken': challengeToken,
          'credential': credential,
        }),
      );

      if (response.statusCode == 200) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Passkey verification failed.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Passkey verification failed.',
      );
      _logDebug('Verify passkey login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<AuthResponse> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
          if (phone != null) 'phone': phone,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        await _saveAuth(authResponse);
        return authResponse;
      }
      if (response.statusCode == 409) {
        throw const AppError(
          code: AppErrorCode.validation,
          message: 'Email already registered.',
          statusCode: 409,
        );
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Registration failed.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Registration failed.',
      );
      _logDebug('Register error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  // ==================== Bluvberry Sign-In ====================

  static Future<AuthResponse> bluvberryLogin({bool persistSession = true}) async {
    try {
      final clientType = _resolveClientType();
      final authorizeUrl =
          '${ApiService.baseUrl}/auth/bluvberry/authorize?clientType=$clientType';

      final result = await FlutterWebAuth2.authenticate(
        url: authorizeUrl,
        callbackUrlScheme: _bluvberryCallbackScheme,
      );

      final callbackUri = Uri.parse(result);
      final code = callbackUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const AppError.server(
          message: 'Bluvberry sign-in did not return a valid code.',
        );
      }

      final redirectUri = _resolveBluvberryRedirectUri();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/bluvberry/exchange'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'clientType': clientType,
          'redirectUri': redirectUri,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Bluvberry sign-in failed.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Bluvberry sign-in failed.',
      );
      _logDebug('Bluvberry login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  // ==================== RealAdmin SSO ====================

  static Future<AuthResponse> realAdminSsoLogin({bool persistSession = true}) async {
    try {
      // Typically, an environment variable or config would dictate the RealAdmin frontend URL.
      // Pointing directly to production SSO
      const authorizeUrl = 'https://ishinadwelly.com/sso-authorize';

      final result = await FlutterWebAuth2.authenticate(
        url: authorizeUrl,
        callbackUrlScheme: 'dwelly',
      );

      final callbackUri = Uri.parse(result);
      final code = callbackUri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw const AppError.server(
          message: 'RealAdmin SSO did not return a valid code.',
        );
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/sso/exchange'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      } else {
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'RealAdmin SSO failed.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'RealAdmin SSO failed.',
      );
      _logDebug('RealAdmin SSO login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  // ==================== Google Sign-In ====================

  static Future<AuthResponse> googleLogin({bool persistSession = true, bool forceLogin = false}) async {
    try {
      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw const AppError.silentCancel(message: 'Google sign-in cancelled.');
      }

      // Get the auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw const AppError.server(
          message: 'Google sign-in could not be completed. Please try again.',
        );
      }

      // Send the ID token to backend for verification
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'forceLogin': forceLogin,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        if (persistSession) {
          await _saveAuth(authResponse);
        }
        return authResponse;
      }
      if (response.statusCode == 409) {
        try {
          final decoded = jsonDecode(response.body);
          if (decoded['error'] == 'CONCURRENT_LOGIN_DETECTED') {
            // Need to sign out of Google immediately because we aborted the Dwelly login.
            unawaited(googleSignOut());
            throw AppError(
              code: AppErrorCode.concurrentLogin,
              message: decoded['message'] ?? 'You are already logged in on another device.',
              statusCode: 409,
            );
          }
        } catch (_) {}
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Google sign-in failed.',
      );
    } on PlatformException catch (e) {
      throw _normalizeGoogleSignInException(e);
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Google sign-in failed.',
      );
      _logDebug('Google login error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<void> googleSignOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  // ==================== Email Verification ====================

  static Future<EmailCodeResponse> sendVerificationCode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/email/send-verification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      return EmailCodeResponse.fromJson(data, response.statusCode);
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Could not send verification code. Please try again.',
      );
      _logDebug('Send verification code error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<bool> verifyEmail(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/email/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        return true;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Verification failed.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Verification failed.',
      );
      _logDebug('Verify email error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  // ==================== Password Reset ====================

  static Future<EmailCodeResponse> sendPasswordResetCode(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/password/forgot'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      return EmailCodeResponse.fromJson(data, response.statusCode);
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Could not send reset code. Please try again.',
      );
      _logDebug(
        'Send password reset code error',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<bool> verifyPasswordResetCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/password/verify-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        return true;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Invalid or expired code.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Invalid or expired code.',
      );
      _logDebug(
        'Verify password reset code error',
        appError.technicalMessage ?? e,
      );
      throw appError;
    }
  }

  static Future<bool> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/password/reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Password reset failed.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Password reset failed.',
      );
      _logDebug('Reset password error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<User> updateProfile({
    required String firstName,
    required String lastName,
    String? username,
    String? phone,
    String? avatarUrl,
  }) async {
    if (_currentUser == null || _token == null) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Your session expired. Please sign in again.',
        retryable: true,
      );
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'firstName': firstName,
          'lastName': lastName,
          if (username != null) 'username': username,
          if (phone != null) 'phone': phone,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        }),
      );

      if (response.statusCode == 200) {
        final user = User.fromJson(jsonDecode(response.body));
        _currentUser = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(user.toJson()));
        return user;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update profile.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to update profile.',
      );
      _logDebug('Update profile error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  /// Update user with full user object (including location and FYP preferences)
  static Future<User> updateUser(User user) async {
    if (_currentUser == null || _token == null) {
      throw const AppError(
        code: AppErrorCode.sessionExpired,
        message: 'Your session expired. Please sign in again.',
        retryable: true,
      );
    }

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'firstName': user.firstName,
          'lastName': user.lastName,
          'phone': user.phone,
          'locationWard': user.locationWard,
          'locationConstituency': user.locationConstituency,
          'locationCounty': user.locationCounty,
          'locationAreaName': user.locationAreaName,
          'locationLatitude': user.locationLatitude,
          'locationLongitude': user.locationLongitude,
          'fypWards': user.fypWards,
          'fypNicknames': user.fypNicknames,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Merge the response with current user data (response may not have all fields)
        final updatedUser = _currentUser!.copyWith(
          firstName: data['firstName'] ?? user.firstName,
          lastName: data['lastName'] ?? user.lastName,
          phone: data['phone'],
          locationWard: data['locationWard'],
          locationConstituency: data['locationConstituency'],
          locationCounty: data['locationCounty'],
          locationAreaName: data['locationAreaName'],
          locationLatitude: data['locationLatitude']?.toDouble(),
          locationLongitude: data['locationLongitude']?.toDouble(),
          fypWards:
              (data['fypWards'] as List<dynamic>?)?.cast<String>() ??
              user.fypWards,
          fypNicknames:
              (data['fypNicknames'] as List<dynamic>?)?.cast<String>() ??
              user.fypNicknames,
          premiumStartedAt: data['premiumStartedAt'] != null
            ? DateTime.tryParse(data['premiumStartedAt'].toString())
            : _currentUser!.premiumStartedAt,
          premiumExpiresAt: data['premiumExpiresAt'] != null
            ? DateTime.tryParse(data['premiumExpiresAt'].toString())
            : _currentUser!.premiumExpiresAt,
        );
        _currentUser = updatedUser;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(updatedUser.toJson()));
        return updatedUser;
      }
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update profile.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to update profile.',
      );
      _logDebug('Update user error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<User?> refreshCurrentUser() async {
    if (_token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: ApiService.getHeaders(token: _token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = User.fromJson(data);
        _currentUser = user;
        PremiumService.notifyPremiumStatusChanged();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, jsonEncode(user.toJson()));
        return user;
      }

      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to refresh user profile.',
      );
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to refresh user profile.',
      );
      _logDebug('Refresh user error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<void> setPrimaryRole(String role) async {
    if (_token == null) throw const AppError.server(message: 'Not logged in');

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/auth/role'),
        headers: ApiService.getHeaders(token: _token),
        body: jsonEncode({'role': role}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final authResponse = AuthResponse.fromJson(jsonDecode(response.body));
        await persistAuthResponse(authResponse);
      } else {
        throw ApiService.parseHttpError(
          response,
          fallbackMessage: 'Failed to update primary role.',
        );
      }
    } catch (e) {
      final appError = ApiService.parseException(
        e,
        fallbackMessage: 'Failed to update primary role.',
      );
      _logDebug('Set primary role error', appError.technicalMessage ?? e);
      throw appError;
    }
  }

  static Future<void> setTenantMode(bool enabled) async {
    _isTenantMode = enabled;
    PremiumService.notifyPremiumStatusChanged();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tenantModeKey, enabled);
    if (isLoggedIn) {
      try {
        await setPrimaryRole(enabled ? 'tenant' : 'user');
      } catch (_) {}
    }
  }

  static Future<void> logout() async {
    final tokenToUnregister = _token;

    // Notify the backend to revoke the token if possible.
    if (_token != null && _refreshToken != null) {
      try {
        await http.post(
          Uri.parse('${ApiService.baseUrl}/auth/logout'),
          headers: ApiService.getHeaders(token: _token),
        ).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    if (tokenToUnregister != null) {
      unawaited(NotificationService.unregisterDevice(token: tokenToUnregister).catchError((_) => false));
    }
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    _isTenantMode = false;
    PremiumService.notifyPremiumStatusChanged();
    CacheManager.clearAll();
    ApiService.clearCachedGets();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_tenantModeKey);
    await googleSignOut();
  }

  static Future<void> saveDeviceRecordedPasskeyEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passkeyEmailKey, email.trim());
  }

  static Future<String?> getDeviceRecordedPasskeyEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_passkeyEmailKey);
    if (email != null && email.trim().isNotEmpty) return email.trim();
    if (_currentUser != null && _currentUser!.email.isNotEmpty) {
      return _currentUser!.email;
    }
    final rawUser = prefs.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final map = jsonDecode(rawUser) as Map<String, dynamic>;
        final e = map['email']?.toString();
        if (e != null && e.trim().isNotEmpty) return e.trim();
      } catch (_) {}
    }
    return null;
  }

  static Future<void> persistAuthResponse(AuthResponse auth) async {
    await _saveAuth(auth);
  }

  static Future<void> _saveAuth(AuthResponse auth) async {
    _token = auth.token;
    if (auth.refreshToken != null) {
      _refreshToken = auth.refreshToken;
    }
    _currentUser = auth.toUser();
    await saveDeviceRecordedPasskeyEmail(_currentUser!.email);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, auth.token);
    if (auth.refreshToken != null) {
      await prefs.setString(_refreshTokenKey, auth.refreshToken!);
    }
    await prefs.setString(_userKey, jsonEncode(_currentUser!.toJson()));
    await prefs.setString('last_login_at', DateTime.now().toIso8601String());

    // Notify premium status change so ad widgets react immediately.
    PremiumService.notifyPremiumStatusChanged();

    // Clear ad caches when a premium user logs in so stale free-tier
    // ads are not served from cache.
    if (_currentUser!.isPremiumActive) {
      try {
        final adService = await AdService.getInstance();
        await adService.clearCache();
      } catch (_) {
        // Ad service is optional; don't block login.
      }
    }

    unawaited(ContactService.loadContacts());

    // Register device for push notifications
    final fcmToken = NotificationService.fcmToken;
    if (fcmToken != null) {
      NotificationService.registerDevice(fcmToken);
    }
    await _syncPendingLocationIfAny();
    await NotificationService.syncPreferences();
  }

  static Future<void> _syncPendingLocationIfAny() async {
    if (_currentUser == null || _token == null) return;

    final pending = await DeviceLocationService.getPendingProfileLocation();
    if (pending == null || pending.isEmpty) return;

    try {
      final nextUser = _currentUser!.copyWith(
        locationWard: pending['ward']?.toString(),
        locationConstituency: pending['constituency']?.toString(),
        locationCounty: pending['county']?.toString(),
        locationAreaName: pending['areaName']?.toString(),
        locationLatitude: (pending['latitude'] as num?)?.toDouble(),
        locationLongitude: (pending['longitude'] as num?)?.toDouble(),
      );
      await updateUser(nextUser);
      await DeviceLocationService.clearPendingProfileLocation();
    } catch (e) {
      _logDebug('Deferred location sync failed', e);
    }
  }

  static String _resolveClientType() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'IOS';
      case TargetPlatform.android:
        return 'ANDROID';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'WEB';
    }
  }

  static String _resolveBluvberryRedirectUri() {
    if (kIsWeb) {
      final base = Uri.base;
      return base.replace(path: '/auth/bluvberry', query: '').toString();
    }
    return '${_bluvberryCallbackScheme}://auth/bluvberry';
  }

  static AppError _normalizeGoogleSignInException(PlatformException e) {
    final raw = '${e.code} ${e.message ?? ''}'.toLowerCase();
    if (raw.contains('sign_in_canceled') || raw.contains('cancelled')) {
      return const AppError.silentCancel(message: 'Google sign-in cancelled.');
    }
    if (raw.contains('network_error') || raw.contains('apiexception: 7')) {
      return const AppError.network(
        message:
            'Google sign-in could not reach Google Play services. Check internet and try again.',
        technicalMessage: 'Google ApiException:7 network error',
      );
    }
    if (raw.contains('apiexception: 10') || raw.contains('developer_error')) {
      return AppError.server(
        message: 'Google sign-in configuration mismatch. Contact support.',
        technicalMessage: 'Google developer error: ${e.message ?? e.code}',
      );
    }
    return AppError.server(
      message: 'Google sign-in failed. Please try again.',
      technicalMessage: '${e.code}: ${e.message}',
    );
  }

  static Set<String> _extractAllowedCredentialIds(
    Map<String, dynamic> requestOptions,
  ) {
    final rawAllowCredentials = requestOptions['allowCredentials'];
    if (rawAllowCredentials is! List) return <String>{};

    final ids = <String>{};
    for (final item in rawAllowCredentials) {
      if (item is! Map) continue;
      final id = item['id']?.toString().trim();
      if (id == null || id.isEmpty) continue;
      ids.add(_normalizeCredentialId(id));
    }
    return ids;
  }

  static bool _matchesAllowedCredential(
    AuthenticateResponseType credential,
    Set<String> allowedCredentialIds,
  ) {
    final returnedIds = <String>{
      if (credential.id.trim().isNotEmpty)
        _normalizeCredentialId(credential.id.trim()),
      if (credential.rawId.trim().isNotEmpty)
        _normalizeCredentialId(credential.rawId.trim()),
    };
    return returnedIds.any(allowedCredentialIds.contains);
  }

  static String _normalizeCredentialId(String value) =>
      value.replaceAll('=', '').trim();

  static bool _isNoCredentialException(PlatformException e) {
    final raw = '${e.code} ${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    return raw.contains('nocredentialexception') ||
        raw.contains('no credentials available') ||
        raw.contains('cannot find a matching credential') ||
        raw.contains('instance of \'nocredentialsavailableexception\'') ||
        raw.contains('28433');
  }

  static bool isPasskeyNoCredentialError(Object error) {
    if (error is AppError) {
      return error.code == AppErrorCode.passkeyNoCredential;
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('no passkey found for this email on this device') ||
        raw.contains('nocredentialsavailableexception') ||
        raw.contains('cannot find a matching credential');
  }

  static bool isPasskeyDifferentAccountError(Object error) {
    if (error is AppError) {
      return error.code == AppErrorCode.passkeyNoCredential &&
          error.message.toLowerCase().contains('different account');
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('belongs to a different account email');
  }

  static void _logDebug(String message, Object? details) {
    if (!kDebugMode) return;
    debugPrint('$message: $details');
  }
}

enum LoginInitStatus { authenticated, mfaRequired }

class LoginInitResult {
  final LoginInitStatus status;
  final AuthResponse? authResponse;
  final MfaChallenge? challenge;

  LoginInitResult({required this.status, this.authResponse, this.challenge});

  factory LoginInitResult.fromJson(Map<String, dynamic> json) {
    final statusRaw = (json['status'] ?? '').toString().toUpperCase();
    final status = statusRaw == 'MFA_REQUIRED'
        ? LoginInitStatus.mfaRequired
        : LoginInitStatus.authenticated;

    return LoginInitResult(
      status: status,
      authResponse: json['auth'] is Map<String, dynamic>
          ? AuthResponse.fromJson(json['auth'] as Map<String, dynamic>)
          : null,
      challenge: status == LoginInitStatus.mfaRequired
          ? MfaChallenge.fromJson(json)
          : null,
    );
  }
}

class MfaChallenge {
  final String challengeId;
  final String challengeToken;
  final List<String> availableMethods;
  final String? preferredMethod;
  final DateTime? expiresAt;

  MfaChallenge({
    required this.challengeId,
    required this.challengeToken,
    required this.availableMethods,
    this.preferredMethod,
    this.expiresAt,
  });

  factory MfaChallenge.fromJson(Map<String, dynamic> json) {
    final methods = (json['availableMethods'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().toUpperCase())
        .toList();
    return MfaChallenge(
      challengeId: json['challengeId']?.toString() ?? '',
      challengeToken: json['challengeToken']?.toString() ?? '',
      availableMethods: methods,
      preferredMethod: json['preferredMethod']?.toString(),
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
    );
  }
}

class EmailCodeResponse {
  final bool success;
  final String message;
  final int? expiresInMinutes;
  final int? cooldownSeconds;
  final int? cooldownRemaining;

  EmailCodeResponse({
    required this.success,
    required this.message,
    this.expiresInMinutes,
    this.cooldownSeconds,
    this.cooldownRemaining,
  });

  factory EmailCodeResponse.fromJson(
    Map<String, dynamic> json,
    int statusCode,
  ) {
    return EmailCodeResponse(
      success: json['success'] ?? (statusCode == 200),
      message: json['message'] ?? '',
      expiresInMinutes: json['expiresInMinutes'],
      cooldownSeconds: json['cooldownSeconds'],
      cooldownRemaining: json['cooldownRemaining'],
    );
  }
}
