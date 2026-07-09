import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/api_service.dart';
import 'landlord_dashboard_page.dart';

class LandlordPage extends StatefulWidget {
  const LandlordPage({super.key});

  @override
  State<LandlordPage> createState() => _LandlordPageState();
}

class _LandlordPageState extends State<LandlordPage> {
  bool _isLoading = false;

  String _getRealAdminUrl() {
    final base = ApiService.effectiveBaseUrl;
    if (base.contains('ishinadwelly.com')) {
      return 'https://ishinadwelly.com';
    } else {
      // Assuming cloudflare URL or other host
      return base.replaceAll('/api', '');
    }
  }

  void _launchRealAdmin() async {
    final url = Uri.parse('${_getRealAdminUrl()}/login');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch RealAdmin')),
        );
      }
    }
  }

  void _launchRealAdminSignup() async {
    final url = Uri.parse('${_getRealAdminUrl()}/signup?role=landlord&source=dwelly');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch RealAdmin')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;

    if (user != null && (user.role == 'ADMIN' || user.primaryRole == 'landlord')) {
      return const LandlordDashboardPage();
    }

    // Temporary check for any signed in user to access dashboard (if testing locally)
    // You can remove this or rely strictly on isRealAdmin flag
    // if (user != null) {
    //  return const LandlordDashboardPage();
    // }

    return Scaffold(
      appBar: AppBar(title: const Text('Become a Landlord')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.real_estate_agent, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Manage your properties with RealAdmin',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign in with your RealAdmin account to seamlessly import your profile, manage your buildings and rentals, and create groups right from the Dwelly app.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        if (user == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please log in to continue')),
                          );
                          return;
                        }
                        setState(() => _isLoading = true);
                        try {
                          await AuthService.setPrimaryRole('landlord');
                          if (mounted) setState(() {}); // Trigger rebuild to show dashboard
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update role: $e')),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(user != null ? 'Continue as ${user.firstName}' : 'Continue', style: const TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _launchRealAdminSignup,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Create a separate account', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _launchRealAdmin,
                      child: const Text('Sign in to existing account', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
