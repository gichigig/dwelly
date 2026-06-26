import 'package:flutter/material.dart';
import 'package:realestate/core/models/user.dart';
import 'package:realestate/core/models/rental.dart';
import 'package:realestate/core/services/auth_service.dart';
import 'package:realestate/core/services/chat_service.dart';
import 'package:realestate/core/services/helper_service.dart';
import 'package:realestate/core/services/helper_job_service.dart';
import 'package:realestate/features/listings/presentation/chat_page.dart';
import 'package:realestate/core/data/kenya_locations.dart';
import 'package:realestate/features/helper/presentation/helper_profile_page.dart';

class FindHelperTab extends StatefulWidget {
  const FindHelperTab({super.key});

  @override
  State<FindHelperTab> createState() => _FindHelperTabState();
}

class _FindHelperTabState extends State<FindHelperTab> {
  bool _isLoading = true;
  String? _error;
  List<User> _helpers = [];
  String? _selectedCounty;

  @override
  void initState() {
    super.initState();
    _loadHelpers();
  }

  Future<void> _loadHelpers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final helpers = await HelperService.getAvailableHelpers(county: _selectedCounty);
      if (mounted) {
        setState(() {
          _helpers = helpers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openChat(BuildContext context, User helper) async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to contact a helper')),
      );
      return;
    }

    final dummyRental = Rental(
      id: 0,
      title: '${helper.firstName} (Helper)',
      description: 'Helper services',
      price: helper.helperPrice ?? 0.0,
      address: '',
      bedrooms: 0,
      bathrooms: 0,
      squareFeet: 0,
      propertyType: 'HELPER',
      ownerId: helper.id,
      ownerName: helper.fullName,
      ownerAvatarUrl: helper.avatarUrl,
    );

    try {
      final conversation = await ChatService.startConversation(
        targetUserId: helper.id,
      );
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            rental: dummyRental,
            existingConversation: conversation,
          ),
        ),
      );
    } catch (_) {
      // Fallback: open without existing conversation
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(rental: dummyRental),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<String>(
            value: _selectedCounty,
            decoration: const InputDecoration(
              labelText: 'Filter by County',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_city),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('All Counties'),
              ),
              ...KenyaLocations.counties.map((county) {
                return DropdownMenuItem(
                  value: county,
                  child: Text(county),
                );
              }),
            ],
            onChanged: (value) {
              setState(() {
                _selectedCounty = value;
              });
              _loadHelpers();
            },
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
                  : _helpers.isEmpty
                      ? const Center(
                          child: Text(
                            'No helpers found in this area.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: _helpers.length,
                          itemBuilder: (context, index) {
                            final helper = _helpers[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => HelperProfilePage(helperId: helper.id!, helperName: helper.firstName)),
                                  );
                                },
                                leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).primaryColor,
                                    backgroundImage: helper.avatarUrl != null && helper.avatarUrl!.isNotEmpty
                                        ? NetworkImage(helper.avatarUrl!)
                                        : null,
                                    child: helper.avatarUrl == null || helper.avatarUrl!.isEmpty
                                        ? Text(
                                            helper.firstName.isNotEmpty ? helper.firstName[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white),
                                          )
                                        : null,
                                  ),
                                title: Text(helper.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('Price: KES ${helper.helperPrice ?? 'Not set'}'),
                                    const SizedBox(height: 2),
                                    Text('Coverage: ${helper.helperCoverageLevel ?? 'N/A'}'),
                                    const SizedBox(height: 2),
                                    if (helper.helperCounty != null) Text('County: ${helper.helperCounty}'),
                                  ],
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => HelperProfilePage(helperId: helper.id!, helperName: helper.firstName)),
                                    );
                                  },
                                  child: const Text('View Profile'),
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
