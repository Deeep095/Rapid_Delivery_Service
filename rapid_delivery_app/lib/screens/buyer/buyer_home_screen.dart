import 'package:flutter/material.dart';
import '../../models.dart';
import '../../api_service.dart';
import '../../data_repository.dart';
import '../../location_sheet.dart';
import '../../widgets/widgets.dart';
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
  List<ProductCategory> _categories = [];
  List<PromoBanner> _banners = [];
  String _selectedCategoryId = 'all';

  final Map<String, int> _cart = {};
  final Map<String, int> _stockLevels = {};

  String _warehouseInfo = "Select a location to start";
  String _activeWarehouseId = "";
  bool _isLoading = true;
  bool _deliveryAvailable =
      false; // Track if delivery is available at current location

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // Load categories and banners
    _categories = DataRepository.getCategories();
    _banners = DataRepository.getBanners();

    // Load product catalog
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

  void _filterByCategory(String categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;

      // Start with products that have stock at current warehouse
      List<Product> baseProducts =
          _deliveryAvailable
              ? _products.where((p) => (_stockLevels[p.id] ?? 0) > 0).toList()
              : [];

      if (categoryId == 'all') {
        _filteredProducts = baseProducts;
      } else {
        _filteredProducts =
            baseProducts.where((p) => p.categoryId == categoryId).toList();
      }
      // Also apply search filter if active
      if (_searchController.text.isNotEmpty) {
        _runProductSearch(_searchController.text);
      }
    });
  }

  void _runProductSearch(String query) {
    setState(() {
      // Start with products that have stock at current warehouse
      List<Product> inStock =
          _deliveryAvailable
              ? _products.where((p) => (_stockLevels[p.id] ?? 0) > 0).toList()
              : [];

      List<Product> base =
          _selectedCategoryId == 'all'
              ? inStock
              : inStock
                  .where((p) => p.categoryId == _selectedCategoryId)
                  .toList();

      if (query.isEmpty) {
        _filteredProducts = base;
      } else {
        _filteredProducts =
            base
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
      _deliveryAvailable = false;
      _stockLevels.clear();
      _cart.clear(); // Clear cart when location changes
    });

    // Probe first item to check if any warehouse is nearby
    var probe = await ApiService.checkStock(
      "apple",
      _currentLocation!.lat,
      _currentLocation!.lon,
    );

    if (probe['available'] == true) {
      double dist = probe['distance_km'];
      setState(() {
        _activeWarehouseId = probe['warehouse_id'];
        _deliveryAvailable = true;
        _warehouseInfo =
            "⚡ Delivery from $_activeWarehouseId (${dist.toStringAsFixed(1)} km)";
      });

      // Fetch stock for all products from the nearest warehouse
      for (var p in _products) {
        final result = await ApiService.checkStock(
          p.id,
          _currentLocation!.lat,
          _currentLocation!.lon,
        );
        if (result['available'] == true &&
            result['warehouse_id'] == _activeWarehouseId) {
          _stockLevels[p.id] = result['quantity'] ?? 0;
        } else {
          _stockLevels[p.id] = 0;
        }
      }

      // Filter products to only show those with stock > 0 at this warehouse
      setState(() {
        _filteredProducts =
            _products.where((p) {
              return (_stockLevels[p.id] ?? 0) > 0;
            }).toList();
      });
    } else {
      setState(() {
        _activeWarehouseId = "";
        _deliveryAvailable = false;
        _warehouseInfo = "🚫 No delivery available in your area";
        _filteredProducts = []; // Hide all products when no delivery
        _stockLevels.clear();
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
    // Block cart access when no delivery is available
    if (!_deliveryAvailable || _activeWarehouseId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No delivery available at your location. Please change your address.",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

  double get _totalCartAmount {
    double total = 0;
    for (var entry in _cart.entries) {
      final product = _products.firstWhere((p) => p.id == entry.key);
      total += product.price * entry.value;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: SafeArea(
        child:
            _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0C831F)),
                )
                : Column(
                  children: [
                    // Delivery Address Bar
                    DeliveryAddressBar(
                      currentLocation: _currentLocation,
                      deliveryInfo: _warehouseInfo,
                      onChangeLocation: _showLocationSheet,
                    ),
                    // Main Content
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshStock,
                        color: const Color(0xFF0C831F),
                        child: CustomScrollView(
                          slivers: [
                            _buildSearchBar(),
                            _buildBannerSection(),
                            _buildCategorySection(),
                            _buildWarehouseInfo(),
                            _buildSectionHeader(),
                            _buildProductGrid(),
                          ],
                        ),
                      ),
                    ),
                    // Cart Bottom Bar
                    CartBottomBar(
                      itemCount: _totalCartItems,
                      totalAmount: _totalCartAmount,
                      onViewCart: _openCart,
                    ),
                  ],
                ),
      ),
      // Top action buttons
      appBar: _buildAppBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0C831F),
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Text(
            'Rapid',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '10 min',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long, color: Colors.white),
          onPressed: _openOrders,
          tooltip: 'Order History',
        ),
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Profile',
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: _searchController,
          onChanged: _runProductSearch,
          decoration: InputDecoration(
            hintText: 'Search for groceries, snacks & more...',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0C831F)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: BannerCarousel(banners: _banners),
      ),
    );
  }

  Widget _buildCategorySection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: CategoryChips(
          categories: _categories,
          selectedCategoryId: _selectedCategoryId,
          onCategorySelected: _filterByCategory,
        ),
      ),
    );
  }

  Widget _buildWarehouseInfo() {
    if (_warehouseInfo.isEmpty || _currentLocation == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              _activeWarehouseId.isNotEmpty
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFF3E0),
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
            Expanded(
              child: Text(
                _warehouseInfo,
                style: TextStyle(
                  color:
                      _activeWarehouseId.isNotEmpty
                          ? Colors.green[800]
                          : Colors.orange[800],
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    String title = 'All Products';
    if (_selectedCategoryId != 'all') {
      final cat = _categories.firstWhere((c) => c.id == _selectedCategoryId);
      title = cat.name;
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              '${_filteredProducts.length} items',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('🔍', style: TextStyle(fontSize: 48)),
              SizedBox(height: 16),
              Text(
                'No products found',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.68,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final product = _filteredProducts[index];
          return ProductCard(
            product: product,
            quantity: _cart[product.id] ?? 0,
            stockLevel: _stockLevels[product.id] ?? 0,
            onIncrement: () => _updateCart(product.id, 1),
            onDecrement: () => _updateCart(product.id, -1),
          );
        }, childCount: _filteredProducts.length),
      ),
    );
  }
}
