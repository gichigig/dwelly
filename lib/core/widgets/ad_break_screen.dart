import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/advertisement.dart';
import '../services/ad_service.dart';
import 'app_launch_ad_screen.dart';

class AdBreakScreen extends StatefulWidget {
  final List<Advertisement> ads;
  final AdService adService;
  final VoidCallback onComplete;
  final String? county;
  final String? constituency;
  final AdPlacement placement;
  final bool firstAdUnskippable;
  final int skipDelaySeconds;
  final String? breakId;
  final bool markLaunchAdShownOnComplete;

  const AdBreakScreen({
    super.key,
    required this.ads,
    required this.adService,
    required this.onComplete,
    this.county,
    this.constituency,
    required this.placement,
    this.firstAdUnskippable = true,
    this.skipDelaySeconds = 5,
    this.breakId,
    this.markLaunchAdShownOnComplete = true,
  });

  @override
  State<AdBreakScreen> createState() => _AdBreakScreenState();
}

class _AdBreakScreenState extends State<AdBreakScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.ads.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onComplete();
      });
    }
  }

  void _handleStepComplete() {
    if (!mounted) return;
    final next = _index + 1;
    if (next >= widget.ads.length) {
      _finish();
      return;
    }
    setState(() => _index = next);
  }

  Future<void> _finish() async {
    if (widget.markLaunchAdShownOnComplete) {
      await widget.adService.markLaunchAdShown();
    }
    if (!mounted) return;
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentAd = widget.ads[_index];
    final firstUnskippableStep =
        widget.firstAdUnskippable && _index == 0 && widget.ads.length > 1;
    final stepSkipDelay = currentAd.skipDelaySeconds ?? widget.skipDelaySeconds;

    return AppLaunchAdScreen(
      ad: currentAd,
      adService: widget.adService,
      onComplete: _handleStepComplete,
      county: widget.county,
      constituency: widget.constituency,
      placement: widget.placement,
      markLaunchAdShownOnComplete: false,
      skipEnabled: !firstUnskippableStep,
      skipDelayOverrideSeconds: firstUnskippableStep ? null : stepSkipDelay,
      autoAdvanceAfter: firstUnskippableStep
          ? Duration(seconds: math.max(4, stepSkipDelay))
          : null,
      breakId: widget.breakId,
      breakStepIndex: _index + 1,
    );
  }
}

