import 'package:flutter/material.dart';

import 'error_mapper.dart';

String userErrorMessage(
  Object error, {
  String fallbackMessage = 'Something went wrong. Please try again.',
}) {
  return ErrorMapper.userMessage(error, fallbackMessage: fallbackMessage);
}

bool isSilentError(Object error) => ErrorMapper.isSilent(error);

void showErrorSnackBar(
  BuildContext context,
  Object error, {
  String fallbackMessage = 'Something went wrong. Please try again.',
  SnackBarAction? action,
}) {
  if (isSilentError(error)) return;
  final message = userErrorMessage(error, fallbackMessage: fallbackMessage);
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message), action: action));
}
