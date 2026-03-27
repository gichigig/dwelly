import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import '../models/advertisement.dart';
import '../services/ad_service.dart';
import 'video_ad_player.dart';
import 'ad_form_modal.dart';

/// Full-screen ad screen shown on app launch
class AppLaunchAdScreen extends StatefulWidget {
  final Advertisement ad;
  final AdService adService;
  final VoidCallback onComplete;
  final String? county;
  final String? constituency;
  final AdPlacement placement;
  final bool markLaunchAdShownOnComplete;
  final bool skipEnabled;
  final int? skipDelayOverrideSeconds;
  final Duration? autoAdvanceAfter;
  final String? breakId;
  final int? breakStepIndex;

  const AppLaunchAdScreen({
    super.key,
    required this.ad,
    required this.adService,
    required this.onComplete,
    this.county,
    this.constituency,
    this.placement = AdPlacement.APP_LAUNCH,
    this.markLaunchAdShownOnComplete = true,
    this.skipEnabled = true,
    this.skipDelayOverrideSeconds,
    this.autoAdvanceAfter,
    this.breakId,
    this.breakStepIndex,
  });

  @override
  State<AppLaunchAdScreen> createState() => _AppLaunchAdScreenState();
}

class _AppLaunchAdScreenState extends State<AppLaunchAdScreen> {
  Timer? _skipTimer;
  Timer? _autoAdvanceTimer;
  int _skipCountdown = 5;
  bool _canSkip = false;
  bool _impressionRecorded = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _skipCountdown = widget.skipDelayOverrideSeconds ?? widget.ad.skipDelaySeconds ?? 5;
    _startSkipTimerIfNeeded();
    _startAutoAdvanceIfNeeded();
    _recordImpression();
  }

  String get _placementName => widget.placement.name;

  @override
  void dispose() {
    _skipTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    super.dispose();
  }

  void _startSkipTimerIfNeeded() {
    if (!widget.skipEnabled) {
      _canSkip = false;
      return;
    }
    _skipTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_skipCountdown > 0) {
          _skipCountdown--;
        } else {
          _canSkip = true;
          timer.cancel();
        }
      });
    });
  }

  void _startAutoAdvanceIfNeeded() {
    if (widget.autoAdvanceAfter == null) return;
    _autoAdvanceTimer = Timer(widget.autoAdvanceAfter!, () {
      if (!mounted) return;
      _complete(skipped: false);
    });
  }

  void _recordImpression() {
    if (!_impressionRecorded) {
      _impressionRecorded = true;
      widget.adService.recordAnalyticsEvent(
        adId: widget.ad.id,
        eventType: 'IMPRESSION',
        county: widget.county,
        constituency: widget.constituency,
        placement: _placementName,
        breakId: widget.breakId,
        breakStepIndex: widget.breakStepIndex,
      );
    }
  }

  void _complete({required bool skipped}) {
    if (_completed) return;
    _completed = true;
    _skipTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    if (skipped) {
      widget.adService.recordAnalyticsEvent(
        adId: widget.ad.id,
        eventType: 'SKIP',
        county: widget.county,
        constituency: widget.constituency,
        placement: _placementName,
        breakId: widget.breakId,
        breakStepIndex: widget.breakStepIndex,
      );
    }
    if (widget.markLaunchAdShownOnComplete) {
      widget.adService.markLaunchAdShown();
    }
    widget.onComplete();
  }

  void _handleSkip() {
    _complete(skipped: true);
  }

  Future<void> _handleTap() async {
    widget.adService.recordAnalyticsEvent(
      adId: widget.ad.id,
      eventType: 'CLICK',
      county: widget.county,
      constituency: widget.constituency,
      placement: _placementName,
      breakId: widget.breakId,
      breakStepIndex: widget.breakStepIndex,
    );

    switch (widget.ad.linkType) {
      case LinkType.WEBSITE:
        if (widget.ad.targetUrl != null) {
          await _launchUrl(widget.ad.targetUrl!);
        }
        break;
      case LinkType.PLAYSTORE:
        if (widget.ad.playStoreUrl != null) {
          widget.adService.recordAnalyticsEvent(
            adId: widget.ad.id,
            eventType: 'PLAY_STORE_CLICK',
            placement: _placementName,
            breakId: widget.breakId,
            breakStepIndex: widget.breakStepIndex,
          );
          await _launchUrl(widget.ad.playStoreUrl!);
        }
        break;
      case LinkType.APPSTORE:
        if (widget.ad.appStoreUrl != null) {
          widget.adService.recordAnalyticsEvent(
            adId: widget.ad.id,
            eventType: 'APP_STORE_CLICK',
            placement: _placementName,
            breakId: widget.breakId,
            breakStepIndex: widget.breakStepIndex,
          );
          await _launchUrl(widget.ad.appStoreUrl!);
        }
        break;
      case LinkType.APP_BOTH:
        _showStoreSelector();
        break;
      case LinkType.FORM:
        _showForm();
        break;
      case LinkType.NONE:
        break;
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Silently fail
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
              if (widget.ad.playStoreUrl != null && Platform.isAndroid)
                ListTile(
                  leading: const Icon(
                    Icons.android,
                    size: 40,
                    color: Colors.green,
                  ),
                  title: const Text('Google Play Store'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.adService.recordAnalyticsEvent(
                      adId: widget.ad.id,
                      eventType: 'PLAY_STORE_CLICK',
                      placement: _placementName,
                      breakId: widget.breakId,
                      breakStepIndex: widget.breakStepIndex,
                    );
                    _launchUrl(widget.ad.playStoreUrl!);
                  },
                ),
              if (widget.ad.appStoreUrl != null && Platform.isIOS)
                ListTile(
                  leading: const Icon(Icons.apple, size: 40),
                  title: const Text('App Store'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.adService.recordAnalyticsEvent(
                      adId: widget.ad.id,
                      eventType: 'APP_STORE_CLICK',
                      placement: _placementName,
                      breakId: widget.breakId,
                      breakStepIndex: widget.breakStepIndex,
                    );
                    _launchUrl(widget.ad.appStoreUrl!);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForm() {
    if (widget.ad.formSchema == null) return;
    widget.adService.recordAnalyticsEvent(
      adId: widget.ad.id,
      eventType: 'FORM_OPEN',
      placement: _placementName,
      breakId: widget.breakId,
      breakStepIndex: widget.breakStepIndex,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AdFormModal(
        ad: widget.ad,
        adService: widget.adService,
        onSuccess: () {
          widget.adService.recordAnalyticsEvent(
            adId: widget.ad.id,
            eventType: 'FORM_SUBMIT',
            placement: _placementName,
            breakId: widget.breakId,
            breakStepIndex: widget.breakStepIndex,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Ad content
            GestureDetector(onTap: _handleTap, child: _buildAdContent()),

            // Sponsored label (top left)
            if (widget.ad.sponsored)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SPONSORED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

            // Skip button (top right)
            if (widget.skipEnabled)
              Positioned(top: 16, right: 16, child: _buildSkipButton()),

            // Bottom info bar
            Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomBar()),
          ],
        ),
      ),
    );
  }

  Widget _buildAdContent() {
    if (widget.ad.mediaType == MediaType.VIDEO && widget.ad.videoUrl != null) {
      return VideoAdPlayer(
        ad: widget.ad,
        adService: widget.adService,
        autoPlay: true,
        showControls: false,
        onComplete: () {
          widget.adService.recordAnalyticsEvent(
            adId: widget.ad.id,
            eventType: 'VIDEO_COMPLETE',
            placement: _placementName,
            breakId: widget.breakId,
            breakStepIndex: widget.breakStepIndex,
          );
        },
      );
    }

    // Image ad
    return widget.ad.imageUrl != null
        ? CachedNetworkImage(
            imageUrl: widget.ad.imageUrl!,
            fit: BoxFit.contain,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (context, url, error) => const Center(
              child: Icon(Icons.error, color: Colors.white, size: 48),
            ),
          )
        : const Center(
            child: Icon(Icons.ad_units, color: Colors.white54, size: 64),
          );
  }

  Widget _buildSkipButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: _canSkip ? Colors.white : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _canSkip ? _handleSkip : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _canSkip ? 'Skip' : 'Skip in $_skipCountdown',
                  style: TextStyle(
                    color: _canSkip ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_canSkip) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: _canSkip ? Colors.black : Colors.white70,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Advertiser info
          Row(
            children: [
              if (widget.ad.advertiserLogoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: widget.ad.advertiserLogoUrl!,
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(width: 24, height: 24, color: Colors.grey),
                    errorWidget: (context, url, error) => const SizedBox(),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                widget.ad.advertiserName,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (widget.ad.advertiserVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: Colors.blue, size: 14),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Title
          Text(
            widget.ad.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Description
          if (widget.ad.description != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.ad.description!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // Location instructions
          if (widget.ad.locationInstructions != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.ad.locationInstructions!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          // CTA button
          if (widget.ad.linkType != LinkType.NONE) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(_getCtaText()),
              ),
            ),
          ],
        ],
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
        return 'Download App';
      case LinkType.FORM:
        return widget.ad.formSubmitButtonText ?? 'Get Started';
      case LinkType.NONE:
        return '';
    }
  }
}
