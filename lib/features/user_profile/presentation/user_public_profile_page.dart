import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:realestate/core/services/api_service.dart';
import 'package:realestate/core/services/user_profile_service.dart';
import 'package:realestate/core/models/rental.dart';
import 'package:realestate/features/listings/presentation/rental_detail_page.dart';
import 'package:realestate/features/user_profile/presentation/profile_photo_viewer_page.dart';
import 'package:realestate/core/services/contact_service.dart';

class UserPublicProfilePage extends StatefulWidget {
  final int userId;

  const UserPublicProfilePage({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserPublicProfilePage> createState() => _UserPublicProfilePageState();
}

class _UserPublicProfilePageState extends State<UserPublicProfilePage> {
  bool _isLoading = true;
  String? _error;
  PublicProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final profile = await UserProfileService.getPublicProfile(widget.userId, forceRefresh: forceRefresh);
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error', style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _profile == null
                  ? const Center(child: Text('Profile not found'))
                  : RefreshIndicator(
                      onRefresh: () => _loadProfile(forceRefresh: true),
                      child: _buildProfileContent(context, _profile!, theme),
                    ),
    );
  }

  Widget _buildProfileContent(BuildContext context, PublicProfile profile, ThemeData theme) {
    String? displayAvatarUrl = profile.avatarUrl;
    if (displayAvatarUrl == null || displayAvatarUrl.isEmpty) {
      try {
        final contact = ContactService.contacts.value.firstWhere(
          (c) => c.contactUserId == profile.id,
        );
        displayAvatarUrl = contact.avatarUrl;
      } catch (_) {}
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  theme.colorScheme.surface.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: displayAvatarUrl != null && displayAvatarUrl.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              opaque: false,
                              pageBuilder: (_, __, ___) => ProfilePhotoViewerPage(
                                imageUrl: ApiService.resolveMediaUrl(displayAvatarUrl!)!,
                                tag: 'profile_avatar_${profile.id}',
                              ),
                              transitionsBuilder: (_, animation, __, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        }
                      : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Hero(
                        tag: 'profile_avatar_${profile.id}',
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: displayAvatarUrl != null && displayAvatarUrl.isNotEmpty ? NetworkImage(ApiService.resolveMediaUrl(displayAvatarUrl)!) : null,
                          child: displayAvatarUrl == null || displayAvatarUrl.isEmpty
                              ? Icon(Icons.person, size: 50, color: theme.colorScheme.onPrimaryContainer)
                              : null,
                        ),
                      ),
                      if (displayAvatarUrl != null && displayAvatarUrl.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.zoom_in, size: 16, color: theme.colorScheme.onPrimary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${profile.firstName} ${profile.lastName}',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (profile.verificationStatus == 'VERIFIED')
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified, size: 16, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text('Verified', style: theme.textTheme.labelSmall?.copyWith(color: Colors.blue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (profile.userType != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          profile.userType!,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                if (profile.memberSince != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Member since ${DateFormat('MMMM yyyy').format(profile.memberSince!)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          
          // Listings Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active Listings (${profile.activeListings.length})',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (profile.activeListings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'No active listings found.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: profile.activeListings.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final rental = profile.activeListings[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 80,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: theme.colorScheme.surfaceContainerHighest,
                            image: rental.imageUrls.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(rental.imageUrls.first),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: rental.imageUrls.isEmpty
                              ? const Icon(Icons.home_work)
                              : null,
                        ),
                        title: Text(rental.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(rental.formattedPrice, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => RentalDetailPage(rental: rental),
                            ),
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
