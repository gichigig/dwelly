import 'package:flutter/material.dart';
import '../models/advertisement.dart';
import '../services/ad_service.dart';
import 'banner_ad_widget.dart';
import 'video_ad_player.dart';
import 'ad_form_modal.dart';

/// Widget for displaying ads in a feed/list context
/// Automatically chooses between image and video display based on media type
class FeedAdWidget extends StatelessWidget {
  final Advertisement ad;
  final AdService adService;
  final double? height;
  final EdgeInsets? margin;

  const FeedAdWidget({
    super.key,
    required this.ad,
    required this.adService,
    this.height,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ad.mediaType == MediaType.VIDEO
          ? VideoAdPlayer(
              ad: ad,
              adService: adService,
              height: height ?? 200,
              autoPlay: false,
              showControls: true,
              onFormTap: () => _showForm(context),
            )
          : BannerAdWidget(
              ad: ad,
              adService: adService,
              height: height ?? 160,
              onFormTap: () => _showForm(context),
            ),
    );
  }

  void _showForm(BuildContext context) {
    if (ad.linkType == LinkType.FORM && ad.formSchema != null) {
      AdFormModal.show(
        context,
        ad: ad,
        adService: adService,
      );
    }
  }
}

/// Helper widget to insert ads into a ListView at regular intervals
class AdListBuilder extends StatelessWidget {
  final List<Widget> children;
  final List<Advertisement> ads;
  final AdService adService;
  final int adInterval; // Show an ad every N items
  final double adHeight;
  
  const AdListBuilder({
    super.key,
    required this.children,
    required this.ads,
    required this.adService,
    this.adInterval = 5,
    this.adHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (ads.isEmpty) {
      return Column(children: children);
    }

    final List<Widget> combined = [];
    int adIndex = 0;

    for (int i = 0; i < children.length; i++) {
      combined.add(children[i]);
      
      // Insert ad after every N items
      if ((i + 1) % adInterval == 0 && adIndex < ads.length) {
        combined.add(FeedAdWidget(
          ad: ads[adIndex],
          adService: adService,
          height: ads[adIndex].mediaType == MediaType.VIDEO ? 200 : adHeight,
        ));
        adIndex++;
      }
    }

    return Column(children: combined);
  }
}

/// Sliver version for use in CustomScrollView
class SliverAdListBuilder extends StatelessWidget {
  final List<Widget> slivers;
  final List<Advertisement> ads;
  final AdService adService;
  final int adInterval;
  final double adHeight;

  const SliverAdListBuilder({
    super.key,
    required this.slivers,
    required this.ads,
    required this.adService,
    this.adInterval = 5,
    this.adHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (ads.isEmpty) {
      return SliverList(delegate: SliverChildListDelegate(slivers));
    }

    final List<Widget> combined = [];
    int adIndex = 0;

    for (int i = 0; i < slivers.length; i++) {
      combined.add(slivers[i]);

      if ((i + 1) % adInterval == 0 && adIndex < ads.length) {
        combined.add(SliverToBoxAdapter(
          child: FeedAdWidget(
            ad: ads[adIndex],
            adService: adService,
            height: ads[adIndex].mediaType == MediaType.VIDEO ? 200 : adHeight,
          ),
        ));
        adIndex++;
      }
    }

    return SliverList(delegate: SliverChildListDelegate(combined));
  }
}

/// Carousel widget for rotating through multiple banner ads
class AdCarousel extends StatefulWidget {
  final List<Advertisement> ads;
  final AdService adService;
  final double height;
  final Duration autoPlayInterval;
  final bool autoPlay;

  const AdCarousel({
    super.key,
    required this.ads,
    required this.adService,
    this.height = 160,
    this.autoPlayInterval = const Duration(seconds: 5),
    this.autoPlay = true,
  });

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.autoPlay && widget.ads.length > 1) {
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    Future.delayed(widget.autoPlayInterval, () {
      if (mounted && widget.ads.isNotEmpty) {
        final nextPage = (_currentPage + 1) % widget.ads.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _startAutoPlay();
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.ads.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final ad = widget.ads[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BannerAdWidget(
                  ad: ad,
                  adService: widget.adService,
                  height: widget.height,
                  onFormTap: () {
                    if (ad.linkType == LinkType.FORM && ad.formSchema != null) {
                      AdFormModal.show(context, ad: ad, adService: widget.adService);
                    }
                  },
                ),
              );
            },
          ),
        ),
        if (widget.ads.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.ads.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Theme.of(context).primaryColor
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
