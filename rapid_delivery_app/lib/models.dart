// =====================================================
// DATA MODELS - Rapid Delivery App
// =====================================================

/// Product category for filtering
class ProductCategory {
  final String id;
  final String name;
  final String icon;
  final String color;

  const ProductCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.color = '#0C831F',
  });
}

/// Product model with enhanced fields
class Product {
  final String id;
  final String name;
  final String unit;
  final String imageEmoji;
  final String? imageUrl; // For real product images
  final double price;
  final double? originalPrice; // For showing discounts
  final String categoryId;
  final String? description;
  final bool isBestSeller;
  final double? rating;

  Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.imageEmoji,
    this.imageUrl,
    required this.price,
    this.originalPrice,
    this.categoryId = 'all',
    this.description,
    this.isBestSeller = false,
    this.rating,
  });

  int get discountPercent {
    if (originalPrice == null || originalPrice! <= price) return 0;
    return (((originalPrice! - price) / originalPrice!) * 100).round();
  }
}

/// User location model
class UserLocation {
  final String name; // e.g. "Home", "Office"
  final String address; // e.g. "LNMIIT Campus"
  final double lat;
  final double lon;
  final bool isSaved;

  UserLocation({
    required this.name,
    required this.address,
    required this.lat,
    required this.lon,
    this.isSaved = false,
  });
}

/// Saved address model
class SavedAddress {
  final String id;
  final String label; // "Home", "Work", "Other"
  final String fullAddress;
  final String? landmark;
  final double lat;
  final double lon;
  final bool isDefault;

  SavedAddress({
    required this.id,
    required this.label,
    required this.fullAddress,
    this.landmark,
    required this.lat,
    required this.lon,
    this.isDefault = false,
  });
}

/// Banner model for promotions
class PromoBanner {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String backgroundColor;
  final String? actionUrl;

  const PromoBanner({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.backgroundColor = '#FFE4B5',
    this.actionUrl,
  });
}

/// Order status for tracking
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  outForDelivery,
  delivered,
  cancelled,
}

/// Order tracking model
class OrderTracking {
  final String orderId;
  final OrderStatus status;
  final DateTime? estimatedDelivery;
  final String? deliveryPartner;
  final double? currentLat;
  final double? currentLon;
  final List<TrackingStep> steps;

  OrderTracking({
    required this.orderId,
    required this.status,
    this.estimatedDelivery,
    this.deliveryPartner,
    this.currentLat,
    this.currentLon,
    this.steps = const [],
  });
}

/// Individual tracking step
class TrackingStep {
  final String title;
  final String? subtitle;
  final DateTime? time;
  final bool isCompleted;

  TrackingStep({
    required this.title,
    this.subtitle,
    this.time,
    this.isCompleted = false,
  });
}
