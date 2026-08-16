import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/models/rental.dart';
import '../../../../core/widgets/shimmer_placeholder.dart';

class TikTokRentalPage extends StatefulWidget {
  final Rental rental;
  final bool isEffectivelySponsored;
  final VoidCallback onTapDetails;
  final bool isSaved;
  final bool isViewed;
  final VoidCallback onToggleSave;
  final VoidCallback onReport;
  final double? userLatitude;
  final double? userLongitude;
  final bool isActivePage;

  const TikTokRentalPage({
    super.key,
    required this.rental,
    required this.isEffectivelySponsored,
    required this.onTapDetails,
    required this.isSaved,
    required this.isViewed,
    required this.onToggleSave,
    required this.onReport,
    this.userLatitude,
    this.userLongitude,
    required this.isActivePage,
  });

  @override
  State<TikTokRentalPage> createState() => _TikTokRentalPageState();
}

class _TikTokRentalPageState extends State<TikTokRentalPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _initVideo() {
    if (widget.rental.hasAnyVideo && widget.rental.effectiveVideoUrl != null) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.rental.effectiveVideoUrl!))
        ..initialize().then((_) {
          _videoController!.setLooping(true);
          if (widget.isActivePage && mounted) {
            _videoController!.play();
          }
          setState(() {});
        });
    }
  }

  @override
  void didUpdateWidget(TikTokRentalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActivePage != oldWidget.isActivePage) {
      if (widget.isActivePage) {
        _videoController?.play();
      } else {
        _videoController?.pause();
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Media
        GestureDetector(
          onTap: widget.onTapDetails,
          child: _buildMedia(),
        ),
        
        // Gradient overlay for text readability
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                    Colors.black.withOpacity(0.6),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Right side buttons
        Positioned(
          right: 16,
          bottom: 130, // Increased to avoid bottom navigation bar
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                icon: widget.isSaved ? Icons.favorite : Icons.favorite_border,
                label: 'Save',
                color: widget.isSaved ? Colors.red : Colors.white,
                onTap: widget.onToggleSave,
              ),
              const SizedBox(height: 24),
              _buildActionButton(
                icon: Icons.info_outline,
                label: 'Details',
                color: Colors.white,
                onTap: widget.onTapDetails,
              ),
              const SizedBox(height: 24),
              _buildActionButton(
                icon: Icons.report_problem_outlined,
                label: 'Report',
                color: Colors.white,
                onTap: widget.onReport,
              ),
            ],
          ),
        ),

        // Bottom left info
        Positioned(
          left: 16,
          bottom: 110, // Increased to avoid bottom navigation bar
          right: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isEffectivelySponsored)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Sponsored',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(
                'KES ${widget.rental.price.toStringAsFixed(0)} / mo',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.rental.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white70, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${widget.rental.ward ?? widget.rental.city}, ${widget.rental.county ?? widget.rental.state}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedia() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _videoController!.value.size.width,
            height: _videoController!.value.size.height,
            child: VideoPlayer(_videoController!),
          ),
        ),
      );
    }
    
    // Fallback to image
    if (widget.rental.imageUrls.isNotEmpty) {
      return SizedBox.expand(
        child: DwellyNetworkImage(
          imageUrl: widget.rental.imageUrls.first,
          fit: BoxFit.cover,
          height: double.infinity,
          width: double.infinity,
        ),
      );
    }
    
    return Container(color: Colors.black87);
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
