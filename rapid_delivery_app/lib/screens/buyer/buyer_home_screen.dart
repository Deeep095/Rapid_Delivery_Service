import 'package:flutter/material.dart';
import '../../models.dart';
import '../../api_service.dart';
import '../../data_repository.dart';
import '../../location_sheet.dart'; // Contains LocationSearchSheet
import 'cart_screen.dart';
import 'order_history_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  final String userEmail;
  final String userName;

  const BuyerHomeScreen({
    super.key,
    required this.userEmail,
    required this.userName,
  });

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  // --- STATE ---
  UserLocation? _currentLocation;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final Map<String, int> _cart = {};
  final Map<String, int> _stockLevels = {};

  String _warehouseInfo = "Select a location to start";
  String _activeWarehouseId = "";
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    var catalog = await DataRepository.fetchCatalog();
    setState(() {
      _products = catalog;
      _filteredProducts = catalog;
      _isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLocationSheet();
    });
  }

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

    // Probe first item
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

      // Fetch stock for all products
      for (var p in _products) {
        final result = await ApiService.checkStock(
          p.id,
          _currentLocation!.lat,
          _currentLocation!.lon,
        );
        if (result['available'] == true) {
          _stockLevels[p.id] = result['quantity'] ?? 0;
        } else {
          _stockLevels[p.id] = 0;
        }
      }
    } else {
      setState(() {
        _activeWarehouseId = "";
        _warehouseInfo = "🚫 No delivery available here";
      });
    }

    setState(() => _isLoading = false);
  }

  void _updateCart(String itemId, int change) {
    int currentQty = _cart[itemId] ?? 0;
    int maxStock = _stockLevels[itemId] ?? 0;
    int newQty = currentQty + change;

    if (newQty < 0) newQty = 0;
    if (newQty > maxStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Maximum stock limit reached!"),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    setState(() {
      if (newQty == 0) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = newQty;
      }
    });
  }

  void _showLocationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => LocationSearchSheet(
            onLocationSelected: (location) {
              setState(() => _currentLocation = location);
              _refreshStock();
            },
          ),
    );
  }

  void _openCart() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Your cart is empty!")));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => CartScreen(
              cart: _cart,
              products: _products,
              warehouseId: _activeWarehouseId,
              userEmail: widget.userEmail,
              userName: widget.userName,
              onOrderPlaced: () {
                setState(() => _cart.clear());
                _refreshStock();
              },
            ),
      ),
    );
  }

  void _openOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => OrderHistoryScreen(userEmail: widget.userEmail),
      ),
    );
  }

  int get _totalCartItems => _cart.values.fold(0, (sum, qty) => sum + qty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: _buildAppBar(),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _refreshStock,
                child: CustomScrollView(
                  slivers: [
                    _buildSearchBar(),
                    _buildWarehouseInfo(),
                    _buildProductGrid(),
                  ],
                ),
              ),
      floatingActionButton:
          _cart.isNotEmpty
              ? FloatingActionButton.extended(
                onPressed: _openCart,
                backgroundColor: const Color(0xFF0C831F),
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                label: Text(
                  '$_totalCartItems items',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
              : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0C831F),
      elevation: 0,
      title: GestureDetector(
        onTap: _showLocationSheet,
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentLocation?.name ?? 'Select Location',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentLocation?.address ??
                        'Tap to choose delivery address',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long, color: Colors.white),
          onPressed: _openOrders,
          tooltip: 'Order History',
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Switch Role',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _searchController,
          onChanged: _runProductSearch,
          decoration: InputDecoration(
            hintText: 'Search products...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon:
                _searchController.text.isNotEmpty
                    ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _runProductSearch('');
                      },
                    )
                    : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarehouseInfo() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              _activeWarehouseId.isNotEmpty
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _activeWarehouseId.isNotEmpty ? Icons.check_circle : Icons.info,
              color:
                  _activeWarehouseId.isNotEmpty ? Colors.green : Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _warehouseInfo,
              style: TextStyle(
                color:
                    _activeWarehouseId.isNotEmpty
                        ? Colors.green[800]
                        : Colors.orange[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: Text('No products found')),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final product = _filteredProducts[index];
          return _ProductCard(
            product: product,
            stock: _stockLevels[product.id] ?? 0,
            cartQty: _cart[product.id] ?? 0,
            onAdd: () => _updateCart(product.id, 1),
            onRemove: () => _updateCart(product.id, -1),
          );
        }, childCount: _filteredProducts.length),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final int stock;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ProductCard({
    required this.product,
    required this.stock,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool isOutOfStock = stock <= 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Image/Emoji
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      product.imageEmoji,
                      style: TextStyle(
                        fontSize: 48,
                        color: isOutOfStock ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (isOutOfStock)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'OUT OF STOCK',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Product Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    product.unit,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹${product.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C831F),
                          fontSize: 16,
                        ),
                      ),
                      if (!isOutOfStock)
                        cartQty > 0
                            ? _QuantitySelector(
                              quantity: cartQty,
                              onAdd: onAdd,
                              onRemove: onRemove,
                            )
                            : GestureDetector(
                              onTap: onAdd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0C831F),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'ADD',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantitySelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _QuantitySelector({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C831F),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.remove, color: Colors.white, size: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
