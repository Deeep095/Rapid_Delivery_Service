import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'models.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return "http://localhost";
    return "http://10.0.2.2"; 
  }

  // 1. Backend: Check Stock
  static Future<Map<String, dynamic>> checkStock(String itemId, double lat, double lon) async {
    final url = Uri.parse("$baseUrl:8000/availability?item_id=$itemId&lat=$lat&lon=$lon");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("Backend Error: $e");
    }
    return {"available": false};
  }

  // 2. Backend: Place Order
  static Future<Map<String, dynamic>> placeOrder(String userId, List<Map<String, dynamic>> items) async {
    final url = Uri.parse("$baseUrl:8001/order");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "customer_id": userId,
          "items": items
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return {"error": "Server error: ${response.statusCode}"};
      }
    } catch (e) {
      return {"error": "Connection Failed: $e"};
    }
  }

  // 3. OpenStreetMap: Search Locations
  static Future<List<dynamic>> searchLocations(String query) async {
    if (query.length < 3) return [];
    try {
      final url = Uri.parse("https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5");
      final response = await http.get(url, headers: {'User-Agent': 'RapidDeliveryApp/1.0'});
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      print("OSM Error: $e");
    }
    return [];
  }

  static Future<List<dynamic>> fetchOrders(String userId) async {
    final url = Uri.parse("$baseUrl:8001/orders/$userId");
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
}