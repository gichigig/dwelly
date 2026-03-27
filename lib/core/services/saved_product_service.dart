import 'marketplace_service.dart';

class SavedProductService {
  static Future<void> save(int productId) {
    return MarketplaceService.saveProduct(productId);
  }

  static Future<void> unsave(int productId) {
    return MarketplaceService.unsaveProduct(productId);
  }

  static Future<PaginatedMarketplaceProducts> getSaved({
    int page = 0,
    int size = 6,
  }) {
    return MarketplaceService.getSavedProducts(page: page, size: size);
  }
}
