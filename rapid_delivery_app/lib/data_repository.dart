import 'models.dart';

class DataRepository {
  // Simulates fetching the master product catalog
  static Future<List<Product>> fetchCatalog() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    return [
      Product(id: "apple", name: "Red Apple", unit: "1 kg", imageEmoji: "🍎", price: 2.50),
      Product(id: "milk", name: "Fresh Milk", unit: "1 L", imageEmoji: "🥛", price: 1.20),
      Product(id: "bread", name: "Wheat Bread", unit: "1 pkt", imageEmoji: "🍞", price: 3.00),
      Product(id: "coke", name: "Cola Can", unit: "330ml", imageEmoji: "🥤", price: 1.00),
      Product(id: "chips", name: "Chips", unit: "50g", imageEmoji: "🍟", price: 1.50),
      Product(id: "eggs", name: "Farm Eggs", unit: "6 pcs", imageEmoji: "🥚", price: 4.50),
      Product(id: "banana", name: "Bananas", unit: "1 dz", imageEmoji: "🍌", price: 1.80),
      Product(id: "cookie", name: "Cookies", unit: "200g", imageEmoji: "🍪", price: 2.50),
    ];
  }
}