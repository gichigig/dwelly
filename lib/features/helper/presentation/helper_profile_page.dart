import 'package:flutter/material.dart';
import '../../../core/models/helper_profile.dart';
import '../../../core/models/helper_review.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/user.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/helper_service.dart';
import '../../../core/services/auth_service.dart';
import '../../listings/presentation/chat_page.dart';
import 'package:intl/intl.dart';

class HelperProfilePage extends StatefulWidget {
  final int helperId;
  final String helperName;

  const HelperProfilePage({super.key, required this.helperId, required this.helperName});

  @override
  State<HelperProfilePage> createState() => _HelperProfilePageState();
}

class _HelperProfilePageState extends State<HelperProfilePage> {
  HelperProfile? _profile;
  List<HelperReview> _reviews = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final profile = await HelperService.getHelperProfile(widget.helperId);
      final reviews = await HelperService.getHelperReviews(widget.helperId);
      
      if (mounted) {
        setState(() {
          _profile = profile;
          _reviews = reviews;
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

  Future<void> _openChat() async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to contact a helper')),
      );
      return;
    }

    final dummyRental = Rental(
      id: 0,
      title: '${widget.helperName} (Helper)',
      description: 'Helper services',
      price: _profile?.helperPrice ?? 0.0,
      address: '',
      bedrooms: 0,
      bathrooms: 0,
      squareFeet: 0,
      propertyType: 'HELPER',
      ownerId: widget.helperId,
      ownerName: widget.helperName,
      ownerAvatarUrl: _profile?.avatarUrl,
    );

    try {
      final conversation = await ChatService.startConversation(
        targetUserId: widget.helperId,
      );
      if (!mounted) return;
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
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(rental: dummyRental),
        ),
      );
    }
  }

  Future<void> _showRateDialog() async {
    int rating = 5;
    final commentController = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Rate Helper'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How was your experience with this helper?'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            rating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      labelText: 'Review (Optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() => submitting = true);
                          try {
                            await HelperService.submitReview(
                              helperId: widget.helperId,
                              rating: rating,
                              comment: commentController.text,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              _loadData(); // Refresh to show new review
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Review submitted!')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() => submitting = false);
                            }
                          }
                        },
                  child: submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helper Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _buildProfile(),
    );
  }

  Widget _buildProfile() {
    final profile = _profile!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          Container(
            color: Theme.of(context).colorScheme.surfaceVariant,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(
                            backgroundColor: Colors.black,
                            iconTheme: const IconThemeData(color: Colors.white),
                            elevation: 0,
                          ),
                          body: Center(
                            child: InteractiveViewer(
                              child: Hero(
                                tag: 'helper_avatar_${profile.id}',
                                child: Image.network(
                                  profile.avatarUrl!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                        fullscreenDialog: true,
                      ),
                    );
                  } : null,
                  child: Hero(
                    tag: 'helper_avatar_${profile.id}',
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).primaryColor,
                      backgroundImage: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
                          ? NetworkImage(profile.avatarUrl!)
                          : null,
                      child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                          ? Text(
                              profile.firstName.isNotEmpty ? profile.firstName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 40),
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  profile.fullName,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      profile.averageRating > 0 ? profile.averageRating.toStringAsFixed(1) : 'New',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      ' (${profile.reviewCount} reviews)',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.work, color: Colors.grey, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${profile.totalHires} hires',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat),
                  label: const Text('Contact Helper'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Details Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildDetailRow(Icons.payments, 'Price', 'KES ${profile.helperPrice.toStringAsFixed(2)}'),
                if (profile.helperCoverageLevel != null)
                  _buildDetailRow(Icons.map, 'Coverage Level', profile.helperCoverageLevel!),
                if (profile.helperCounty != null)
                  _buildDetailRow(Icons.location_city, 'County', profile.helperCounty!),
                if (profile.helperWards.isNotEmpty)
                  _buildDetailRow(Icons.location_on, 'Wards', profile.helperWards.join(', ')),
              ],
            ),
          ),
          const Divider(),

          // Reviews Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if (profile.canReview)
                  TextButton.icon(
                    onPressed: _showRateDialog,
                    icon: const Icon(Icons.rate_review),
                    label: const Text('Leave Review'),
                  ),
              ],
            ),
          ),
          
          if (_reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Text('No reviews yet.', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reviews.length,
              itemBuilder: (context, index) {
                final review = _reviews[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(review.clientName.isNotEmpty ? review.clientName[0] : '?'),
                  ),
                  title: Row(
                    children: [
                      Text(review.clientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Row(
                        children: List.generate(5, (i) {
                          return Icon(
                            i < review.rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          );
                        }),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (review.comment != null && review.comment!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(review.comment!),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat.yMMMd().format(review.createdAt),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
