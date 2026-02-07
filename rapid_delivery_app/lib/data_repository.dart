import 'models.dart';

/// Repository for fetching app data (catalog, categories, banners)
class DataRepository {
  // =====================================================
  // PRODUCT CATEGORIES
  // =====================================================
  static List<ProductCategory> getCategories() {
    return const [
      ProductCategory(id: 'all', name: 'All', icon: '🏠', color: '#0C831F'),
      ProductCategory(
        id: 'fruits',
        name: 'Fruits',
        icon: '🍎',
        color: '#FF6B6B',
      ),
      ProductCategory(id: 'dairy', name: 'Dairy', icon: '🥛', color: '#4ECDC4'),
      ProductCategory(
        id: 'snacks',
        name: 'Snacks',
        icon: '🍿',
        color: '#FFE66D',
      ),
      ProductCategory(
        id: 'beverages',
        name: 'Drinks',
        icon: '🥤',
        color: '#95E1D3',
      ),
      ProductCategory(
        id: 'bakery',
        name: 'Bakery',
        icon: '🍞',
        color: '#DEB887',
      ),
      ProductCategory(
        id: 'grocery',
        name: 'Grocery',
        icon: '🛒',
        color: '#98D8C8',
      ),
      ProductCategory(
        id: 'frozen',
        name: 'Frozen',
        icon: '🧊',
        color: '#87CEEB',
      ),
    ];
  }

  // =====================================================
  // PROMO BANNERS
  // =====================================================
  static List<PromoBanner> getBanners() {
    return const [
      PromoBanner(
        id: 'b1',
        title: '⚡ 10-Min Delivery',
        subtitle: 'Get groceries in minutes',
        imageUrl: '',
        backgroundColor: '#E8F5E9',
      ),
      PromoBanner(
        id: 'b2',
        title: '🎉 First Order FREE',
        subtitle: 'Use code: RAPID50',
        imageUrl: '',
        backgroundColor: '#FFF3E0',
      ),
      PromoBanner(
        id: 'b3',
        title: '🥛 Fresh Dairy Daily',
        subtitle: 'Farm-fresh at 6 AM',
        imageUrl: '',
        backgroundColor: '#E3F2FD',
      ),
      PromoBanner(
        id: 'b4',
        title: '🍎 Fruits & Veggies',
        subtitle: 'Up to 30% OFF',
        imageUrl: '',
        backgroundColor: '#FCE4EC',
      ),
    ];
  }

  // =====================================================
  // PRODUCT CATALOG
  // =====================================================
  static Future<List<Product>> fetchCatalog() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    return [
      // Fruits
      Product(
        id: 'apple',
        name: 'Red Apple',
        unit: '1 kg',
        imageEmoji: '🍎',
        price: 149,
        originalPrice: 180,
        categoryId: 'fruits',
        isBestSeller: true,
        rating: 4.5,
        description: 'Fresh, crispy Shimla apples',
      ),
      Product(
        id: 'banana',
        name: 'Bananas',
        unit: '1 dozen',
        imageEmoji: '🍌',
        price: 49,
        categoryId: 'fruits',
        rating: 4.3,
        description: 'Ripe yellow bananas, rich in potassium',
      ),
      Product(
        id: 'orange',
        name: 'Nagpur Orange',
        unit: '1 kg',
        imageEmoji: '🍊',
        price: 89,
        originalPrice: 110,
        categoryId: 'fruits',
        rating: 4.2,
      ),
      Product(
        id: 'grapes',
        name: 'Green Grapes',
        unit: '500 g',
        imageEmoji: '🍇',
        price: 79,
        categoryId: 'fruits',
        isBestSeller: true,
      ),

      // Dairy
      Product(
        id: 'milk',
        name: 'Fresh Milk',
        unit: '1 L',
        imageEmoji: '🥛',
        price: 60,
        categoryId: 'dairy',
        isBestSeller: true,
        rating: 4.7,
        description: 'Full cream toned milk',
      ),
      Product(
        id: 'eggs',
        name: 'Farm Eggs',
        unit: '6 pcs',
        imageEmoji: '🥚',
        price: 59,
        originalPrice: 72,
        categoryId: 'dairy',
        rating: 4.4,
      ),
      Product(
        id: 'curd',
        name: 'Fresh Curd',
        unit: '400 g',
        imageEmoji: '🥄',
        price: 35,
        categoryId: 'dairy',
      ),
      Product(
        id: 'paneer',
        name: 'Paneer',
        unit: '200 g',
        imageEmoji: '🧀',
        price: 85,
        categoryId: 'dairy',
        rating: 4.3,
      ),

      // Snacks
      Product(
        id: 'chips',
        name: 'Potato Chips',
        unit: '90 g',
        imageEmoji: '🍟',
        price: 20,
        categoryId: 'snacks',
        isBestSeller: true,
      ),
      Product(
        id: 'cookie',
        name: 'Choco Cookies',
        unit: '200 g',
        imageEmoji: '🍪',
        price: 45,
        originalPrice: 55,
        categoryId: 'snacks',
        rating: 4.6,
      ),
      Product(
        id: 'namkeen',
        name: 'Mixed Namkeen',
        unit: '150 g',
        imageEmoji: '🥜',
        price: 35,
        categoryId: 'snacks',
      ),

      // Beverages
      Product(
        id: 'coke',
        name: 'Cola Can',
        unit: '330 ml',
        imageEmoji: '🥤',
        price: 40,
        categoryId: 'beverages',
        rating: 4.1,
      ),
      Product(
        id: 'water',
        name: 'Mineral Water',
        unit: '1 L',
        imageEmoji: '💧',
        price: 20,
        categoryId: 'beverages',
      ),
      Product(
        id: 'juice',
        name: 'Mango Juice',
        unit: '1 L',
        imageEmoji: '🧃',
        price: 99,
        originalPrice: 120,
        categoryId: 'beverages',
        isBestSeller: true,
      ),

      // Bakery
      Product(
        id: 'bread',
        name: 'Wheat Bread',
        unit: '400 g',
        imageEmoji: '🍞',
        price: 45,
        categoryId: 'bakery',
        rating: 4.2,
      ),
      Product(
        id: 'cake',
        name: 'Chocolate Cake',
        unit: '500 g',
        imageEmoji: '🎂',
        price: 299,
        originalPrice: 399,
        categoryId: 'bakery',
      ),

      // Grocery
      Product(
        id: 'rice',
        name: 'Basmati Rice',
        unit: '1 kg',
        imageEmoji: '🍚',
        price: 145,
        originalPrice: 165,
        categoryId: 'grocery',
        rating: 4.5,
      ),
      Product(
        id: 'oil',
        name: 'Cooking Oil',
        unit: '1 L',
        imageEmoji: '🫒',
        price: 180,
        categoryId: 'grocery',
      ),
      Product(
        id: 'atta',
        name: 'Wheat Flour',
        unit: '5 kg',
        imageEmoji: '🌾',
        price: 249,
        categoryId: 'grocery',
        isBestSeller: true,
      ),

      // Frozen
      Product(
        id: 'icecream',
        name: 'Ice Cream',
        unit: '500 ml',
        imageEmoji: '🍦',
        price: 149,
        originalPrice: 199,
        categoryId: 'frozen',
        rating: 4.8,
        isBestSeller: true,
      ),
    ];
  }
}
