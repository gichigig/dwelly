import 'package:flutter/material.dart';

class TelegramListRowTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? meta;
  final String? trailingTopText;
  final int badgeCount;
  final String? imageUrl;
  final IconData? leadingIcon;
  final String? avatarText;
  final Color? avatarColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? bottom;
  final EdgeInsetsGeometry margin;

  const TelegramListRowTile({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.trailingTopText,
    this.badgeCount = 0,
    this.imageUrl,
    this.leadingIcon,
    this.avatarText,
    this.avatarColor,
    this.onTap,
    this.trailing,
    this.bottom,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: hasImage
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, __) =>
                              _buildAvatarFallback(context),
                        )
                      : _buildAvatarFallback(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (meta != null && meta!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (bottom != null) ...[const SizedBox(height: 8), bottom!],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (trailingTopText != null &&
                        trailingTopText!.trim().isNotEmpty)
                      Text(
                        trailingTopText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (badgeCount > 0) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : badgeCount.toString(),
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        avatarColor ?? theme.colorScheme.primary.withValues(alpha: 0.22);
    final content = (avatarText != null && avatarText!.trim().isNotEmpty)
        ? Text(
            avatarText!.trim().substring(0, 1).toUpperCase(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          )
        : Icon(
            leadingIcon ?? Icons.person,
            color: theme.colorScheme.onSurfaceVariant,
            size: 24,
          );
    return Container(
      color: background,
      child: Center(child: content),
    );
  }
}
