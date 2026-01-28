import 'dart:convert';
import 'package:http/http.dart' as http;
import '../aws_config.dart';

class InventoryService {
  static String get baseUrl => AwsConfig.availabilityUrl;

  /// Get list of all warehouses
  static Future<List<Map<String, dynamic>>> getWarehouses() async {
    try {
      final url = Uri.parse('$baseUrl/warehouses');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['warehouses'] ?? []);
      }
      return [];
    } catch (e) {
      print('Get Warehouses Error: $e');
      return [];
    }
  }

  /// Get inventory for a specific warehouse
  static Future<List<Map<String, dynamic>>> getWarehouseInventory(
    String warehouseId,
  ) async {
    try {
      final url = Uri.parse('$baseUrl/inventory/$warehouseId');
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['inventory'] ?? []);
      }
      return [];
    } catch (e) {
      print('Get Inventory Error: $e');
      return [];
    }
  }

  /// Update stock for a product in a warehouse
  static Future<Map<String, dynamic>> updateStock({
    required String warehouseId,
    required String productId,
    required int newStock,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/inventory/$warehouseId/$productId');
      final response = await http
          .put(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'stock': newStock}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'error': 'Failed to update stock: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Connection failed: $e'};
    }
  }

  /// Subscribe manager to SNS notifications for a warehouse
  static Future<Map<String, dynamic>> subscribeToNotifications({
    required String warehouseId,
    required String email,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/subscribe');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'warehouse_id': warehouseId,
              'email': email,
              'type': 'manager',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {'error': 'Failed to subscribe: ${response.statusCode}'};
    } catch (e) {
      return {'error': 'Connection failed: $e'};
    }
  }
}
