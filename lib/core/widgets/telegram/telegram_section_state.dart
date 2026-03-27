import 'package:flutter/material.dart';

class TelegramSectionState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const TelegramSectionState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  const TelegramSectionState.empty({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
         key: key,
         icon: Icons.inbox_outlined,
         title: title,
         subtitle: subtitle,
         actionLabel: actionLabel,
         onAction: onAction,
       );

  const TelegramSectionState.error({
    Key? key,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) : this(
         key: key,
         icon: Icons.error_outline,
         title: title,
         subtitle: subtitle,
         actionLabel: actionLabel,
         onAction: onAction,
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 50, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
