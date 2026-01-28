// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:flutter/foundation.dart' show kIsWeb;

// void main() {
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Rapid Delivery',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         primaryColor: const Color(0xFF0C831F), // Blinkit Green
//         scaffoldBackgroundColor: const Color(
//           0xFFF4F6FB,
//         ), // Light Grey Background
//         useMaterial3: true,
//         colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0C831F)),
//         appBarTheme: const AppBarTheme(
//           backgroundColor: Colors.white,
//           elevation: 0,
//         ),
//       ),
//       home: const DeliveryHomeScreen(),
//     );
//   }
// }

// // --- DATA MODEL ---
// class Product {
//   final String id;
//   final String name;
//   final String unit;
//   final String imageEmoji;
//   final double price;

//   Product({
//     required this.id,
//     required this.name,
//     required this.unit,
//     required this.imageEmoji,
//     required this.price,
//   });
// }

// class DeliveryHomeScreen extends StatefulWidget {
//   const DeliveryHomeScreen({super.key});

//   @override
//   State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
// }

// class _DeliveryHomeScreenState extends State<DeliveryHomeScreen> {
//   // --- 1. DATA ---
//   final List<Product> _allProducts = [
//     Product(
//       id: "apple",
//       name: "Red Apple",
//       unit: "1 kg",
//       imageEmoji: "🍎",
//       price: 2.50,
//     ),
//     Product(
//       id: "milk",
//       name: "Fresh Milk",
//       unit: "1 L",
//       imageEmoji: "🥛",
//       price: 1.20,
//     ),
//     Product(
//       id: "bread",
//       name: "Wheat Bread",
//       unit: "1 pkt",
//       imageEmoji: "🍞",
//       price: 3.00,
//     ),
//     Product(
//       id: "eggs",
//       name: "Farm Eggs",
//       unit: "12 pcs",
//       imageEmoji: "🥚",
//       price: 4.50,
//     ),
//     Product(
//       id: "chips",
//       name: "Potato Chips",
//       unit: "50g",
//       imageEmoji: "🍟",
//       price: 1.50,
//     ),
//     Product(
//       id: "coke",
//       name: "Cola Can",
//       unit: "330ml",
//       imageEmoji: "🥤",
//       price: 1.00,
//     ),
//     Product(
//       id: "banana",
//       name: "Bananas",
//       unit: "1 dz",
//       imageEmoji: "🍌",
//       price: 1.80,
//     ),
//     Product(
//       id: "cookie",
//       name: "Cookies",
//       unit: "200g",
//       imageEmoji: "🍪",
//       price: 2.50,
//     ),
//   ];

//   List<Product> _filteredProducts = [];
//   String _searchQuery = "";

//   // --- STATE ---
//   final Map<String, int> _cart = {};
//   final Map<String, int> _stockLevels = {};

//   bool _isLoadingStock = true;
//   String _deliveryAddress = "Home - 123, Manhattan, NY";
//   String _activeWarehouse = "Finding store...";

//   // --- NETWORKING ---
//   String get _baseUrl {
//     if (kIsWeb) return "http://localhost";
//     return "http://10.0.2.2";
//   }

//   @override
//   void initState() {
//     super.initState();
//     _filteredProducts = _allProducts; // Init with all products
//     _fetchMenuStock();
//   }

//   // --- 2. LOGIC ---

//   void _runSearch(String query) {
//     setState(() {
//       _searchQuery = query;
//       if (query.isEmpty) {
//         _filteredProducts = _allProducts;
//       } else {
//         _filteredProducts =
//             _allProducts
//                 .where(
//                   (p) => p.name.toLowerCase().contains(query.toLowerCase()),
//                 )
//                 .toList();
//       }
//     });
//   }

//   Future<void> _fetchMenuStock() async {
//     // Simulating checking stock for all items
//     for (var p in _allProducts) {
//       final url = Uri.parse(
//         "$_baseUrl:8000/availability?item_id=${p.id}&lat=40.7128&lon=-74.0060",
//       );
//       try {
//         final response = await http.get(url);
//         if (response.statusCode == 200) {
//           final data = json.decode(response.body);
//           if (data['available'] == true) {
//             setState(() {
//               _stockLevels[p.id] = data['quantity'];
//               _activeWarehouse = data['warehouse_id'];
//             });
//           } else {
//             _stockLevels[p.id] = 0;
//           }
//         }
//       } catch (e) {
//         // Silent fail for UI smoothness, assumes 0 stock
//       }
//     }
//     setState(() => _isLoadingStock = false);
//   }

//   // --- 3. CART ACTIONS ---

//   void _updateCart(String itemId, int change) {
//     int currentQty = _cart[itemId] ?? 0;
//     int maxStock = _stockLevels[itemId] ?? 0;
//     int newQty = currentQty + change;

//     if (newQty < 0) newQty = 0;
//     if (newQty > maxStock) {
//       ScaffoldMessenger.of(context).hideCurrentSnackBar();
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text("Maximum stock limit reached!"),
//           duration: Duration(milliseconds: 800),
//         ),
//       );
//       return;
//     }

//     setState(() {
//       if (newQty == 0) {
//         _cart.remove(itemId);
//       } else {
//         _cart[itemId] = newQty;
//       }
//     });
//   }

//   void _showLocationPicker() {
//     showModalBottomSheet(
//       context: context,
//       builder: (ctx) {
//         return Container(
//           padding: const EdgeInsets.all(20),
//           height: 250,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 "Select Location",
//                 style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
//               ),
//               const SizedBox(height: 15),
//               ListTile(
//                 leading: const Icon(Icons.home, color: Colors.green),
//                 title: const Text("Home"),
//                 subtitle: const Text("123, Manhattan, NY"),
//                 onTap: () {
//                   setState(
//                     () => _deliveryAddress = "Home - 123, Manhattan, NY",
//                   );
//                   Navigator.pop(context);
//                   _fetchMenuStock(); // Refetch stock for new location
//                 },
//               ),
//               ListTile(
//                 leading: const Icon(Icons.work, color: Colors.blue),
//                 title: const Text("Office"),
//                 subtitle: const Text("Soho Square, London (Demo)"),
//                 onTap: () {
//                   setState(() => _deliveryAddress = "Office - Soho, London");
//                   Navigator.pop(context);
//                   // In real app, we'd pass London coordinates here to _fetchMenuStock
//                 },
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }

//   // --- 4. CHECKOUT SHEET ---
//   void _showCartSheet() {
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder:
//           (ctx) => DraggableScrollableSheet(
//             initialChildSize: 0.6,
//             minChildSize: 0.4,
//             maxChildSize: 0.9,
//             builder: (_, controller) {
//               return Container(
//                 decoration: const BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//                 ),
//                 padding: const EdgeInsets.all(20),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     const Text(
//                       "Bill Summary",
//                       style: TextStyle(
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                     const SizedBox(height: 20),
//                     Expanded(
//                       child: ListView(
//                         controller: controller,
//                         children:
//                             _cart.entries.map((entry) {
//                               final product = _allProducts.firstWhere(
//                                 (p) => p.id == entry.key,
//                               );
//                               return Padding(
//                                 padding: const EdgeInsets.symmetric(
//                                   vertical: 8.0,
//                                 ),
//                                 child: Row(
//                                   mainAxisAlignment:
//                                       MainAxisAlignment.spaceBetween,
//                                   children: [
//                                     Text(
//                                       "${product.imageEmoji} ${product.name} x ${entry.value}",
//                                     ),
//                                     Text(
//                                       "\$${(product.price * entry.value).toStringAsFixed(2)}",
//                                       style: const TextStyle(
//                                         fontWeight: FontWeight.bold,
//                                       ),
//                                     ),
//                                   ],
//                                 ),
//                               );
//                             }).toList(),
//                       ),
//                     ),
//                     const Divider(),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         const Text(
//                           "Grand Total",
//                           style: TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                         Text(
//                           "\$${_calculateTotal().toStringAsFixed(2)}",
//                           style: const TextStyle(
//                             fontSize: 18,
//                             fontWeight: FontWeight.bold,
//                             color: Colors.green,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 20),
//                     SizedBox(
//                       width: double.infinity,
//                       height: 50,
//                       child: ElevatedButton(
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: const Color(0xFF0C831F),
//                           foregroundColor: Colors.white,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(10),
//                           ),
//                         ),
//                         onPressed: () {
//                           Navigator.pop(context); // Close sheet
//                           _placeOrder(); // Trigger API
//                         },
//                         child: const Text(
//                           "PAY & ORDER",
//                           style: TextStyle(
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               );
//             },
//           ),
//     );
//   }

//   double _calculateTotal() {
//     double total = 0;
//     _cart.forEach((key, qty) {
//       final product = _allProducts.firstWhere((p) => p.id == key);
//       total += (product.price * qty);
//     });
//     return total;
//   }

//   Future<void> _placeOrder() async {
//     // Show Loading
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (_) => const Center(child: CircularProgressIndicator()),
//     );

//     List<Map<String, dynamic>> itemsPayload = [];
//     _cart.forEach((itemId, qty) {
//       itemsPayload.add({
//         "item_id": itemId,
//         "warehouse_id": _activeWarehouse,
//         "quantity": qty,
//       });
//     });

//     final url = Uri.parse("$_baseUrl:8001/order");
//     try {
//       final response = await http.post(
//         url,
//         headers: {"Content-Type": "application/json"},
//         body: json.encode({
//           "customer_id": "user_mobile",
//           "items": itemsPayload,
//         }),
//       );

//       Navigator.pop(context); // Close Loader

//       if (response.statusCode == 200) {
//         final data = json.decode(response.body);
//         _showSuccessAnimation(data['order_id']);
//       } else {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text("Failed: ${response.body}")));
//       }
//     } catch (e) {
//       Navigator.pop(context);
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text("Error: $e")));
//     }
//   }

//   void _showSuccessAnimation(int orderId) {
//     showDialog(
//       context: context,
//       builder:
//           (ctx) => AlertDialog(
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20),
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Icon(Icons.check_circle, color: Colors.green, size: 60),
//                 const SizedBox(height: 15),
//                 const Text(
//                   "Order Placed!",
//                   style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
//                 ),
//                 Text(
//                   "Order ID: #$orderId",
//                   style: TextStyle(color: Colors.grey[600]),
//                 ),
//                 const SizedBox(height: 20),
//                 ElevatedButton(
//                   onPressed: () {
//                     setState(() {
//                       _cart.clear();
//                       _fetchMenuStock();
//                     });
//                     Navigator.pop(ctx);
//                   },
//                   child: const Text("Done"),
//                 ),
//               ],
//             ),
//           ),
//     );
//   }

//   // --- 5. UI BUILD ---

//   @override
//   Widget build(BuildContext context) {
//     int totalItems = _cart.values.fold(0, (sum, qty) => sum + qty);
//     double totalPrice = _calculateTotal();

//     return Scaffold(
//       appBar: AppBar(
//         titleSpacing: 0,
//         leading: const Icon(Icons.location_on, color: Color(0xFF0C831F)),
//         title: GestureDetector(
//           onTap: _showLocationPicker,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 _deliveryAddress.split(' - ')[0],
//                 style: const TextStyle(
//                   fontWeight: FontWeight.w800,
//                   fontSize: 16,
//                   color: Colors.black,
//                 ),
//               ),
//               Text(
//                 _deliveryAddress,
//                 style: TextStyle(fontSize: 12, color: Colors.grey[700]),
//               ),
//             ],
//           ),
//         ),
//         actions: [
//           IconButton(
//             icon: const CircleAvatar(
//               backgroundColor: Colors.grey,
//               radius: 15,
//               child: Icon(Icons.person, size: 20, color: Colors.white),
//             ),
//             onPressed: () {},
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           // SEARCH BAR
//           Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//             child: TextField(
//               onChanged: _runSearch,
//               decoration: InputDecoration(
//                 prefixIcon: const Icon(Icons.search, color: Colors.grey),
//                 hintText: 'Search "milk"',
//                 filled: true,
//                 fillColor: Colors.white,
//                 contentPadding: const EdgeInsets.symmetric(vertical: 0),
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide: BorderSide.none,
//                 ),
//               ),
//             ),
//           ),

//           // STORE INFO
//           if (_activeWarehouse.contains("Loading") ||
//               _activeWarehouse == "Finding store...")
//             const LinearProgressIndicator(minHeight: 2, color: Colors.green)
//           else
//             Container(
//               width: double.infinity,
//               color: const Color(0xFFE8F5E9),
//               padding: const EdgeInsets.all(8),
//               child: Text(
//                 "⚡ Delivery from $_activeWarehouse in 10 mins",
//                 textAlign: TextAlign.center,
//                 style: TextStyle(
//                   color: Colors.green[800],
//                   fontSize: 12,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),

//           // GRID
//           Expanded(
//             child:
//                 _filteredProducts.isEmpty
//                     ? const Center(child: Text("No items found"))
//                     : GridView.builder(
//                       padding: const EdgeInsets.all(12),
//                       itemCount: _filteredProducts.length,
//                       gridDelegate:
//                           const SliverGridDelegateWithFixedCrossAxisCount(
//                             crossAxisCount: 2, // 2 columns
//                             childAspectRatio: 0.82, // TALLER CARDS FIX
//                             crossAxisSpacing: 12,
//                             mainAxisSpacing: 12,
//                           ),
//                       itemBuilder:
//                           (ctx, i) => _buildProductCard(_filteredProducts[i]),
//                     ),
//           ),
//         ],
//       ),
//       bottomNavigationBar:
//           totalItems > 0
//               ? SafeArea(
//                 child: Padding(
//                   padding: const EdgeInsets.all(12.0),
//                   child: ElevatedButton(
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xFF0C831F),
//                       foregroundColor: Colors.white,
//                       padding: const EdgeInsets.symmetric(
//                         vertical: 12,
//                         horizontal: 16,
//                       ),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       elevation: 5,
//                     ),
//                     onPressed: _showCartSheet,
//                     child: Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         Column(
//                           mainAxisSize: MainAxisSize.min,
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Text(
//                               "$totalItems ITEMS",
//                               style: const TextStyle(
//                                 fontSize: 10,
//                                 fontWeight: FontWeight.w300,
//                               ),
//                             ),
//                             Text(
//                               "\$${totalPrice.toStringAsFixed(2)}",
//                               style: const TextStyle(
//                                 fontSize: 16,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ],
//                         ),
//                         const Row(
//                           children: [
//                             Text(
//                               "View Cart",
//                               style: TextStyle(fontWeight: FontWeight.bold),
//                             ),
//                             SizedBox(width: 5),
//                             Icon(Icons.arrow_right_alt),
//                           ],
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//               )
//               : null,
//     );
//   }

//   Widget _buildProductCard(Product p) {
//     int qty = _cart[p.id] ?? 0;
//     int stock = _stockLevels[p.id] ?? 0;
//     bool outOfStock = stock == 0 && !_isLoadingStock;

//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(15),
//         border: Border.all(color: Colors.grey.shade200),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // IMAGE
//           Expanded(
//             child: Center(
//               child: Text(p.imageEmoji, style: const TextStyle(fontSize: 55)),
//             ),
//           ),

//           // INFO
//           Padding(
//             padding: const EdgeInsets.all(10.0),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   p.name,
//                   style: const TextStyle(
//                     fontWeight: FontWeight.bold,
//                     fontSize: 14,
//                   ),
//                 ),
//                 Text(
//                   p.unit,
//                   style: TextStyle(color: Colors.grey[500], fontSize: 12),
//                 ),
//                 const SizedBox(height: 8),
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Text(
//                       "\$${p.price}",
//                       style: const TextStyle(
//                         fontWeight: FontWeight.w600,
//                         fontSize: 14,
//                       ),
//                     ),

//                     // BUTTONS
//                     outOfStock
//                         ? Container(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: 8,
//                             vertical: 4,
//                           ),
//                           decoration: BoxDecoration(
//                             color: Colors.grey[100],
//                             borderRadius: BorderRadius.circular(5),
//                           ),
//                           child: const Text(
//                             "NO STOCK",
//                             style: TextStyle(fontSize: 10, color: Colors.grey),
//                           ),
//                         )
//                         : qty == 0
//                         ? SizedBox(
//                           height: 30,
//                           width: 70,
//                           child: OutlinedButton(
//                             style: OutlinedButton.styleFrom(
//                               side: const BorderSide(color: Color(0xFF0C831F)),
//                               foregroundColor: const Color(0xFF0C831F),
//                               padding: EdgeInsets.zero,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(6),
//                               ),
//                             ),
//                             onPressed: () => _updateCart(p.id, 1),
//                             child: const Text(
//                               "ADD",
//                               style: TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 12,
//                               ),
//                             ),
//                           ),
//                         )
//                         : Container(
//                           height: 30,
//                           decoration: BoxDecoration(
//                             color: const Color(0xFF0C831F),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               InkWell(
//                                 onTap: () => _updateCart(p.id, -1),
//                                 child: const Padding(
//                                   padding: EdgeInsets.symmetric(horizontal: 8),
//                                   child: Icon(
//                                     Icons.remove,
//                                     color: Colors.white,
//                                     size: 14,
//                                   ),
//                                 ),
//                               ),
//                               Text(
//                                 "$qty",
//                                 style: const TextStyle(
//                                   color: Colors.white,
//                                   fontWeight: FontWeight.bold,
//                                   fontSize: 12,
//                                 ),
//                               ),
//                               InkWell(
//                                 onTap: () => _updateCart(p.id, 1),
//                                 child: const Padding(
//                                   padding: EdgeInsets.symmetric(horizontal: 8),
//                                   child: Icon(
//                                     Icons.add,
//                                     color: Colors.white,
//                                     size: 14,
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'screens/role_selection_screen.dart';

void main() {
  runApp(const RapidDeliveryApp());
}

class RapidDeliveryApp extends StatelessWidget {
  const RapidDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rapid Delivery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0C831F), // Blinkit Green
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C831F),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C831F),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const RoleSelectionScreen(),
    );
  }
}
