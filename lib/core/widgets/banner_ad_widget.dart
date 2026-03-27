import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../models/advertisement.dart';
import '../services/ad_service.dart';

/// Widget for displaying banner-style image ads
class BannerAdWidget extends StatefulWidget {
  final Advertisement ad;
  final AdService adService;
  final double height;
  final BorderRadius? borderRadius;
  final VoidCallback? onFormTap;

  const BannerAdWidget({
    super.key,
    required this.ad,
    required this.adService,
    this.height = 120,
    this.borderRadius,
    this.onFormTap,
  });

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  bool _impressionRecorded = false;

  @override
  void initState() {
    super.initState();
    _recordImpression();
  }

  void _recordImpression() {
    if (!_impressionRecorded) {
      _impressionRecorded = true;
      widget.adService.recordImpression(widget.ad.id);
    }
  }

  Future<void> _handleTap() async {
    widget.adService.recordClick(widget.ad.id);

    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        if (widget.ad.targetUrl != null) {
          await _launchUrl(widget.ad.targetUrl!);
        }
        break;
      case LinkType.PLAYSTORE:
        if (widget.ad.playStoreUrl != null) {
          await _launchUrl(widget.ad.playStoreUrl!);
        }
        break;
      case LinkType.APPSTORE:
        if (widget.ad.appStoreUrl != null) {
          await _launchUrl(widget.ad.appStoreUrl!);
        }
        break;
      case LinkType.APP_BOTH:
        _showStoreSelector();
        break;
      case LinkType.FORM:
        widget.onFormTap?.call();
        break;
      case LinkType.NONE:
        break;
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showStoreSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Download App',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              if (widget.ad.playStoreUrl != null)
                ListTile(
                  leading: Image.asset(
                    'assets/images/google_play.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(Icons.android, size: 40),
                  ),
                  title: const Text('Google Play Store'),
                  subtitle: const Text('For Android devices'),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUrl(widget.ad.playStoreUrl!);
                  },
                ),
              if (widget.ad.appStoreUrl != null)
                ListTile(
                  leading: Image.asset(
                    'assets/images/app_store.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(Icons.apple, size: 40),
                  ),
                  title: const Text('App Store'),
                  subtitle: const Text('For iOS devices'),
                  onTap: () {
                    Navigator.pop(context);
                    _launchUrl(widget.ad.appStoreUrl!);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.ad.linkType != LinkType.NONE ? _handleTap : null,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              CachedNetworkImage(
                imageUrl: widget.ad.imageUrl ?? '',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[200],
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
              // Gradient overlay for text visibility
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.ad.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.ad.description != null)
                              Text(
                                widget.ad.description!,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Call to action indicator
                      if (widget.ad.linkType != LinkType.NONE)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getCtaText(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Ad label and verification badge
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Verification badge (only for verified advertisers)
                    if (widget.ad.advertiserVerified)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 12),
                            SizedBox(width: 2),
                            Text(
                              'VERIFIED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // AD label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'AD',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCtaText() {
    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        return 'Learn More';
      case LinkType.PLAYSTORE:
      case LinkType.APPSTORE:
      case LinkType.APP_BOTH:
        return 'Download';
      case LinkType.FORM:
        return 'Sign Up';
      case LinkType.NONE:
        return '';
    }
  }
}
