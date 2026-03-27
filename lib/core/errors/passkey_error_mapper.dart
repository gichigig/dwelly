import 'package:flutter/services.dart';

import 'app_error.dart';

class PasskeyErrorMapper {
  static AppError fromPlatformException(PlatformException e) {
    final raw = '${e.code} ${e.message ?? ''} ${e.details ?? ''}'
        .toLowerCase()
        .trim();

    if (_isUserCancelled(raw)) {
      return AppError.silentCancel(
        technicalMessage: 'Passkey cancelled: ${e.code} ${e.message}',
      );
    }

    if (_isNoCredential(raw)) {
      return AppError.passkeyNoCredential(
        technicalMessage: 'No credential: ${e.code} ${e.message}',
      );
    }

    if (_isDomainMismatch(raw)) {
      return AppError.passkeyDomainMismatch(
        technicalMessage: 'Domain mismatch: ${e.code} ${e.message}',
      );
    }

    return AppError.server(
      message: 'Passkey sign-in failed. Please try again.',
      technicalMessage: '${e.code}: ${e.message} ${e.details}',
    );
  }

  static bool isSilentCancel(Object error) =>
      error is AppError && error.code == AppErrorCode.userCancelled;

  static bool _isUserCancelled(String raw) {
    return raw.contains('notallowederror') ||
        raw.contains('request was aborted') ||
        raw.contains('aborted') ||
        raw.contains('cancel') ||
        raw.contains('timed out') ||
        raw.contains('timeout');
  }

  static bool _isNoCredential(String raw) {
    return raw.contains('nocredentialexception') ||
        raw.contains('no credentials available') ||
        raw.contains('cannot find a matching credential') ||
        raw.contains('28433');
  }

  static bool _isDomainMismatch(String raw) {
    return raw.contains('type_security_error') ||
        raw.contains('cannot be validated') ||
        raw.contains('relying party id') ||
        raw.contains('cross-origin') ||
        raw.contains('.well-known/webauthn');
  }
}
