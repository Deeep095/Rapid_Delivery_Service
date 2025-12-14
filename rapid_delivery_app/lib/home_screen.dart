import 'package:flutter/material.dart';
import 'models.dart';
import 'api_service.dart';
import 'data_repository.dart';
import 'location_sheet.dart';
import 'orders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- STATE ---
  UserLocation? _currentLocation; // Nullable: Forces user to select first
  List<Product> _products = [];

  // NEW: List to store search results
  List<Product> _filteredProducts = [];

  final Map<String, int> _cart = {};
  final Map<String, int> _stockLevels = {};

  String _warehouseInfo = "Select a location to start";
  String _activeWarehouseId = "";
  bool _isLoading = true;

  // NEW: Controller for search input
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Fetch Catalog
    var catalog = await DataRepository.fetchCatalog();
    setState(() {
      _products = catalog;
      _filteredProducts = catalog; // NEW: Initially show all products
      _isLoading = false;
    });

    // 2. Prompt Location immediately if none set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationSheet();
    });
  }

  // --- LOGIC ---

  // NEW: Search Logic
  void _runProductSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts =
            _products
                .where(
                  (p) => p.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
      }
    });
  }

  Future<void> _refreshStock() async {
    if (_currentLocation == null) return;

    setState(() {
      _isLoading = true;
      _warehouseInfo = "Checking availability...";
    });

    // Probe
    var probe = await ApiService.checkStock(
      "apple",
      _currentLocation!.lat,
      _currentLocation!.lon,
    );

    if (probe['available'] == true) {
      double dist = probe['distance_km'];
      setState(() {
        _activeWarehouseId = probe['warehouse_id'];
        _warehouseInfo =
            "⚡ Delivery from $_activeWarehouseId (${dist.toStringAsFixed(1)} km)";
      });
    } else {
      setState(() {
        _activeWarehouseId = "";
        _warehouseInfo = "🚫 No delivery available here";
      });
    }

    // Update all items
    for (var p in _products) {
      var data = await ApiService.checkStock(
        p.id,
        _currentLocation!.lat,
        _currentLocation!.lon,
      );
      _stockLevels[p.id] = (data['available'] == true) ? data['quantity'] : 0;
    }

    setState(() => _isLoading = false);
  }

  void _setLocation(UserLocation loc) {
    setState(() {
      _currentLocation = loc;
      _cart.clear();
    });
    _refreshStock();
  }

  void _updateCart(String itemId, int change) {
    int currentQty = _cart[itemId] ?? 0;
    int maxStock = _stockLevels[itemId] ?? 0;
    int newQty = currentQty + change;

    if (newQty < 0) newQty = 0;
    if (newQty > maxStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Max stock limit reached!"),
          backgroundColor: Colors.red,
          duration: Duration(milliseconds: 500),
        ),
      );
      return;
    }

    setState(() {
      if (newQty == 0)
        _cart.remove(itemId);
      else
        _cart[itemId] = newQty;
    });
  }

  // --- UI COMPONENTS ---

  void _showLocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocationSearchSheet(onLocationSelected: _setLocation),
    );
  }

  void _showBillSummary() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder:
                (_, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        "Order Summary",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children:
                              _cart.entries.map((e) {
                                final p = _products.firstWhere(
                                  (prod) => prod.id == e.key,
                                );
                                return ListTile(
                                  leading: Text(
                                    p.imageEmoji,
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  title: Text(p.name),
                                  subtitle: Text("${p.unit} x ${e.value}"),
                                  trailing: Text(
                                    "\$${(p.price * e.value).toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                      const Divider(),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0C831F),
                          ),
                          onPressed: _placeOrder,
                          child: const Text(
                            "PLACE ORDER",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _placeOrder() async {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const Center(
            child: CircularProgressIndicator(color: Color(0xFF0C831F)),
          ),
    );

    List<Map<String, dynamic>> itemsPayload = [];
    _cart.forEach((key, qty) {
      itemsPayload.add({
        "item_id": key,
        "warehouse_id": _activeWarehouseId,
        "quantity": qty,
      });
    });

    // Use constant user ID for consistency
    var result = await ApiService.placeOrder("mobile_user_1", itemsPayload);

    Navigator.pop(context); // Close loader

    if (result.containsKey('order_id')) {
      showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text("Success"),
              content: Text("Order #${result['order_id']} placed!"),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() => _cart.clear());
                    _refreshStock();
                  },
                  child: const Text("OK"),
                ),
              ],
            ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed: ${result['error']}")));
    }
  }

  // --- RESPONSIVE GRID BUILDER ---
  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    // Web/Desktop: 4 columns, Mobile: 2 columns
    int crossAxisCount = screenWidth > 600 ? 4 : 2;
    double childAspectRatio =
        screenWidth > 600 ? 0.9 : 0.75; // Adjust ratio for web

    int totalItems = _cart.values.fold(0, (sum, qty) => sum + qty);
    double totalPrice = 0;
    _cart.forEach((key, qty) {
      final product = _products.firstWhere((p) => p.id == key);
      totalPrice += (product.price * qty);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: GestureDetector(
          onTap: _showLocationSheet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFF0C831F),
                    size: 18,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _currentLocation?.name ?? "Select Location",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.black),
                ],
              ),
              Text(
                _currentLocation?.address ?? "Click to set delivery address",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // NEW: Orders Button
          IconButton(
            icon: const CircleAvatar(
              backgroundColor: Color(0xFFE8F5E9),
              child: Icon(
                Icons.receipt_long,
                color: Color(0xFF0C831F),
                size: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const OrdersScreen()),
              );
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // Status Bar
          if (_currentLocation != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color:
                  _activeWarehouseId.isEmpty
                      ? Colors.red[50]
                      : const Color(0xFFE8F5E9),
              child: Text(
                _warehouseInfo,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color:
                      _activeWarehouseId.isEmpty
                          ? Colors.red
                          : Colors.green[800],
                ),
              ),
            ),

          // NEW: SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _runProductSearch,
              decoration: InputDecoration(
                hintText: 'Search "milk" or "apple"',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // Responsive Grid
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredProducts.isEmpty
                    ? const Center(child: Text("No items found"))
                    : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      // CHANGED: Use _filteredProducts
                      itemCount: _filteredProducts.length,
                      itemBuilder:
                          (ctx, i) => _buildProductCard(_filteredProducts[i]),
                    ),
          ),
        ],
      ),
      bottomNavigationBar:
          totalItems > 0
              ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C831F),
                      padding: const EdgeInsets.all(15),
                    ),
                    onPressed: _showBillSummary,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "$totalItems ITEMS | \$${totalPrice.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          "View Cart >",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              : null,
    );
  }

  Widget _buildProductCard(Product p) {
    int qty = _cart[p.id] ?? 0;
    int stock = _stockLevels[p.id] ?? 0;
    bool isOutOfStock = stock == 0 && !_isLoading;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(p.imageEmoji, style: const TextStyle(fontSize: 50)),
            ),
          ), // Icon size
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  p.unit,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "\$${p.price}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (isOutOfStock)
                      const Text(
                        "SOLD OUT",
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    else if (qty == 0)
                      SizedBox(
                        height: 30,
                        width: 70,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0C831F),
                            side: const BorderSide(color: Color(0xFF0C831F)),
                          ),
                          onPressed: () => _updateCart(p.id, 1),
                          child: const Text("ADD"),
                        ),
                      )
                    else
                      Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C831F),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _updateCart(p.id, -1),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.remove,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                            Text(
                              "$qty",
                              style: const TextStyle(color: Colors.white),
                            ),
                            InkWell(
                              onTap: () => _updateCart(p.id, 1),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
