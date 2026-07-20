import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'auth_service.dart';
import 'premium_service.dart';
import 'ad_service.dart';
import '../../features/listings/presentation/premium_page.dart';
import '../../features/listings/presentation/about_developer_page.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

/// Returns true if Google Ads should be suppressed — either because the user
/// is premium OR because the super admin has globally suspended ads.
bool _shouldSuppressGoogleAds() {
  final user = AuthService.currentUser;
  final isUserPremium = user != null && user.shouldHideAds;
  return isUserPremium || AdService.areGoogleAdsSuspended();
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
  static Future<void> showRewardedAd(
    BuildContext context, {
    required VoidCallback onReward,
  }) async {
    if (_shouldSuppressGoogleAds() ||
        kIsWeb ||
        (!Platform.isIOS && !Platform.isAndroid)) {
      onReward();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: DwellyOrbitingLoader()),
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

          ad.show(
            onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
              rewardEarned = true;
            },
          );
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
    if (_shouldSuppressGoogleAds() ||
        kIsWeb ||
        (!Platform.isIOS && !Platform.isAndroid)) {
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

    if (DateTime.now()
        .subtract(const Duration(hours: 4))
        .isAfter(_appOpenLoadTime!)) {
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
    if (!_isAdLoadStarted &&
        !_shouldSuppressGoogleAds() &&
        !kIsWeb &&
        (Platform.isIOS || Platform.isAndroid)) {
      _isAdLoadStarted = true;
      _loadAd(MediaQuery.of(context).size.width.truncate());
    }
  }

  Future<void> _loadAd(int width) async {
    final adSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
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
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
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
    if (_shouldSuppressGoogleAds()) {
      return const SizedBox.shrink(); // Don't show anything for premium users
    }

    if (!_isLoaded || _bannerAd == null) {
      return (DateTime.now().second % 2 == 0)
          ? _buildPremiumBanner()
          : _buildDeveloperBanner();
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      color: Theme.of(
        context,
      ).scaffoldBackgroundColor, // Match scaffold background
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Widget _buildPremiumBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0EA5E9), Color(0xFF1E40AF)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Upgrade to Dwelly Premium 👑',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '100% Ad-Free • Verified Contacts • Instant WhatsApp & Push Alerts',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildDeveloperBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AboutDeveloperPage()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF312E81)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.code_rounded, color: Colors.cyanAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Need a Website, Software or Mobile App? ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Expert software development by Dwelly creator. Tap for socials & contact info!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

class GoogleAdMediumRectangleWidget extends StatefulWidget {
  const GoogleAdMediumRectangleWidget({super.key});

  @override
  State<GoogleAdMediumRectangleWidget> createState() =>
      _GoogleAdMediumRectangleWidgetState();
}

class _GoogleAdMediumRectangleWidgetState
    extends State<GoogleAdMediumRectangleWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    PremiumService.premiumActive.addListener(_onPremiumChanged);
    if (!_shouldSuppressGoogleAds() &&
        !kIsWeb &&
        (Platform.isIOS || Platform.isAndroid)) {
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
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isLoaded = false;
            });
          }
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
    if (_shouldSuppressGoogleAds()) {
      return const SizedBox.shrink();
    }

    if (!_isLoaded || _bannerAd == null) {
      return (DateTime.now().second % 2 == 0)
          ? _buildPremiumBanner()
          : _buildDeveloperBanner();
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      color: Colors.white,
      child: AdWidget(ad: _bannerAd!),
    );
  }

  Widget _buildPremiumBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PremiumPage()));
      },
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0EA5E9), Color(0xFF1E40AF)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Upgrade to Dwelly Premium 👑',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enjoy a 100% ad-free experience across all listings, unlock direct verified phone numbers, get instant alerts, and access compound video tours.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeveloperBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AboutDeveloperPage()));
      },
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFF312E81)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.code_rounded, color: Colors.cyanAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Need a Custom Website, Software or App? ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Looking for high-quality software development, custom websites, or iOS/Android apps? Reach out to the Dwelly creator via socials!',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
