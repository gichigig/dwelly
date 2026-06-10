import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {

  String _resolvePaymentUrl(String amount) {
    String baseUrl = 'https://billygichigdev.me/payments/mpesa';
    if (kDebugMode) {
      if (kIsWeb) {
        baseUrl = 'http://localhost:3000/payments/mpesa';
      } else if (!kIsWeb && Platform.isIOS) {
        baseUrl = 'http://localhost:3000/payments/mpesa';
      } else {
        baseUrl = 'http://10.0.2.2:3000/payments/mpesa';
      }
    }
    
    final params = <String, String>{
      'type': 'PREMIUM',
      'amount': amount,
    };
    
    final token = AuthService.token;
    if (token != null) {
      params['token'] = token;
    }
    
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    return uri.toString();
  }

  Future<void> _openWebPortal(String amount) async {
    if (!AuthService.isLoggedIn) {
      showLoginBottomSheet(
        context,
        onSuccess: () {},
      );
      return;
    }

    final uri = Uri.parse(_resolvePaymentUrl(amount));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the payment page.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final isActive = user?.isPremiumActive ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1), // Deep Blue Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '💎 Dwelly Premium',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Icon(
                isActive ? Icons.verified : Icons.workspace_premium,
                size: 80,
                color: isActive ? Colors.greenAccent : Colors.amber,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isActive ? '🎉 PREMIUM ACTIVE' : '🚀 UNLOCK PREMIUM',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            if (isActive && user?.premiumExpiresAt != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Valid until: ${user!.premiumExpiresAt!.toLocal().toString().split(' ')[0]}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (!isActive)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'KES 300 / 30 DAYS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'KES 600 / 60 DAYS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 32),
            _buildFeatureRow(Icons.block, '🚫 ZERO Ads Interruption'),
            _buildFeatureRow(Icons.map, '🗺️ Advanced Location Filters'),
            _buildFeatureRow(Icons.radar, '📡 Exclusive Direction Cone Radar'),
            _buildFeatureRow(Icons.notifications_active, '🔔 Premium Instant Alerts'),
            _buildFeatureRow(Icons.video_library, '🎥 Full HD Video Access'),
            const SizedBox(height: 40),
            if (!isActive)
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWebPortal('300'),
                      icon: const Icon(Icons.open_in_new, size: 28, color: Color(0xFF0D47A1)),
                      label: const Text(
                        'PAY 300 KSH (30 DAYS)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber, // High contrast button
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed: () => _openWebPortal('600'),
                      icon: const Icon(Icons.star, size: 28, color: Colors.white),
                      label: const Text(
                        'PAY 600 KSH (60 DAYS)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
