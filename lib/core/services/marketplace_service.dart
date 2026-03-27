import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors/app_error.dart';
import '../models/chat.dart';
import '../models/marketplace_commerce.dart';
import '../models/marketplace_product.dart';
import '../models/marketplace_review.dart';
import '../models/seller_profile.dart';
import 'api_service.dart';
import 'auth_service.dart';

class PaginatedMarketplaceProducts {
  final List<MarketplaceProduct> products;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final bool hasMore;
  final String? rankingVersion;
  final String? viewerLocationUsed;
  final bool restrictedFilterApplied;
  final String? servedMode;
  final List<String> warnings;

  const PaginatedMarketplaceProducts({
    required this.products,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.hasMore,
    this.rankingVersion,
    this.viewerLocationUsed,
    this.restrictedFilterApplied = false,
    this.servedMode,
    this.warnings = const [],
  });
}

class MarketplaceFilterMetadata {
  final List<String> categories;
  final List<String> conditions;
  final List<String> counties;
  final Map<String, List<String>> constituenciesByCounty;
  final Map<String, List<String>> wardsByConstituency;

  const MarketplaceFilterMetadata({
    required this.categories,
    required this.conditions,
    required this.counties,
    required this.constituenciesByCounty,
    required this.wardsByConstituency,
  });

  factory MarketplaceFilterMetadata.fromJson(Map<String, dynamic> json) {
    List<String> toStringList(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) => e.toString()).toList();
    }

    Map<String, List<String>> toNestedStringMap(dynamic raw) {
      final result = <String, List<String>>{};
      if (raw is! Map<String, dynamic>) return result;
      raw.forEach((key, value) {
        if (value is List) {
          result[key] = value.map((e) => e.toString()).toList();
        }
      });
      return result;
    }

    return MarketplaceFilterMetadata(
      categories: toStringList(json['categories']),
      conditions: toStringList(json['conditions']),
      counties: toStringList(json['counties']),
      constituenciesByCounty: toNestedStringMap(json['constituenciesByCounty']),
      wardsByConstituency: toNestedStringMap(json['wardsByConstituency']),
    );
  }
}

class MarketplaceNavBadges {
  final int savedCount;
  final int inboxUnreadCount;
  final int sellerActiveCount;

  const MarketplaceNavBadges({
    this.savedCount = 0,
    this.inboxUnreadCount = 0,
    this.sellerActiveCount = 0,
  });

  factory MarketplaceNavBadges.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MarketplaceNavBadges();
    return MarketplaceNavBadges(
      savedCount: (json['savedCount'] as num?)?.toInt() ?? 0,
      inboxUnreadCount: (json['inboxUnreadCount'] as num?)?.toInt() ?? 0,
      sellerActiveCount: (json['sellerActiveCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class MarketplaceAccountSummary {
  final bool authenticated;
  final String badgeStatus;
  final int totalProducts;
  final int activeProducts;
  final int pendingSponsorshipRequests;
  final int inboxUnreadCount;
  final int savedCount;
  final List<String> warnings;

  const MarketplaceAccountSummary({
    required this.authenticated,
    required this.badgeStatus,
    required this.totalProducts,
    required this.activeProducts,
    required this.pendingSponsorshipRequests,
    required this.inboxUnreadCount,
    required this.savedCount,
    this.warnings = const [],
  });

  const MarketplaceAccountSummary.empty()
    : authenticated = false,
      badgeStatus = 'NONE',
      totalProducts = 0,
      activeProducts = 0,
      pendingSponsorshipRequests = 0,
      inboxUnreadCount = 0,
      savedCount = 0,
      warnings = const [];

  factory MarketplaceAccountSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MarketplaceAccountSummary.empty();
    return MarketplaceAccountSummary(
      authenticated: json['authenticated'] == true,
      badgeStatus: (json['badgeStatus'] as String?) ?? 'NONE',
      totalProducts: (json['totalProducts'] as num?)?.toInt() ?? 0,
      activeProducts: (json['activeProducts'] as num?)?.toInt() ?? 0,
      pendingSponsorshipRequests:
          (json['pendingSponsorshipRequests'] as num?)?.toInt() ?? 0,
      inboxUnreadCount: (json['inboxUnreadCount'] as num?)?.toInt() ?? 0,
      savedCount: (json['savedCount'] as num?)?.toInt() ?? 0,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class MarketplaceBootstrapPayload {
  final PaginatedMarketplaceProducts home;
  final MarketplaceFilterMetadata filters;
  final MarketplaceTabPreviews tabPreviews;
  final MarketplaceNavBadges navBadges;
  final MarketplaceAccountSummary accountSummary;
  final MarketplaceStorefrontPayload? storefront;
  final String? serverNow;
  final String? requestId;
  final List<String> warnings;

  const MarketplaceBootstrapPayload({
    required this.home,
    required this.filters,
    required this.tabPreviews,
    required this.navBadges,
    required this.accountSummary,
    this.storefront,
    this.serverNow,
    this.requestId,
    this.warnings = const [],
  });

  factory MarketplaceBootstrapPayload.fromJson(Map<String, dynamic> json) {
    return MarketplaceBootstrapPayload(
      home: MarketplaceService._parseProductsPage(
        json['home'] as Map<String, dynamic>? ?? const {},
        fallbackPage: 0,
      ),
      filters: MarketplaceFilterMetadata.fromJson(
        json['filters'] as Map<String, dynamic>? ?? const {},
      ),
      tabPreviews: MarketplaceTabPreviews.fromJson(
        json['tabPreviews'] as Map<String, dynamic>?,
      ),
      navBadges: MarketplaceNavBadges.fromJson(
        json['navBadges'] as Map<String, dynamic>?,
      ),
      accountSummary: MarketplaceAccountSummary.fromJson(
        json['accountSummary'] as Map<String, dynamic>?,
      ),
      storefront: json['storefront'] is Map<String, dynamic>
          ? MarketplaceStorefrontPayload.fromJson(
              json['storefront'] as Map<String, dynamic>,
            )
          : null,
      serverNow: json['serverNow'] as String?,
      requestId: json['requestId'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class MarketplaceTabPreviews {
  final List<MarketplaceProduct> savedProducts;
  final List<MarketplaceProduct> myProducts;
  final List<Conversation> inboxConversations;

  const MarketplaceTabPreviews({
    this.savedProducts = const [],
    this.myProducts = const [],
    this.inboxConversations = const [],
  });

  factory MarketplaceTabPreviews.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MarketplaceTabPreviews();

    List<MarketplaceProduct> parseProducts(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceProduct.fromJson)
          .toList();
    }

    List<Conversation> parseConversations(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Conversation.fromJson)
          .toList();
    }

    return MarketplaceTabPreviews(
      savedProducts: parseProducts(json['savedProducts']),
      myProducts: parseProducts(json['myProducts']),
      inboxConversations: parseConversations(json['inboxConversations']),
    );
  }
}

class MarketplaceSponsorshipRequest {
  final int? id;
  final int? productId;
  final String? productTitle;
  final String? status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final DateTime? startAt;
  final DateTime? endAt;
  final int? multiplier;

  const MarketplaceSponsorshipRequest({
    this.id,
    this.productId,
    this.productTitle,
    this.status,
    this.notes,
    this.createdAt,
    this.reviewedAt,
    this.startAt,
    this.endAt,
    this.multiplier,
  });

  factory MarketplaceSponsorshipRequest.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return MarketplaceSponsorshipRequest(
      id: (json['id'] as num?)?.toInt(),
      productId: (json['productId'] as num?)?.toInt(),
      productTitle: json['productTitle'] as String?,
      status: json['status'] as String?,
      notes: json['notes'] as String?,
      createdAt: parseDate(json['createdAt']),
      reviewedAt: parseDate(json['reviewedAt']),
      startAt: parseDate(json['startAt']),
      endAt: parseDate(json['endAt']),
      multiplier: (json['multiplier'] as num?)?.toInt(),
    );
  }
}

class PaginatedMarketplaceSponsorshipRequests {
  final List<MarketplaceSponsorshipRequest> requests;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final int pageSize;
  final bool hasMore;

  const PaginatedMarketplaceSponsorshipRequests({
    required this.requests,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
    required this.hasMore,
  });
}

class MarketplaceService {
  static const AppError _authRequired = AppError(
    code: AppErrorCode.sessionExpired,
    message: 'Please sign in to continue.',
    retryable: true,
  );

  static void _invalidateMarketplaceReadCaches() {
    ApiService.invalidateCachedGetByPath('/marketplace/products');
    ApiService.invalidateCachedGetByPath('/marketplace/sellers');
    ApiService.invalidateCachedGetByPath('/marketplace/bootstrap');
    ApiService.invalidateCachedGetByPath('/marketplace/account/summary');
    ApiService.invalidateCachedGetByPath('/marketplace/storefront');
    ApiService.invalidateCachedGetByPath('/marketplace/sections');
    ApiService.invalidateCachedGetByPath('/marketplace/cart');
    ApiService.invalidateCachedGetByPath('/marketplace/orders');
  }

  static Future<PaginatedMarketplaceProducts> getProducts({
    int page = 0,
    int size = 6,
    String? query,
    String? category,
    String? county,
    String? constituency,
    String? ward,
    String? condition,
    double? minPrice,
    double? maxPrice,
    String sort = 'SMART',
    String loadMode = 'SMART',
    String? viewerCounty,
    bool includeAds = true,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
      'sort': sort,
      'loadMode': loadMode,
      'includeAds': '$includeAds',
    };
    if (query != null && query.trim().isNotEmpty) {
      params['query'] = query.trim();
    }
    if (category != null && category.isNotEmpty) {
      params['category'] = category;
    }
    if (county != null && county.trim().isNotEmpty) {
      params['county'] = county.trim();
    }
    if (constituency != null && constituency.trim().isNotEmpty) {
      params['constituency'] = constituency.trim();
    }
    if (ward != null && ward.trim().isNotEmpty) {
      params['ward'] = ward.trim();
    }
    if (condition != null && condition.isNotEmpty) {
      params['condition'] = condition;
    }
    if (minPrice != null) {
      params['minPrice'] = minPrice.toString();
    }
    if (maxPrice != null) {
      params['maxPrice'] = maxPrice.toString();
    }
    if (viewerCounty != null && viewerCounty.trim().isNotEmpty) {
      params['viewerCounty'] = viewerCounty.trim();
    }

    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/products',
    ).replace(queryParameters: params);

    final response = await ApiService.cachedGet(
      uri,
      headers: const {'Accept': 'application/json'},
      ttl: page == 0
          ? const Duration(seconds: 30)
          : const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 120),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load marketplace products.',
      );
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    return _parseProductsPage(data, fallbackPage: page);
  }

  static Future<MarketplaceBootstrapPayload> getBootstrap({
    String? viewerCounty,
    Duration requestTimeout = const Duration(seconds: 8),
  }) async {
    final params = <String, String>{};
    if (viewerCounty != null && viewerCounty.trim().isNotEmpty) {
      params['viewerCounty'] = viewerCounty.trim();
    }

    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/bootstrap',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final response = await ApiService.cachedGet(
      uri,
      headers: AuthService.token == null
          ? const {'Accept': 'application/json'}
          : ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 25),
      staleWhileRevalidate: const Duration(seconds: 90),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load marketplace.',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceBootstrapPayload.fromJson(data);
  }

  static Future<MarketplaceAccountSummary> getAccountSummary({
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    final response = await ApiService.cachedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/account/summary'),
      headers: AuthService.token == null
          ? const {'Accept': 'application/json'}
          : ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 60),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load account summary.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceAccountSummary.fromJson(body);
  }

  static Future<MarketplaceStorefrontPayload> getStorefront({
    String? viewerCounty,
    Duration requestTimeout = const Duration(milliseconds: 4500),
  }) async {
    final params = <String, String>{};
    if (viewerCounty != null && viewerCounty.trim().isNotEmpty) {
      params['viewerCounty'] = viewerCounty.trim();
    }
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/storefront',
    ).replace(queryParameters: params.isEmpty ? null : params);
    final response = await ApiService.cachedGet(
      uri,
      headers: AuthService.token == null
          ? const {'Accept': 'application/json'}
          : ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 60),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load storefront.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceStorefrontPayload.fromJson(body);
  }

  static Future<PaginatedMarketplaceProducts> getStorefrontSectionProducts(
    String sectionKey, {
    int page = 0,
    int size = 12,
    String? viewerCounty,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'size': '$size',
      if (viewerCounty != null && viewerCounty.trim().isNotEmpty)
        'viewerCounty': viewerCounty.trim(),
    };
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/sections/$sectionKey/products',
    ).replace(queryParameters: params);
    final response = await ApiService.cachedGet(
      uri,
      headers: AuthService.token == null
          ? const {'Accept': 'application/json'}
          : ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 60),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load section products.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseProductsPage(body, fallbackPage: page);
  }

  static Future<MarketplaceCart> getCart({
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.cachedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/cart'),
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 8),
      staleWhileRevalidate: const Duration(seconds: 20),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load cart.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceCart.fromJson(body);
  }

  static Future<MarketplaceCart> addCartItem(
    int productId, {
    int quantity = 1,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/cart/items'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'productId': productId, 'quantity': quantity}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to add item to cart.',
      );
    }
    ApiService.invalidateCachedGetByPath('/marketplace/cart');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceCart.fromJson(body);
  }

  static Future<MarketplaceCart> updateCartItem(
    int itemId, {
    required int quantity,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPatch(
      Uri.parse('${ApiService.baseUrl}/marketplace/cart/items/$itemId'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'quantity': quantity}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update cart item.',
      );
    }
    ApiService.invalidateCachedGetByPath('/marketplace/cart');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceCart.fromJson(body);
  }

  static Future<MarketplaceCart> removeCartItem(int itemId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedDelete(
      Uri.parse('${ApiService.baseUrl}/marketplace/cart/items/$itemId'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to remove cart item.',
      );
    }
    ApiService.invalidateCachedGetByPath('/marketplace/cart');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceCart.fromJson(body);
  }

  static Future<MarketplaceOrder> checkout({
    required String mpesaPhone,
    String deliveryType = 'BOTH',
    String? deliveryAddress,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/checkout'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({
        'deliveryType': deliveryType,
        'mpesaPhone': mpesaPhone,
        if (deliveryAddress != null && deliveryAddress.trim().isNotEmpty)
          'deliveryAddress': deliveryAddress.trim(),
      }),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Checkout failed.',
      );
    }
    ApiService.invalidateCachedGetByPath('/marketplace/cart');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceOrder.fromJson(body);
  }

  static Future<PaginatedMarketplaceOrders> getMyOrders({
    int page = 0,
    int size = 20,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/orders/me',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});
    final response = await ApiService.cachedGet(
      uri,
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 10),
      staleWhileRevalidate: const Duration(seconds: 30),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load orders.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedMarketplaceOrders.fromJson(body);
  }

  static Future<PaginatedMarketplaceOrders> getSellerOrders({
    int page = 0,
    int size = 20,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/seller/orders',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});
    final response = await ApiService.cachedGet(
      uri,
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 10),
      staleWhileRevalidate: const Duration(seconds: 30),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load seller orders.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedMarketplaceOrders.fromJson(body);
  }

  static Future<MarketplaceOrder> getOrderById(int orderId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/orders/$orderId'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load order.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceOrder.fromJson(body);
  }

  static Future<MarketplaceOrder> cancelOrder(int orderId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/orders/$orderId/cancel'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to cancel order.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceOrder.fromJson(body);
  }

  static Future<MarketplaceOrder> updateSellerOrderFulfillment(
    int orderId, {
    required String status,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPatch(
      Uri.parse(
        '${ApiService.baseUrl}/marketplace/seller/orders/$orderId/fulfillment',
      ),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update order status.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MarketplaceOrder.fromJson(body);
  }

  static Future<MpesaCheckoutResult> startOrderMpesa(
    int orderId, {
    required String phoneNumber,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse(
        '${ApiService.baseUrl}/marketplace/orders/$orderId/payment/mpesa/stk',
      ),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'phoneNumber': phoneNumber}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to start M-Pesa payment.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return MpesaCheckoutResult.fromJson(body);
  }

  static Future<MarketplaceProduct> getProductById(int productId) async {
    final response = await ApiService.cachedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId'),
      headers: const {'Accept': 'application/json'},
      ttl: const Duration(minutes: 2),
      staleWhileRevalidate: const Duration(minutes: 3),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load product.',
      );
    }
    return MarketplaceProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<MarketplaceProduct> createProduct({
    required MarketplaceProduct product,
    required List<File> images,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    if (images.isEmpty) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'At least one image is required.',
      );
    }
    if (images.length > 6) {
      throw const AppError(
        code: AppErrorCode.validation,
        message: 'Maximum 6 images allowed.',
      );
    }

    final uploadedUrls = <String>[];
    for (final image in images) {
      final url = await uploadFile(image);
      uploadedUrls.add(url);
    }

    final payload = product.toJson()..['imageUrls'] = uploadedUrls;
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/products'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode(payload),
    );
    if (response.statusCode != 201) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to create product.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<MarketplaceProduct> updateProduct({
    required int productId,
    required MarketplaceProduct product,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPut(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode(product.toJson()),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update product.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> updateStatus(int productId, String status) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPatch(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId/status'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update product status.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<void> deleteProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedDelete(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 204) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to delete product.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<void> saveProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId/save'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to save product.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<void> unsaveProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedDelete(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId/save'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to unsave product.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<PaginatedMarketplaceProducts> getSavedProducts({
    int page = 0,
    int size = 6,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/products/saved',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});
    final response = await ApiService.cachedGet(
      uri,
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 60),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load saved products.',
      );
    }
    final Map<String, dynamic> data = jsonDecode(response.body);
    return _parseProductsPage(data, fallbackPage: page);
  }

  static Future<PaginatedMarketplaceProducts> getMyProducts({
    int page = 0,
    int size = 10,
    String? status,
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }

    final params = <String, String>{
      'page': '$page',
      'size': '$size',
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };

    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/products/me',
    ).replace(queryParameters: params);
    final response = await ApiService.cachedGet(
      uri,
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 60),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load your products.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseProductsPage(body, fallbackPage: page);
  }

  static Future<PaginatedMarketplaceSponsorshipRequests>
  getMySponsorshipRequests({int page = 0, int size = 20}) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }

    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/products/me/sponsorship-requests',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});
    final response = await ApiService.timedGet(
      uri,
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load sponsorship requests.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = body['requests'] as List<dynamic>? ?? const [];
    return PaginatedMarketplaceSponsorshipRequests(
      requests: raw
          .map(
            (e) => MarketplaceSponsorshipRequest.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      totalElements: (body['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (body['totalPages'] as num?)?.toInt() ?? 0,
      currentPage: (body['currentPage'] as num?)?.toInt() ?? page,
      pageSize: (body['pageSize'] as num?)?.toInt() ?? size,
      hasMore: body['hasMore'] == true,
    );
  }

  static Future<SellerProfile> getSellerSummary(int userId) async {
    final response = await ApiService.cachedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/sellers/$userId/summary'),
      headers: const {'Accept': 'application/json'},
      ttl: const Duration(minutes: 2),
      staleWhileRevalidate: const Duration(minutes: 3),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load seller profile.',
      );
    }
    return SellerProfile.fromJson(jsonDecode(response.body));
  }

  static Future<MarketplaceProduct> likeProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId/like'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to like product.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<MarketplaceProduct> unlikeProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedDelete(
      Uri.parse('${ApiService.baseUrl}/marketplace/products/$productId/like'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to unlike product.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceProduct.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<bool> hasLikedProduct(int productId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) return false;
    final response = await ApiService.cachedGet(
      Uri.parse(
        '${ApiService.baseUrl}/marketplace/products/$productId/likes/me',
      ),
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 15),
      staleWhileRevalidate: const Duration(seconds: 30),
    );
    if (response.statusCode != 200) return false;
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['liked'] == true;
  }

  static Future<MarketplaceReviewPage> getReviews(
    int productId, {
    int page = 0,
    int size = 20,
  }) async {
    final uri = Uri.parse(
      '${ApiService.baseUrl}/marketplace/products/$productId/reviews',
    ).replace(queryParameters: {'page': '$page', 'size': '$size'});
    final response = await ApiService.cachedGet(
      uri,
      headers: const {'Accept': 'application/json'},
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 45),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load reviews.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final reviews = (body['reviews'] as List<dynamic>? ?? const [])
        .map((e) => MarketplaceReview.fromJson(e as Map<String, dynamic>))
        .toList();
    return MarketplaceReviewPage(
      reviews: reviews,
      totalElements: (body['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (body['totalPages'] as num?)?.toInt() ?? 0,
      currentPage: (body['currentPage'] as num?)?.toInt() ?? page,
      pageSize: (body['pageSize'] as num?)?.toInt() ?? size,
      hasMore: body['hasMore'] == true,
    );
  }

  static Future<MarketplaceReview> upsertReview(
    int productId, {
    required int rating,
    String? comment,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse(
        '${ApiService.baseUrl}/marketplace/products/$productId/reviews',
      ),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'rating': rating, 'comment': comment?.trim()}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to save review.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceReview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<MarketplaceReview> updateReview(
    int reviewId, {
    required int rating,
    String? comment,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPut(
      Uri.parse('${ApiService.baseUrl}/marketplace/reviews/$reviewId'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'rating': rating, 'comment': comment?.trim()}),
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to update review.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return MarketplaceReview.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> deleteReview(int reviewId) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedDelete(
      Uri.parse('${ApiService.baseUrl}/marketplace/reviews/$reviewId'),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 204) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to delete review.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<void> reportReview(int reviewId, String reason) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/reviews/$reviewId/report'),
      headers: ApiService.getHeaders(token: AuthService.token),
      body: jsonEncode({'reason': reason.trim()}),
    );
    if (response.statusCode != 201) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to report review.',
      );
    }
    _invalidateMarketplaceReadCaches();
  }

  static Future<Map<String, dynamic>> requestMarketplaceBadge({
    String? companyLogoUrl,
    String? companyProfilePdfUrl,
    String? businessPermitUrl,
    String? nationalIdUrl,
    String? kraCertUrl,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final body = <String, dynamic>{};
    if (companyLogoUrl != null) body['companyLogoUrl'] = companyLogoUrl;
    if (companyProfilePdfUrl != null) {
      body['companyProfilePdfUrl'] = companyProfilePdfUrl;
    }
    if (businessPermitUrl != null) {
      body['businessPermitUrl'] = businessPermitUrl;
    }
    if (nationalIdUrl != null) body['nationalIdUrl'] = nationalIdUrl;
    if (kraCertUrl != null) body['kraCertUrl'] = kraCertUrl;

    final headers = Map<String, String>.from(
      ApiService.getHeaders(token: AuthService.token),
    );
    headers['Content-Type'] = 'application/json';

    final response = await ApiService.timedPost(
      Uri.parse('${ApiService.baseUrl}/marketplace/badge/request'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to submit badge request.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMyMarketplaceBadgeRequest({
    Duration requestTimeout = ApiService.defaultRequestTimeout,
  }) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.cachedGet(
      Uri.parse('${ApiService.baseUrl}/marketplace/badge/me'),
      headers: ApiService.getHeaders(token: AuthService.token),
      ttl: const Duration(seconds: 20),
      staleWhileRevalidate: const Duration(seconds: 40),
      requestTimeout: requestTimeout,
    );
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to load badge request.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> requestProductSponsorship(
    int productId,
  ) async {
    if (!AuthService.isLoggedIn || AuthService.token == null) {
      throw _authRequired;
    }
    final response = await ApiService.timedPost(
      Uri.parse(
        '${ApiService.baseUrl}/marketplace/products/$productId/sponsorship-request',
      ),
      headers: ApiService.getHeaders(token: AuthService.token),
    );
    if (response.statusCode != 201) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to request sponsorship.',
      );
    }
    _invalidateMarketplaceReadCaches();
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static PaginatedMarketplaceProducts _parseProductsPage(
    Map<String, dynamic> data, {
    required int fallbackPage,
  }) {
    final List<dynamic> rawProducts = data['products'] as List<dynamic>? ?? [];
    return PaginatedMarketplaceProducts(
      products: rawProducts
          .map((e) => MarketplaceProduct.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalElements: (data['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 0,
      currentPage: (data['currentPage'] as num?)?.toInt() ?? fallbackPage,
      hasMore: data['hasMore'] == true,
      rankingVersion: data['rankingVersion'] as String?,
      viewerLocationUsed: data['viewerLocationUsed'] as String?,
      restrictedFilterApplied: data['restrictedFilterApplied'] == true,
      servedMode: data['servedMode'] as String?,
      warnings: (data['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  static Future<String> uploadFile(File file) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/files/upload'),
    );
    if (AuthService.token != null) {
      request.headers['Authorization'] = 'Bearer ${AuthService.token}';
    }
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw ApiService.parseHttpError(
        response,
        fallbackMessage: 'Failed to upload image.',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const AppError.server(
        message: 'Upload completed but no file URL was returned.',
      );
    }
    return url;
  }
}
