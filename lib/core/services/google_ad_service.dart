import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'premium_service.dart';
import 'ad_service.dart';

/// Returns true if Google Ads should be suppressed — either because the user
/// is premium/tenant OR because the super admin has globally suspended ads.
bool _shouldSuppressGoogleAds() {
  return PremiumService.shouldHideAds() || AdService.areGoogleAdsSuspended();
}

class GoogleAdService {
  // Use official test IDs by default
  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7814990820270971/8972994119';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-7814990820270971/1890756610';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
  static String get appOpenAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7814990820270971/8861313473';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-7814990820270971/3675179799';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-7814990820270971/8254808814';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-7814990820270971/3339569657';
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }
}

class GoogleRewardedAdManager {
  static Future<void> showRewardedAd(BuildContext context, {required VoidCallback onReward}) async {
    if (_shouldSuppressGoogleAds() || kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      onReward();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    RewardedAd.load(
      adUnitId: GoogleAdService.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          Navigator.pop(context); // Remove loading spinner
          bool rewardEarned = false;
          
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (rewardEarned) {
                onReward();
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              onReward(); // Fallback
            },
          );

          ad.show(onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
            rewardEarned = true;
          });
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          Navigator.pop(context); // Remove loading spinner
          onReward(); // Fallback
        },
      ),
    );
  }
}

class AppOpenAdManager {
  AppOpenAd? _appOpenAd;
  bool _isShowingAd = false;
  DateTime? _appOpenLoadTime;

  static final AppOpenAdManager instance = AppOpenAdManager._internal();

  AppOpenAdManager._internal();

  void loadAd() {
    if (_shouldSuppressGoogleAds() || kIsWeb || (!Platform.isIOS && !Platform.isAndroid)) {
      return;
    }

    AppOpenAd.load(
      adUnitId: GoogleAdService.appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenLoadTime = DateTime.now();
          _appOpenAd = ad;
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
        },
      ),
    );
  }

  bool get isAdAvailable {
    return _appOpenAd != null;
  }

  void showAdIfAvailable() {
    if (!isAdAvailable) {
      debugPrint('Tried to show ad before available.');
      loadAd();
      return;
    }
    
    if (_isShowingAd) {
      debugPrint('Tried to show ad while already showing an ad.');
      return;
    }
    
    if (_shouldSuppressGoogleAds()) {
      _appOpenAd?.dispose();
      _appOpenAd = null;
      return;
    }

    if (DateTime.now().subtract(const Duration(hours: 4)).isAfter(_appOpenLoadTime!)) {
      debugPrint('Maximum cache duration exceeded. Loading another ad.');
      _appOpenAd!.dispose();
      _appOpenAd = null;
      loadAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAd = true;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAd();
      },
    );
    _appOpenAd!.show();
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
  void initState() {
    super.initState();
    PremiumService.premiumActive.addListener(_onPremiumChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isAdLoadStarted && !_shouldSuppressGoogleAds() && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
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

  void _onPremiumChanged() {
    if (_shouldSuppressGoogleAds()) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) {
        setState(() => _isLoaded = false);
      }
    }
  }

  @override
  void dispose() {
    PremiumService.premiumActive.removeListener(_onPremiumChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldSuppressGoogleAds() || !_isLoaded || _bannerAd == null) {
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
    PremiumService.premiumActive.addListener(_onPremiumChanged);
    if (!_shouldSuppressGoogleAds() && !kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      _loadAd();
    }
  }

  void _onPremiumChanged() {
    if (_shouldSuppressGoogleAds()) {
      _bannerAd?.dispose();
      _bannerAd = null;
      if (mounted) {
        setState(() => _isLoaded = false);
      }
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
    PremiumService.premiumActive.removeListener(_onPremiumChanged);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldSuppressGoogleAds() || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      color: Colors.white,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
