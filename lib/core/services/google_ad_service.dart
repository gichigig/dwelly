import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'premium_service.dart';

class GoogleAdService {
  // Use official test IDs by default
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}

class GoogleAdBannerWidget extends StatefulWidget {
  const GoogleAdBannerWidget({super.key});

  @override
  State<GoogleAdBannerWidget> createState() => _GoogleAdBannerWidgetState();
}

class _GoogleAdBannerWidgetState extends State<GoogleAdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isAdLoadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isAdLoadStarted && !PremiumService.isPremiumActive() && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      _isAdLoadStarted = true;
      _loadAd(MediaQuery.of(context).size.width.truncate());
    }
  }

  Future<void> _loadAd(int width) async {
    final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (adSize == null) return;
    
    _bannerAd = BannerAd(
      adUnitId: GoogleAdService.bannerAdUnitId,
      request: const AdRequest(),
      size: adSize,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('$ad loaded.');
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PremiumService.isPremiumActive() || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink(); // Don't show anything for premium users or if not loaded
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      color: Theme.of(context).scaffoldBackgroundColor, // Match scaffold background
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

class GoogleAdMediumRectangleWidget extends StatefulWidget {
  const GoogleAdMediumRectangleWidget({super.key});

  @override
  State<GoogleAdMediumRectangleWidget> createState() => _GoogleAdMediumRectangleWidgetState();
}

class _GoogleAdMediumRectangleWidgetState extends State<GoogleAdMediumRectangleWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!PremiumService.isPremiumActive() && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      _loadAd();
    }
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: GoogleAdService.bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.mediumRectangle,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (PremiumService.isPremiumActive() || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      color: Colors.transparent,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
