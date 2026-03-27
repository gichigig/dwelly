import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/device_location_service.dart';
import 'found_id_scan_page.dart';
import 'search_lost_id_page.dart';
import 'location_verification_sheet.dart';

class LostIdView extends ConsumerStatefulWidget {
  const LostIdView({super.key});

  @override
  ConsumerState<LostIdView> createState() => _LostIdViewState();
}

class _LostIdViewState extends ConsumerState<LostIdView> {
  final _searchController = TextEditingController();
  
  // Typewriter animation state
  String _hintText = '';
  int _currentHintIndex = 0;
  int _charIndex = 0;
  bool _isDeleting = false;
  Timer? _typewriterTimer;
  
  // Location state
  bool _isGettingLocation = false;
  String? _currentLocation;
  String? _selectedWard;
  String? _selectedConstituency;
  String? _selectedCounty;
  
  final List<String> _hints = [
    'Scan a lost ID',
    'Search your dream rental',
  ];

  @override
  void initState() {
    super.initState();
    // Start with first character immediately visible
    _hintText = _hints[0].substring(0, 1);
    _charIndex = 1;
    _startTypewriterAnimation();
    _checkAndRequestLocation();
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _checkAndRequestLocation() async {
    setState(() => _isGettingLocation = true);
    
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isGettingLocation = false);
        return;
      }
      
      // Permission granted - get location and show verification sheet
      final locationResult = await DeviceLocationService.getCurrentLocation();
      
      if (locationResult.success && locationResult.hasLocationData && mounted) {
        // Show verification sheet
        final verifiedLocation = await showLocationVerificationSheet(
          context,
          detectedLocation: locationResult,
        );
        
        if (verifiedLocation != null && mounted) {
          setState(() {
            _currentLocation = verifiedLocation.displayName;
            _selectedWard = verifiedLocation.ward;
            _selectedConstituency = verifiedLocation.constituency;
            _selectedCounty = verifiedLocation.county;
            _searchController.text = verifiedLocation.displayName;
          });
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }
  
  void _showIdOptionsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'What would you like to do?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.camera_alt, color: Colors.green.shade700),
                ),
                title: const Text('I found someone\'s ID'),
                subtitle: const Text('Scan & register a found ID'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FoundIdScanPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 72),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: Icon(Icons.search, color: Colors.orange.shade700),
                ),
                title: const Text('I lost my ID'),
                subtitle: const Text('Search if someone found it'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SearchLostIdPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<void> _refreshLocation() async {
    setState(() => _isGettingLocation = true);
    
    try {
      final locationResult = await DeviceLocationService.getCurrentLocation();
      
      if (locationResult.success && locationResult.hasLocationData && mounted) {
        // Show verification sheet
        final verifiedLocation = await showLocationVerificationSheet(
          context,
          detectedLocation: locationResult,
        );
        
        if (verifiedLocation != null && mounted) {
          setState(() {
            _currentLocation = verifiedLocation.displayName;
            _selectedWard = verifiedLocation.ward;
            _selectedConstituency = verifiedLocation.constituency;
            _selectedCounty = verifiedLocation.county;
            _searchController.text = verifiedLocation.displayName;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }
  
  void _startTypewriterAnimation() {
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        final currentHint = _hints[_currentHintIndex];
        
        if (!_isDeleting) {
          // Typing
          if (_charIndex < currentHint.length) {
            _hintText = currentHint.substring(0, _charIndex + 1);
            _charIndex++;
          } else {
            // Finished typing, pause then start deleting
            _typewriterTimer?.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _isDeleting = true;
                _startTypewriterAnimation();
              }
            });
          }
        } else {
          // Deleting
          if (_charIndex > 0) {
            _charIndex--;
            _hintText = currentHint.substring(0, _charIndex);
          } else {
            // Finished deleting, move to next hint
            _isDeleting = false;
            _currentHintIndex = (_currentHintIndex + 1) % _hints.length;
            _typewriterTimer?.cancel();
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _startTypewriterAnimation();
              }
            });
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: _searchController.text.isEmpty 
                  ? (_hintText.isEmpty ? '' : '$_hintText|')
                  : null,
              hintStyle: TextStyle(
                color: Colors.grey.shade500,
                fontStyle: FontStyle.normal,
              ),
              prefixIcon: IconButton(
                icon: Icon(
                  Icons.camera_alt,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                tooltip: 'ID Options',
                onPressed: () => _showIdOptionsDialog(),
              ),
              suffixIcon: _isGettingLocation
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.my_location),
                      tooltip: 'Use current location',
                      onPressed: _refreshLocation,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        
        // Action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.camera_alt,
                  title: 'Found an ID?',
                  subtitle: 'Scan & register it',
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FoundIdScanPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.search,
                  title: 'Lost your ID?',
                  subtitle: 'Search for it',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SearchLostIdPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // Placeholder - in a real app this would fetch from the repo
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.badge_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Lost & Found ID Service',
            style: TextStyle(
              color: Colors.grey[700], 
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Help reunite lost IDs with their owners. Scan a found ID or search for your lost one.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildInfoChip(Icons.lock, 'Secure'),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.timer, 'Auto-delete'),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.no_photography, 'No images stored'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

