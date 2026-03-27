import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/advertisement.dart';
import '../../../core/models/marketplace_product.dart';
import '../../../core/models/marketplace_review.dart';
import '../../../core/models/seller_profile.dart';
import '../../../core/models/rental.dart';
import '../../../core/navigation/app_tab_navigator.dart';
import '../../../core/errors/ui_error.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/widgets/feed_ad_widget.dart';
import '../../listings/presentation/chat_page.dart';

class ProductDetailPage extends StatefulWidget {
  final int productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  MarketplaceProduct? _product;
  SellerProfile? _seller;
  final List<MarketplaceReview> _reviews = [];
  bool _loadingReviews = true;
  MarketplaceReview? _myReview;
  AdService? _adService;
  Advertisement? _detailAd;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _initAds();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final product = await MarketplaceService.getProductById(widget.productId);
      SellerProfile? seller;
      if (product.createdById != null) {
        seller = await MarketplaceService.getSellerSummary(
          product.createdById!,
        );
      }
      if (!mounted) return;
      setState(() {
        _product = product;
        _seller = seller;
        _loading = false;
      });
      await _loadReviews();
      await _loadDetailAd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorMessage(
          e,
          fallbackMessage: 'Failed to load product. Please try again.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _initAds() async {
    try {
      final service = await AdService.getInstance();
      if (!mounted) return;
      setState(() => _adService = service);
      await _loadDetailAd();
    } catch (_) {
      // Ads are optional.
    }
  }

  Future<void> _loadDetailAd() async {
    final service = _adService;
    final product = _product;
    if (service == null || product == null) return;
    final ad = await service.getTargetedAd(
      AdPlacement.MARKETPLACE_DETAIL,
      county: product.county,
      constituency: product.constituency,
    );
    if (!mounted) return;
    setState(() => _detailAd = ad);
  }

  Future<void> _loadReviews() async {
    try {
      setState(() => _loadingReviews = true);
      final page = await MarketplaceService.getReviews(widget.productId);
      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(page.reviews);
        _myReview = _reviews.cast<MarketplaceReview?>().firstWhere(
          (r) => r?.mine == true,
          orElse: () => null,
        );
        _loadingReviews = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingReviews = false);
    }
  }

  Future<void> _toggleSave() async {
    final product = _product;
    if (product == null) return;
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to save products');
      return;
    }

    try {
      if (product.savedByViewer) {
        await MarketplaceService.unsaveProduct(product.id!);
        setState(() {
          _product = product.copyWith(
            savedByViewer: false,
            saveCount: (product.saveCount - 1).clamp(0, 1 << 30),
          );
        });
      } else {
        await MarketplaceService.saveProduct(product.id!);
        setState(() {
          _product = product.copyWith(
            savedByViewer: true,
            saveCount: product.saveCount + 1,
          );
        });
      }
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to update saved products. Please try again.',
      );
    }
  }

  Future<void> _toggleLike() async {
    final product = _product;
    if (product?.id == null) return;
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to like products');
      return;
    }

    try {
      final updated = product!.likedByViewer
          ? await MarketplaceService.unlikeProduct(product.id!)
          : await MarketplaceService.likeProduct(product.id!);
      if (!mounted) return;
      setState(
        () => _product = updated.copyWith(
          savedByViewer: _product?.savedByViewer ?? false,
        ),
      );
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to update likes. Please try again.',
      );
    }
  }

  Future<void> _requestSponsorship() async {
    final product = _product;
    if (product?.id == null) return;
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in first');
      return;
    }
    try {
      await MarketplaceService.requestProductSponsorship(product!.id!);
      if (!mounted) return;
      _showSnack('Sponsorship request submitted');
      await _load();
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to request sponsorship. Please try again.',
      );
    }
  }

  Future<void> _openReviewEditor({MarketplaceReview? review}) async {
    if (!AuthService.isLoggedIn) {
      _showSignInSnack('Sign in to add a review');
      return;
    }
    int rating = review?.rating ?? 5;
    final commentController = TextEditingController(
      text: review?.comment ?? '',
    );
    final formKey = GlobalKey<FormState>();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review == null ? 'Add Review' : 'Edit Review',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(
                        5,
                        (index) => IconButton(
                          onPressed: () =>
                              setModalState(() => rating = index + 1),
                          icon: Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: commentController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Comment',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        review == null ? 'Submit review' : 'Save changes',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (submitted != true) {
      commentController.dispose();
      return;
    }

    try {
      if (review == null) {
        await MarketplaceService.upsertReview(
          widget.productId,
          rating: rating,
          comment: commentController.text.trim(),
        );
      } else {
        await MarketplaceService.updateReview(
          review.id,
          rating: rating,
          comment: commentController.text.trim(),
        );
      }
      if (!mounted) return;
      _showSnack('Review saved');
      await _load();
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to save review. Please try again.',
      );
    } finally {
      commentController.dispose();
    }
  }

  Future<void> _deleteMyReview() async {
    final review = _myReview;
    if (review == null) return;
    try {
      await MarketplaceService.deleteReview(review.id);
      if (!mounted) return;
      _showSnack('Review deleted');
      await _load();
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to delete review. Please try again.',
      );
    }
  }

  Future<void> _reportReview(MarketplaceReview review) async {
    if (!AuthService.isLoggedIn) {
      _showSnack('Sign in to report');
      return;
    }
    final reasonController = TextEditingController();
    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report review'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: 'Tell us what is wrong',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );

    if (shouldSend != true) {
      reasonController.dispose();
      return;
    }
    try {
      await MarketplaceService.reportReview(review.id, reasonController.text);
      if (!mounted) return;
      _showSnack('Review reported');
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to report review. Please try again.',
      );
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _chatSeller() async {
    final product = _product;
    if (product?.id == null) return;
    if (!AuthService.isLoggedIn) {
      _showSnack('Sign in to chat with seller');
      return;
    }

    setState(() => _busy = true);
    try {
      final conversation = await ChatService.startConversation(
        productId: product!.id,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            rental: Rental(
              id: -1,
              title: product.title,
              description: product.description,
              price: product.price,
              address:
                  '${product.ward}, ${product.constituency}, ${product.county}',
              city: product.county,
              state: product.county,
              bedrooms: 0,
              bathrooms: 0,
              squareFeet: 0,
              propertyType: 'OTHER',
              imageUrls: product.imageUrls,
              ownerId: conversation.ownerId > 0 ? conversation.ownerId : null,
              ownerName: conversation.ownerName,
            ),
            existingConversation: conversation,
          ),
        ),
      );
    } catch (e) {
      _showError(
        e,
        fallbackMessage: 'Failed to open seller chat. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callSeller() async {
    final phone = _product?.contactPhone;
    if (phone == null || phone.trim().isEmpty) {
      _showSnack('Seller phone is not available');
      return;
    }
    final uri = Uri.parse('tel:${phone.trim()}');
    if (!await canLaunchUrl(uri)) {
      _showSnack('Cannot open dialer on this device');
      return;
    }
    await launchUrl(uri);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSignInSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: AppTabNavigator.openAccount,
        ),
      ),
    );
  }

  void _showError(Object error, {required String fallbackMessage}) {
    if (!mounted || isSilentError(error)) return;
    showErrorSnackBar(context, error, fallbackMessage: fallbackMessage);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Product')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Failed to load product'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final product = _product!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product'),
        actions: [
          IconButton(
            onPressed: _toggleLike,
            icon: Icon(
              product.likedByViewer ? Icons.favorite : Icons.favorite_border,
            ),
          ),
          IconButton(
            onPressed: _toggleSave,
            icon: Icon(
              product.savedByViewer ? Icons.bookmark : Icons.bookmark_border,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                SizedBox(
                  height: 260,
                  child: PageView.builder(
                    itemCount: product.imageUrls.isEmpty
                        ? 1
                        : product.imageUrls.length,
                    itemBuilder: (_, index) {
                      final image = product.imageUrls.isEmpty
                          ? null
                          : product.imageUrls[index];
                      if (image == null) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 48,
                          ),
                        );
                      }
                      return CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 48,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.formattedPrice,
                        style: TextStyle(
                          fontSize: 20,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${product.ward}, ${product.constituency}, ${product.county}',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: Colors.red[400],
                          ),
                          const SizedBox(width: 4),
                          Text('${product.likeCount} likes'),
                          const SizedBox(width: 12),
                          Icon(Icons.star, size: 16, color: Colors.amber[700]),
                          const SizedBox(width: 4),
                          Text(
                            '${product.averageRating.toStringAsFixed(1)} (${product.ratingCount})',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(product.description),
                      if (_detailAd != null && _adService != null) ...[
                        const SizedBox(height: 18),
                        FeedAdWidget(
                          ad: _detailAd!,
                          adService: _adService!,
                          height: 160,
                          margin: EdgeInsets.zero,
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Text(
                        'Seller',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _seller?.sellerName ??
                                        product.sellerName ??
                                        'Seller',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if ((_seller?.verified ??
                                    product.sellerVerified))
                                  const Icon(
                                    Icons.verified,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Active products: ${_seller?.activeProducts ?? 0} - Total: ${_seller?.totalProducts ?? 0}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (AuthService.currentUser?.id ==
                          product.createdById) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _requestSponsorship,
                          icon: const Icon(Icons.campaign_outlined),
                          label: const Text('Request Sponsorship'),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Ratings & Reviews',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                _openReviewEditor(review: _myReview),
                            child: Text(_myReview == null ? 'Add' : 'Edit'),
                          ),
                          if (_myReview != null)
                            TextButton(
                              onPressed: _deleteMyReview,
                              child: const Text('Delete'),
                            ),
                        ],
                      ),
                      if (_loadingReviews)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_reviews.isEmpty)
                        Text(
                          'No reviews yet',
                          style: TextStyle(color: Colors.grey[700]),
                        )
                      else
                        ..._reviews.map(
                          (review) => Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            review.userName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (review.userMarketplaceBadge) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.verified,
                                              size: 15,
                                              color: Colors.blue,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: review.mine
                                          ? null
                                          : () => _reportReview(review),
                                      child: const Text('Report'),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < review.rating
                                          ? Icons.star
                                          : Icons.star_border,
                                      size: 15,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                                if ((review.comment ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(review.comment!),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _chatSeller,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Chat Seller'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: product.showPhone ? _callSeller : null,
                      icon: const Icon(Icons.call),
                      label: const Text('Call Seller'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
