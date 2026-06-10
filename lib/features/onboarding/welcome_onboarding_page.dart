import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_location_service.dart';
import 'widgets/premium_map_animation.dart';

class WelcomeOnboardingPage extends StatefulWidget {
  final Widget child;

  const WelcomeOnboardingPage({super.key, required this.child});

  static const String _onboardingCompleteKey = 'location_onboarding_complete';

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  static Future<void> setOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
  }

  @override
  State<WelcomeOnboardingPage> createState() => _WelcomeOnboardingPageState();
}

class _WelcomeOnboardingPageState extends State<WelcomeOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  bool _isDetecting = false;
  bool _locationDetected = false;
  bool _locationDenied = false;
  DeviceLocationResult? _detectedLocation;
  final _locationController = TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isDetecting = true;
      _locationDenied = false;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _isDetecting = false;
            _locationDenied = true;
          });
          return;
        }
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        await DeviceLocationService.setUserDeniedLocation(true);
        setState(() {
          _isDetecting = false;
          _locationDenied = true;
        });
        return;
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _isDetecting = false;
          _locationDenied = true;
        });
        return;
      }

      final result = await DeviceLocationService.getCurrentLocation();

      if (result.success && result.hasLocationData) {
        setState(() {
          _detectedLocation = result;
          _locationController.text = result.detailedDisplayName;
          _locationDetected = true;
          _isDetecting = false;
        });
      } else {
        setState(() {
          _isDetecting = false;
          _locationDenied = true;
        });
      }
    } catch (e) {
      setState(() {
        _isDetecting = false;
        _locationDenied = true;
      });
    }
  }

  Future<void> _persistLocationSelection() async {
    final result = _detectedLocation;
    if (result == null || !result.success || !result.hasLocationData) return;

    await DeviceLocationService.setPendingProfileLocation(result);

    if (!AuthService.isLoggedIn || AuthService.currentUser == null) {
      return;
    }

    try {
      final current = AuthService.currentUser!;
      final updated = current.copyWith(
        locationWard: result.ward,
        locationConstituency: result.constituency,
        locationCounty: result.county,
        locationAreaName: result.areaName,
        locationLatitude: result.latitude,
        locationLongitude: result.longitude,
      );
      await AuthService.updateUser(updated);
      await DeviceLocationService.clearPendingProfileLocation();
    } catch (_) {}
  }

  Future<void> _finishOnboarding() async {
    await _persistLocationSelection();
    await WelcomeOnboardingPage.setOnboardingComplete();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.child),
      );
    }
  }

  Widget _buildSlide({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(icon, size: 100, color: Colors.blue),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimationSlide({
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const PremiumMapAnimation(size: 260),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              size: 48,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Where are you located?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'We\'ll show you rentals near your area so you find a home faster.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _locationController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Your Location',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
              hintText: 'e.g., Kilimani, Nairobi',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              prefixIcon: Icon(
                _locationDetected
                    ? Icons.check_circle
                    : Icons.location_on_outlined,
                color: _locationDetected ? Colors.green : Colors.white70,
              ),
              suffixIcon: _isDetecting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.my_location, color: Colors.blue),
                      tooltip: 'Detect my location',
                      onPressed: _detectLocation,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
          ),
          const SizedBox(height: 12),
          if (!_locationDetected)
            OutlinedButton.icon(
              onPressed: _isDetecting ? null : _detectLocation,
              icon: _isDetecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    )
                  : const Icon(Icons.my_location, color: Colors.blue),
              label: Text(
                _isDetecting ? 'Detecting...' : 'Use My Current Location',
                style: const TextStyle(color: Colors.blue),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          if (_locationDenied) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Could not detect location. You can type it manually or skip for now.',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_locationDetected && _detectedLocation != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.check,
                  color: Colors.green,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Location detected! You can edit it above.',
                    style: TextStyle(
                      color: Colors.green.shade400,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const Spacer(),
          ElevatedButton(
            onPressed: _finishOnboarding,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Get Started',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _finishOnboarding,
            child: Text(
              'Skip for now',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Force buttons to navigate
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildSlide(
                    icon: Icons.home_work_rounded,
                    title: 'Welcome to Dwelly',
                    subtitle: 'Your ultimate companion for finding the perfect rental property hassle-free.',
                    buttonText: 'Next',
                    onPressed: _nextPage,
                  ),
                  _buildSlide(
                    icon: Icons.travel_explore,
                    title: 'Discover Premium Rentals',
                    subtitle: 'Explore high-quality listings tailored to your preferences, budget, and lifestyle.',
                    buttonText: 'Next',
                    onPressed: _nextPage,
                  ),
                  _buildSlide(
                    icon: Icons.security_rounded,
                    title: 'Secure & Fast Communication',
                    subtitle: 'Chat directly with verified property owners securely within the app.',
                    buttonText: 'Next',
                    onPressed: _nextPage,
                  ),
                  _buildAnimationSlide(
                    title: 'Premium AR Cone Search',
                    subtitle: 'Physically rotate your phone to discover hidden listings around you using Augmented Reality.',
                    buttonText: 'Next',
                    onPressed: _nextPage,
                  ),
                  _buildLocationSlide(),
                ],
              ),
            ),
            // Optional: Pagination Dots
            if (_currentPage < 4)
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Colors.blue
                            : Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
