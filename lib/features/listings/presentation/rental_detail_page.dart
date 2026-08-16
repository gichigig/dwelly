import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/rental.dart';
import '../../../core/models/advertisement.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/google_ad_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/services/saved_rental_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/widgets/auth_bottom_sheets.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/widgets/shimmer_placeholder.dart';
import 'chat_page.dart';
import '../../rentals/presentation/hashtag_search_page.dart';
import 'package:video_player/video_player.dart';
import '../../../core/widgets/full_screen_gallery.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/services/video_unlock_session_service.dart';
import '../../../core/widgets/share_listing_sheet.dart';
import '../../../core/widgets/fading_image_count_badge.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class RentalDetailPage extends StatefulWidget {
  final Rental rental;

  const RentalDetailPage({super.key, required this.rental});

  @override
  State<RentalDetailPage> createState() => _RentalDetailPageState();
}

class _RentalDetailPageState extends State<RentalDetailPage> {
  bool _isSaved = false;
  bool _isLoadingSaveStatus = true;
  bool _hasRecordedDetailOpen = false;
  AdService? _adService;
  Advertisement? _listingDetailAd;
  VideoPlayerController? _videoController;
  VideoPlayerController? _audioController;
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _recordDetailOpenOnce();
    _checkSaveStatus();
    _loadListingDetailAd();
    _initVideo();
    _initAudio();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_pageController.hasClients) return;

      final pageCount =
          widget.rental.imageUrls.length + (widget.rental.hasAnyVideo ? 1 : 0);
      if (pageCount <= 1) return;

      int nextIndex = _pageController.page!.round() + 1;
      if (nextIndex >= pageCount) {
        nextIndex = 0;
      }

      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _initVideo() {
    final effectiveUrl = widget.rental.effectiveVideoUrl;
    final isUnlocked = VideoUnlockSessionService.isVideoUnlocked(
      rentalId: widget.rental.id,
      videoUrl: effectiveUrl,
    );
    if (!isUnlocked) return;

    _initializeVideoPlayer();
  }

  void _initAudio() {
    if (widget.rental.hasAudio) {
      _audioController =
          VideoPlayerController.networkUrl(
            Uri.parse(widget.rental.audioUrl!),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
            ..initialize().then((_) {
              _audioController!.setLooping(true);
              _audioController!.setVolume(1.0);
              _audioController!.play();
              if (mounted) setState(() {});
            });
    }
  }

  void _initializeVideoPlayer() {
    final effectiveUrl = widget.rental.effectiveVideoUrl;
    if (widget.rental.hasAnyVideo && effectiveUrl != null) {
      final isCompound = effectiveUrl == widget.rental.compoundVideoUrl && effectiveUrl != widget.rental.videoUrl;
      final hasCustomAudio = widget.rental.hasAudio;
      _videoController =
          VideoPlayerController.networkUrl(
            Uri.parse(effectiveUrl),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          )
            ..initialize().then((_) {
              _videoController!.setLooping(true);
              _videoController!.setVolume((isCompound || hasCustomAudio) ? 0.0 : 1.0);
              _videoController!.play();
              if (mounted) setState(() {});
            });
    }
  }



  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _videoController?.dispose();
    _audioController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _recordDetailOpenOnce() async {
    if (_hasRecordedDetailOpen || widget.rental.id == null) {
      return;
    }
    _hasRecordedDetailOpen = true;
    await RentalService.recordRentalDetailOpen(widget.rental.id!);
  }

  Future<void> _loadListingDetailAd() async {
    try {
      final adService = await AdService.getInstance();
      final ad = await adService.getTargetedAd(
        AdPlacement.LISTING_DETAIL,
        county: widget.rental.county,
        constituency: widget.rental.constituency,
      );
      if (mounted) {
        setState(() {
          _adService = adService;
          _listingDetailAd = ad;
        });
      }
    } catch (_) {
      // Ignore ad failures in listing details.
    }
  }

  Future<void> _checkSaveStatus() async {
    if (!AuthService.isLoggedIn || widget.rental.id == null) {
      setState(() => _isLoadingSaveStatus = false);
      return;
    }

    try {
      final saved = await SavedRentalService.isRentalSaved(widget.rental.id!);
      if (mounted) {
        setState(() {
          _isSaved = saved;
          _isLoadingSaveStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSaveStatus = false);
      }
    }
  }

  Future<void> _toggleSave() async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to save listings'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Login',
            onPressed: () {
              showLoginBottomSheet(context, onSuccess: () => setState(() {}));
            },
          ),
        ),
      );
      return;
    }

    if (widget.rental.id == null) return;

    final wasavedSaved = _isSaved;
    setState(() => _isSaved = !_isSaved);

    try {
      bool success;
      if (wasavedSaved) {
        success = await SavedRentalService.unsaveRental(widget.rental.id!);
      } else {
        success = await SavedRentalService.saveRental(widget.rental.id!);
      }

      if (!success && mounted) {
        setState(() => _isSaved = wasavedSaved);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${wasavedSaved ? 'unsave' : 'save'} listing',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSaved ? 'Added to saved' : 'Removed from saved'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaved = wasavedSaved);
        showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Failed to update saved listing. Please try again.',
        );
      }
    }
  }

  void _showReportDialog() {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to report a listing'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Login',
            onPressed: () {
              showLoginBottomSheet(context, onSuccess: () => setState(() {}));
            },
          ),
        ),
      );
      return;
    }

    // Check if user owns this rental
    if (widget.rental.ownerId != null &&
        widget.rental.ownerId == AuthService.currentUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot report your own listing')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ReportBottomSheet(
        rentalId: widget.rental.id!,
        rentalTitle: widget.rental.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rental = widget.rental;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with Image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            actions: [
              // Save button
              IconButton(
                onPressed: _isLoadingSaveStatus ? null : _toggleSave,
                icon: _isLoadingSaveStatus
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: DwellyOrbitingLoader(),
                      )
                    : Icon(
                        _isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: _isSaved ? Colors.amber : Colors.white,
                      ),
              ),
              IconButton(
                onPressed: () => ShareListingSheet.show(context, widget.rental),
                icon: const Icon(Icons.share, color: Colors.white),
              ),
              // More options menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'report') {
                    _showReportDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Report Listing'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: (rental.imageUrls.isNotEmpty || rental.hasAnyVideo)
                  ? GestureDetector(
                      onTap: () {
                        final effectiveUrl = rental.effectiveVideoUrl;
                        final isUnlocked =
                            VideoUnlockSessionService.isVideoUnlocked(
                              rentalId: rental.id,
                              videoUrl: effectiveUrl,
                            );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenGallery(
                              rentalId: rental.id,
                              imageUrls: rental.imageUrls,
                              thumbnailUrls: rental.thumbnailUrls,
                              mediumUrls: rental.mediumUrls,
                              videoUrl: effectiveUrl,
                              showVideoFirst: isUnlocked,
                              isPremium: isUnlocked,
                            ),
                          ),
                        ).then((_) {
                          if (mounted &&
                              VideoUnlockSessionService.isVideoUnlocked(
                                rentalId: rental.id,
                                videoUrl: effectiveUrl,
                              )) {
                            if (_videoController == null) {
                              _initializeVideoPlayer();
                            }
                            setState(() {});
                          }
                        });
                      },
                      child: FadingImageCountBadge(
                        currentIndex: _currentImageIndex,
                        totalCount: rental.imageUrls.length + (rental.hasAnyVideo ? 1 : 0),
                        alignment: Alignment.topRight,
                        child: PageView.builder(
                          controller: _pageController,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemCount:
                              rental.imageUrls.length +
                              (rental.hasAnyVideo ? 1 : 0),
                          itemBuilder: (context, index) {
                          final effectiveUrl = rental.effectiveVideoUrl;
                          final isUnlocked =
                              VideoUnlockSessionService.isVideoUnlocked(
                                rentalId: rental.id,
                                videoUrl: effectiveUrl,
                              );
                          final videoIndex = isUnlocked
                              ? 0
                              : rental.imageUrls.length;

                          if (rental.hasAnyVideo && index == videoIndex) {
                            if (_videoController != null &&
                                _videoController!.value.isInitialized) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    color: Colors.black,
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio:
                                            _videoController!.value.aspectRatio,
                                        child: VideoPlayer(_videoController!),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 16,
                                    right: 16,
                                    child: FloatingActionButton.small(
                                      backgroundColor: Colors.black54,
                                      onPressed: () {
                                        setState(() {
                                          _videoController!.value.volume > 0
                                              ? _videoController!.setVolume(0)
                                              : _videoController!.setVolume(1);
                                        });
                                      },
                                      child: Icon(
                                        _videoController!.value.volume > 0
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            }
                          }

                          final imageIndex =
                              (rental.hasAnyVideo && index > videoIndex)
                              ? index - 1
                              : (rental.hasAnyVideo && index < videoIndex)
                              ? index
                              : index;
                          if (imageIndex < 0 || imageIndex >= rental.imageUrls.length) {
                            return _buildPlaceholder();
                          }
                          return DwellyNetworkImage(
                            imageUrl: rental.imageUrls[imageIndex],
                            thumbnailUrl:
                                imageIndex < rental.thumbnailUrls.length
                                ? rental.thumbnailUrls[imageIndex]
                                : null,
                            mediumUrl: imageIndex < rental.mediumUrls.length
                                ? rental.mediumUrls[imageIndex]
                                : null,
                            loadFull: true,
                            fit: BoxFit.cover,
                            errorWidget: _buildPlaceholder(),
                          );
                        },
                      ),
                    ),
                  )
                : _buildPlaceholder(),
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rental.isSponsored)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFF59E0B),
                                      Color(0xFFD97706),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      rental.sponsorshipType != null &&
                                              rental.sponsorshipType != 'BOTH'
                                          ? 'Sponsored (${rental.sponsorshipType})'
                                          : 'Sponsored Listing',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              rental.title,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        rental.formattedPrice,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (rental.latitude != null && rental.longitude != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _getDirections(context, rental),
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text('Get Directions'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),

                  // Location
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          rental.fullAddress,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Property Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      rental.propertyType,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Features
                  const Text(
                    'Features',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildFeatureBox(Icons.bed, '${rental.bedrooms}', 'Beds'),
                      _buildFeatureBox(
                        Icons.bathtub,
                        '${rental.bathrooms}',
                        'Baths',
                      ),
                      _buildFeatureBox(
                        Icons.square_foot,
                        '${rental.squareFeet}',
                        'Sq Ft',
                      ),
                      if (rental.floor != null)
                        _buildFeatureBox(
                          Icons.layers,
                          '${rental.floor}',
                          'Floor',
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const Center(child: GoogleAdMediumRectangleWidget()),
                  const SizedBox(height: 24),

                  // Description
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    rental.description,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                  if (rental.hashtags.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: rental.hashtags.map((tag) {
                        return ActionChip(
                          label: Text(
                            tag.startsWith('#') ? tag : '#$tag',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: Colors.blue.withOpacity(0.08),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HashtagSearchPage(
                                  hashtag: tag.startsWith('#') ? tag : '#$tag',
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  if (_listingDetailAd != null && _adService != null) ...[
                    const SizedBox(height: 24),
                    BannerAdWidget(
                      ad: _listingDetailAd!,
                      adService: _adService!,
                      height: 160,
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Amenities
                  if (rental.amenities.isNotEmpty) ...[
                    const Text(
                      'Amenities',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: rental.amenities.map((amenity) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return Chip(
                          avatar: Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: isDark ? Colors.tealAccent[400] : Theme.of(context).primaryColor,
                          ),
                          label: Text(
                            amenity,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                          side: isDark ? const BorderSide(color: Color(0xFF334155)) : BorderSide.none,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Additional Info
                  const Text(
                    'Additional Info',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    Icons.pets,
                    'Pets',
                    rental.petsAllowed ? 'Allowed' : 'Not Allowed',
                  ),
                  _buildInfoRow(
                    Icons.local_parking,
                    'Parking',
                    rental.parkingAvailable ? 'Available' : 'Not Available',
                  ),
                  if (rental.availableFrom != null)
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Available From',
                      rental.availableFrom!,
                    ),

                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: () => _contactOwner(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Contact Owner',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.home, size: 100, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildFeatureBox(IconData icon, String value, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: isDark ? Colors.tealAccent[400] : Colors.grey[700]),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _getDirections(BuildContext context, Rental r) async {
    if (r.latitude == null || r.longitude == null) return;
    final lat = r.latitude!;
    final lng = r.longitude!;

    final appleMapsUrl = Uri.parse('http://maps.apple.com/?daddr=$lat,$lng');
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
    );

    try {
      if (Platform.isIOS) {
        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
        } else if (await canLaunchUrl(googleMapsUrl)) {
          await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        if (await canLaunchUrl(googleMapsUrl)) {
          await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open map application')),
        );
      }
    }
  }

  void _contactOwner(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please login to contact the owner'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Login',
            onPressed: () {
              showLoginBottomSheet(context, onSuccess: () => setState(() {}));
            },
          ),
        ),
      );
      return;
    }

    final rental = widget.rental;
    final hasPhone = rental.ownerPhone != null && rental.ownerPhone!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Contact ${rental.ownerName ?? 'Owner'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Phone call option
              if (hasPhone)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green[50],
                    child: const Icon(Icons.phone, color: Colors.green),
                  ),
                  title: const Text('Call Owner'),
                  subtitle: Text(rental.ownerPhone!),
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[200]!),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uri = Uri(scheme: 'tel', path: rental.ownerPhone);
                    try {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not launch dialer'),
                          ),
                        );
                      }
                    }
                  },
                ),

              if (hasPhone) const SizedBox(height: 12),

              // Chat option
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[50],
                  child: const Icon(Icons.chat, color: Colors.blue),
                ),
                title: const Text('Chat with Owner'),
                subtitle: const Text('Send a message'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey[200]!),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final conversation = await ChatService.startConversation(
                      rentalId: rental.id,
                    );
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          rental: rental,
                          existingConversation: conversation,
                        ),
                      ),
                    );
                  } catch (_) {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(rental: rental),
                      ),
                    );
                  }
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// Report Bottom Sheet Widget
class _ReportBottomSheet extends StatefulWidget {
  final int rentalId;
  final String rentalTitle;

  const _ReportBottomSheet({required this.rentalId, required this.rentalTitle});

  @override
  State<_ReportBottomSheet> createState() => _ReportBottomSheetState();
}

class _ReportBottomSheetState extends State<_ReportBottomSheet> {
  final _descriptionController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;
  bool _hasAlreadyReported = false;
  bool _isCheckingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkReportStatus();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _checkReportStatus() async {
    try {
      final hasReported = await ReportService.hasReportedRental(
        widget.rentalId,
      );
      if (mounted) {
        setState(() {
          _hasAlreadyReported = hasReported;
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingStatus = false);
      }
    }
  }

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a reason')));
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a description')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ReportService.createReport(
        rentalId: widget.rentalId,
        reason: _selectedReason!,
        description: _descriptionController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report submitted successfully. We will review it shortly.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showErrorSnackBar(
          context,
          e,
          fallbackMessage: 'Failed to submit report. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: _isCheckingStatus
          ? const SizedBox(
              height: 200,
              child: Center(child: DwellyOrbitingLoader()),
            )
          : _buildReportForm(),
    );
  }

  Widget _buildReportForm() {
    final titleText = _hasAlreadyReported
        ? 'Add Additional Complaint'
        : 'Report Listing';
    final buttonText = _hasAlreadyReported
        ? 'Submit Additional Complaint'
        : 'Submit Report';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              const Icon(Icons.flag, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                titleText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Report "${widget.rentalTitle}"',
            style: TextStyle(color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),

          // Reason selection
          const Text(
            'Why are you reporting this listing?',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          Column(
            children: ReportReason.defaultReasons
                .map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason.label),
                    value: reason.value,
                    groupValue: _selectedReason,
                    onChanged: (value) =>
                        setState(() => _selectedReason = value),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 16),

          // Description
          const Text(
            'Please provide details',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: _hasAlreadyReported
                  ? 'Add your new complaint here...'
                  : 'Describe the issue in detail...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: DwellyOrbitingLoader(),
                    )
                  : Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
