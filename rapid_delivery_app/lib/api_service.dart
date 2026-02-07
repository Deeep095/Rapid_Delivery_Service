import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'models.dart';
import 'aws_config.dart';

class ApiService {
  // =====================================================
  // CONFIGURATION
  // =====================================================

  /// Set to TRUE when deploying to AWS
  /// Set to FALSE for local Docker testing
  static const bool useAwsBackend = false;

  // =====================================================
  // BASE URLs - Automatically switches between AWS/Local
  // =====================================================
  static String get availabilityBaseUrl {
    if (useAwsBackend) {
      return AwsConfig.availabilityUrl;
    }
    // Local development
    if (kIsWeb) return "http://localhost:8000";
    return "http://10.0.2.2:8000"; // Android emulator
  }

  static String get orderBaseUrl {
    if (useAwsBackend) {
      return AwsConfig.orderUrl;
    }
    // Local development
    if (kIsWeb) return "http://localhost:8001";
    return "http://10.0.2.2:8001"; // Android emulator
  }

  // 1. Backend: Check Stock
  static Future<Map<String, dynamic>> checkStock(
    String itemId,
    double lat,
    double lon,
  ) async {
    // Note: Nginx rewrites /availability/XXX -> /XXX for the backend
    // So we call /availability/availability which becomes /availability
    final url = Uri.parse(
      "$availabilityBaseUrl/availability"
      "?item_id=$itemId&lat=$lat&lon=$lon",
    );

    print("DEBUG: Calling URL: $url");

    try {
      final response = await http
          .get(url) // Removed Content-Type header to avoid preflight issues
          .timeout(const Duration(seconds: 15));

      print("DEBUG: Response status: ${response.statusCode}");
      print("DEBUG: Response body: ${response.body}");

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"available": false, "error": "Status ${response.statusCode}"};
      }
    } catch (e) {
      print("Backend Error: $e");
      print("DEBUG: URL was: $url");
      return {"available": false, "error": e.toString()};
    }
  }

  // 2. Backend: Place Order
  static Future<Map<String, dynamic>> placeOrder(
    String userId,
    List<Map<String, dynamic>> items,
  ) async {
    // Note: Nginx rewrites /order/XXX -> /XXX for the backend
    final url = Uri.parse("$orderBaseUrl/orders");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({"customer_id": userId, "items": items}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        return {"error": "Server error: ${response.statusCode}"};
      }
    } catch (e) {
      return {"error": "Connection failed: $e"};
    }
  }

  // 3. OpenStreetMap: Search Locations
  static Future<List<dynamic>> searchLocations(String query) async {
    if (query.length < 3) return [];

    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search"
        "?q=$query&format=json&addressdetails=1&limit=5",
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'RapidDeliveryApp/1.0'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("OSM Error: $e");
    }

    return [];
  }

  // 4. Fetch Orders
  static Future<List<dynamic>> fetchOrders(String userId) async {
    final url = Uri.parse("$orderBaseUrl/orders/$userId");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Order History Error: $e");
    }

    return [];
  }

  // 5. Get Order History (for Buyer flow)
  static Future<List<Map<String, dynamic>>> getOrderHistory(
    String userId,
  ) async {
    final url = Uri.parse("$orderBaseUrl/orders/$userId");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print("Order History Error: $e");
    }

    return [];
  }

  // 6. Get Warehouses (for Manager flow)
  static Future<List<Map<String, dynamic>>> getWarehouses() async {
    final url = Uri.parse("$availabilityBaseUrl/warehouses");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print("Get Warehouses Error: $e");
    }

    return [];
  }

  // 7. Get Warehouse Inventory (for Manager flow)
  static Future<List<Map<String, dynamic>>> getWarehouseInventory(
    String warehouseId,
  ) async {
    final url = Uri.parse("$availabilityBaseUrl/inventory/$warehouseId");

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print("Get Inventory Error: $e");
    }

    return [];
  }

  // 8. Update Stock (for Manager flow)
  static Future<Map<String, dynamic>> updateStock({
    required String warehouseId,
    required String productId,
    required int newStock,
  }) async {
    final url = Uri.parse(
      "$availabilityBaseUrl/inventory/$warehouseId/$productId",
    );

    try {
      final response = await http
          .put(
            url,
            headers: {"Content-Type": "application/json"},
            body: json.encode({"stock": newStock}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Failed to update stock: ${response.statusCode}"};
      }
    } catch (e) {
      print("Update Stock Error: $e");
      return {"error": "Connection failed: $e"};
    }
  }

  // 9. Subscribe to SNS Notifications
  static Future<Map<String, dynamic>> subscribeToNotifications({
    required String warehouseId,
    required String email,
  }) async {
    final url = Uri.parse("$orderBaseUrl/subscribe");

    try {
      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: json.encode({"warehouse_id": warehouseId, "email": email}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Failed to subscribe: ${response.statusCode}"};
      }
    } catch (e) {
      print("Subscribe Error: $e");
      return {"error": "Connection failed: $e"};
    }
  }
}
