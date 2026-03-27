import 'marketplace_product.dart';

class MarketplaceStorefrontSection {
  final String key;
  final String title;
  final String subtitle;
  final List<MarketplaceProduct> products;

  const MarketplaceStorefrontSection({
    required this.key,
    required this.title,
    required this.subtitle,
    this.products = const [],
  });

  factory MarketplaceStorefrontSection.fromJson(Map<String, dynamic> json) {
    return MarketplaceStorefrontSection(
      key: (json['key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      products: (json['products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceProduct.fromJson)
          .toList(),
    );
  }
}

class MarketplaceStorefrontPayload {
  final String sectionMode;
  final String heroTitle;
  final String heroSubtitle;
  final List<String> categoryShortcuts;
  final List<MarketplaceStorefrontSection> sections;
  final List<MarketplaceProduct> mainFeed;
  final String? serverNow;
  final String? requestId;
  final List<String> warnings;

  const MarketplaceStorefrontPayload({
    required this.sectionMode,
    required this.heroTitle,
    required this.heroSubtitle,
    this.categoryShortcuts = const [],
    this.sections = const [],
    this.mainFeed = const [],
    this.serverNow,
    this.requestId,
    this.warnings = const [],
  });

  factory MarketplaceStorefrontPayload.fromJson(Map<String, dynamic> json) {
    return MarketplaceStorefrontPayload(
      sectionMode: (json['sectionMode'] ?? 'GRID_FIRST').toString(),
      heroTitle: (json['heroTitle'] ?? 'Marketplace').toString(),
      heroSubtitle: (json['heroSubtitle'] ?? '').toString(),
      categoryShortcuts:
          (json['categoryShortcuts'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(),
      sections: (json['sections'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceStorefrontSection.fromJson)
          .toList(),
      mainFeed: (json['mainFeed'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceProduct.fromJson)
          .toList(),
      serverNow: json['serverNow'] as String?,
      requestId: json['requestId'] as String?,
      warnings: (json['warnings'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class MarketplaceCartItem {
  final int itemId;
  final int? productId;
  final String title;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final bool inStock;
  final int maxAvailable;
  final String deliveryType;
  final double deliveryFee;

  const MarketplaceCartItem({
    required this.itemId,
    this.productId,
    required this.title,
    this.imageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.inStock,
    required this.maxAvailable,
    required this.deliveryType,
    required this.deliveryFee,
  });

  factory MarketplaceCartItem.fromJson(Map<String, dynamic> json) {
    return MarketplaceCartItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      productId: (json['productId'] as num?)?.toInt(),
      title: (json['title'] ?? '').toString(),
      imageUrl: json['imageUrl'] as String?,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
      inStock: json['inStock'] == true,
      maxAvailable: (json['maxAvailable'] as num?)?.toInt() ?? 0,
      deliveryType: (json['deliveryType'] ?? 'BOTH').toString(),
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MarketplaceCart {
  final int? cartId;
  final int itemCount;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final List<MarketplaceCartItem> items;

  const MarketplaceCart({
    this.cartId,
    this.itemCount = 0,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.total = 0,
    this.items = const [],
  });

  const MarketplaceCart.empty() : this();

  factory MarketplaceCart.fromJson(Map<String, dynamic> json) {
    return MarketplaceCart(
      cartId: (json['cartId'] as num?)?.toInt(),
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceCartItem.fromJson)
          .toList(),
    );
  }
}

class MarketplaceOrderLine {
  final int? itemId;
  final int? productId;
  final String title;
  final String? imageUrl;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const MarketplaceOrderLine({
    this.itemId,
    this.productId,
    required this.title,
    this.imageUrl,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory MarketplaceOrderLine.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrderLine(
      itemId: (json['itemId'] as num?)?.toInt(),
      productId: (json['productId'] as num?)?.toInt(),
      title: (json['title'] ?? '').toString(),
      imageUrl: json['imageUrl'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MarketplaceOrder {
  final int id;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final String deliveryType;
  final String? deliveryAddress;
  final String? mpesaPhone;
  final String? checkoutRequestId;
  final String? mpesaReceiptNumber;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final int? buyerId;
  final String? buyerName;
  final int? sellerId;
  final String? sellerName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<MarketplaceOrderLine> items;

  const MarketplaceOrder({
    required this.id,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.deliveryType,
    this.deliveryAddress,
    this.mpesaPhone,
    this.checkoutRequestId,
    this.mpesaReceiptNumber,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.buyerId,
    this.buyerName,
    this.sellerId,
    this.sellerName,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
  });

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '').toString(),
      paymentStatus: (json['paymentStatus'] ?? '').toString(),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      deliveryType: (json['deliveryType'] ?? 'BOTH').toString(),
      deliveryAddress: json['deliveryAddress'] as String?,
      mpesaPhone: json['mpesaPhone'] as String?,
      checkoutRequestId: json['checkoutRequestId'] as String?,
      mpesaReceiptNumber: json['mpesaReceiptNumber'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      buyerId: (json['buyerId'] as num?)?.toInt(),
      buyerName: json['buyerName'] as String?,
      sellerId: (json['sellerId'] as num?)?.toInt(),
      sellerName: json['sellerName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceOrderLine.fromJson)
          .toList(),
    );
  }
}

class PaginatedMarketplaceOrders {
  final List<MarketplaceOrder> orders;
  final int totalElements;
  final int totalPages;
  final int currentPage;
  final int pageSize;
  final bool hasMore;

  const PaginatedMarketplaceOrders({
    required this.orders,
    required this.totalElements,
    required this.totalPages,
    required this.currentPage,
    required this.pageSize,
    required this.hasMore,
  });

  factory PaginatedMarketplaceOrders.fromJson(Map<String, dynamic> json) {
    return PaginatedMarketplaceOrders(
      orders: (json['orders'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MarketplaceOrder.fromJson)
          .toList(),
      totalElements: (json['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
      hasMore: json['hasMore'] == true,
    );
  }
}

class MpesaCheckoutResult {
  final bool success;
  final String message;
  final String? merchantRequestId;
  final String? checkoutRequestId;
  final String? responseCode;
  final String? responseDescription;
  final String? customerMessage;

  const MpesaCheckoutResult({
    required this.success,
    required this.message,
    this.merchantRequestId,
    this.checkoutRequestId,
    this.responseCode,
    this.responseDescription,
    this.customerMessage,
  });

  factory MpesaCheckoutResult.fromJson(Map<String, dynamic> json) {
    return MpesaCheckoutResult(
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      merchantRequestId: json['merchantRequestId'] as String?,
      checkoutRequestId: json['checkoutRequestId'] as String?,
      responseCode: json['responseCode'] as String?,
      responseDescription: json['responseDescription'] as String?,
      customerMessage: json['customerMessage'] as String?,
    );
  }
}
