import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/device_location_service.dart';
import 'widgets/onboarding_motion_step.dart';

/// One-time onboarding screen to set up user's location.
/// Shown only on first app launch.
class LocationOnboardingPage extends StatefulWidget {
  final Widget child;

  const LocationOnboardingPage({super.key, required this.child});

  static const String _onboardingCompleteKey = 'location_onboarding_complete';

  /// Check if onboarding has been completed
  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  /// Mark onboarding as complete
  static Future<void> setOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, true);
  }

  @override
  State<LocationOnboardingPage> createState() => _LocationOnboardingPageState();
}

class _LocationOnboardingPageState extends State<LocationOnboardingPage>
    with SingleTickerProviderStateMixin {
  int _stepIndex = 0;
  bool _isDetecting = false;
  bool _locationDetected = false;
  bool _locationDenied = false;
  DeviceLocationResult? _detectedLocation;
  final _locationController = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _locationController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    if (_stepIndex >= 2) return;
    setState(() => _stepIndex += 1);
  }

  void _skipToLocationStep() {
    setState(() => _stepIndex = 2);
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isDetecting = true;
      _locationDenied = false;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Prompt user to enable GPS
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

      // Check permission
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
        // User dismissed the dialog - do not persist as permanent denial.
        setState(() {
          _isDetecting = false;
          _locationDenied = true;
        });
        return;
      }

      // Get location
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

  Future<void> _continue() async {
    await _persistLocationSelection();
    await LocationOnboardingPage.setOnboardingComplete();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.child));
    }
  }

  Future<void> _skip() async {
    await _persistLocationSelection();
    await LocationOnboardingPage.setOnboardingComplete();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.child));
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
    } catch (_) {
      // Keep pending payload for automatic sync on next auth save/login.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stepIndex == 0) {
      return OnboardingMotionStep(
        type: OnboardingMotionType.search,
        message:
            'Search by ward or constituency for better results near vacant rentals.',
        onFinished: _goToNextStep,
        onSkip: _skipToLocationStep,
      );
    }

    if (_stepIndex == 1) {
      return OnboardingMotionStep(
        type: OnboardingMotionType.filter,
        message:
            'Filter listings to your needs, like 1-bedroom, to find matches faster.',
        onFinished: _goToNextStep,
        onSkip: _skipToLocationStep,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on,
                            size: 48,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Where are you located?',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'We\'ll show you rentals near your area so you find a home faster.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          labelText: 'Your Location',
                          hintText: 'e.g., Kilimani, Nairobi',
                          prefixIcon: Icon(
                            _locationDetected
                                ? Icons.check_circle
                                : Icons.location_on_outlined,
                            color: _locationDetected ? Colors.green : null,
                          ),
                          suffixIcon: _isDetecting
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.my_location),
                                  tooltip: 'Detect my location',
                                  onPressed: _detectLocation,
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          filled: true,
                          fillColor: theme.brightness == Brightness.dark
                              ? theme.colorScheme.surfaceContainerHighest
                                    .withOpacity(0.55)
                              : Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_locationDetected)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isDetecting ? null : _detectLocation,
                            icon: _isDetecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                            label: Text(
                              _isDetecting
                                  ? 'Detecting...'
                                  : 'Use My Current Location',
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      if (_locationDenied) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.orange.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Could not detect location. You can type it manually or skip for now.',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
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
                            Icon(
                              Icons.check,
                              color: Colors.green.shade600,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Location detected! You can edit it above.',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _continue,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _skip,
                        child: Text(
                          'Skip for now',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
