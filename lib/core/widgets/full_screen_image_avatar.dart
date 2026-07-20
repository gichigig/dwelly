import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import 'full_screen_image_view.dart';

class FullScreenImageAvatar extends StatelessWidget {
  final String? avatarUrl;
  final Widget? fallbackWidget;
  final double radius;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const FullScreenImageAvatar({
    super.key,
    this.avatarUrl,
    this.fallbackWidget,
    this.radius = 24.0,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final validUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    final resolvedUrl = validUrl
        ? ApiService.resolveMediaUrl(avatarUrl!)
        : null;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor:
          backgroundColor ?? Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: resolvedUrl != null
          ? CachedNetworkImageProvider(resolvedUrl) as ImageProvider
          : null,
      child: resolvedUrl == null ? fallbackWidget : null,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }

    if (resolvedUrl == null) {
      return avatar;
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FullScreenImageView(imageUrl: resolvedUrl),
          ),
        );
      },
      child: avatar,
    );
  }
}
