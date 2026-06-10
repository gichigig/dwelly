import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:realestate/core/services/intercepted_client.dart' as http;
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import 'house_search_help_page.dart';

class AvailableHelpersPage extends StatefulWidget {
  const AvailableHelpersPage({super.key});

  @override
  State<AvailableHelpersPage> createState() => _AvailableHelpersPageState();
}

class _AvailableHelpersPageState extends State<AvailableHelpersPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _helpers = [];

  @override
  void initState() {
    super.initState();
    _fetchHelpers();
  }

  Future<void> _fetchHelpers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/api/helper/available'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _helpers = data.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load helpers';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  void _onHireTap() {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must log in to hire a house search helper.')),
      );
      showLoginBottomSheet(
        context,
        onSuccess: () {
          // If login success, go to hire page
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HouseSearchHelpPage()),
          );
        },
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HouseSearchHelpPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Helpers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: _fetchHelpers, child: const Text('Retry'))
                    ],
                  ),
                )
              : _helpers.isEmpty
                  ? const Center(child: Text('No helpers currently available.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _helpers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final helper = _helpers[index];
                        final name = helper['name'] ?? 'Helper';
                        final price = helper['helperPrice'] ?? 0;
                        
                        return Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: colorScheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: colorScheme.primaryContainer,
                                  child: Icon(Icons.person, color: colorScheme.primary, size: 32),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Rate: KES $price',
                                        style: TextStyle(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                FilledButton(
                                  onPressed: _onHireTap,
                                  child: const Text('Hire'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
