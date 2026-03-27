enum AppErrorCode {
  authInvalidCredentials,
  network,
  timeout,
  sessionExpired,
  forbidden,
  validation,
  notFound,
  rateLimited,
  server,
  passkeyNoCredential,
  passkeyDomainMismatch,
  userCancelled,
  unknown,
}

class AppError implements Exception {
  final AppErrorCode code;
  final String message;
  final int? statusCode;
  final bool retryable;
  final bool silent;
  final String? technicalMessage;

  const AppError({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryable = false,
    this.silent = false,
    this.technicalMessage,
  });

  const AppError.network({
    String message =
        'Could not reach the server. Check your connection and try again.',
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.network,
         message: message,
         retryable: true,
         technicalMessage: technicalMessage,
       );

  const AppError.timeout({
    String message =
        'Could not reach the server. Check your connection and try again.',
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.timeout,
         message: message,
         retryable: true,
         technicalMessage: technicalMessage,
       );

  const AppError.server({
    String message = 'Something went wrong. Please try again.',
    int? statusCode,
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.server,
         message: message,
         statusCode: statusCode,
         retryable: true,
         technicalMessage: technicalMessage,
       );

  const AppError.silentCancel({
    String message = 'Request cancelled.',
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.userCancelled,
         message: message,
         silent: true,
         technicalMessage: technicalMessage,
       );

  const AppError.passkeyNoCredential({
    String message =
        'No passkey found for this email on this device. Use password sign-in, then register passkey again.',
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.passkeyNoCredential,
         message: message,
         technicalMessage: technicalMessage,
       );

  const AppError.passkeyDomainMismatch({
    String message =
        'Passkey is not available for this app domain on this device.',
    String? technicalMessage,
  }) : this(
         code: AppErrorCode.passkeyDomainMismatch,
         message: message,
         technicalMessage: technicalMessage,
       );

  bool get isSessionExpired => code == AppErrorCode.sessionExpired;

  @override
  String toString() => message;
}
