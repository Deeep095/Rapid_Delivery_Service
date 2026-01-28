import 'package:flutter/material.dart';
import '../../services/inventory_service.dart';
import '../../services/auth_service.dart';
import '../role_selection_screen.dart';
import 'inventory_screen.dart';

class ManagerHomeScreen extends StatefulWidget {
  final String userEmail;
  final String userName;
  final String? warehouseId; // Assigned warehouse (if single warehouse manager)
  final String? warehouseName;

  const ManagerHomeScreen({
    super.key,
    required this.userEmail,
    required this.userName,
    this.warehouseId,
    this.warehouseName,
  });

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  List<Map<String, dynamic>> _warehouses = [];
  bool _isLoading = true;
  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();

    // If manager has assigned warehouse, go directly to it
    if (widget.warehouseId != null && widget.warehouseId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInventory({
          'id': widget.warehouseId,
          'city': widget.warehouseName ?? widget.warehouseId,
        });
      });
    }
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _isLoading = true);

    final warehouses = await InventoryService.getWarehouses();

    setState(() {
      _warehouses = warehouses.isNotEmpty ? warehouses : _getSampleWarehouses();
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _getSampleWarehouses() {
    return [
      {
        'id': 'wh_jaipur_central',
        'city': 'Jaipur Central',
        'lat': 26.9124,
        'lon': 75.7873,
      },
      {
        'id': 'wh_jaipur_malviya',
        'city': 'Jaipur Malviya Nagar',
        'lat': 26.8505,
        'lon': 75.8043,
      },
      {
        'id': 'wh_lnmiit',
        'city': 'LNMIIT Jaipur',
        'lat': 26.9020,
        'lon': 75.8680,
      },
      {
        'id': 'wh_jaipur_amer',
        'city': 'Jaipur Amer',
        'lat': 26.9855,
        'lon': 75.8513,
      },
      {
        'id': 'wh_delhi_central',
        'city': 'Delhi Central',
        'lat': 28.6139,
        'lon': 77.2090,
      },
      {
        'id': 'wh_mumbai_central',
        'city': 'Mumbai Central',
        'lat': 19.0760,
        'lon': 72.8777,
      },
      {
        'id': 'wh_bangalore_central',
        'city': 'Bangalore Central',
        'lat': 12.9716,
        'lon': 77.5946,
      },
      {
        'id': 'wh_chennai_central',
        'city': 'Chennai Central',
        'lat': 13.0827,
        'lon': 80.2707,
      },
      {
        'id': 'wh_hyderabad_central',
        'city': 'Hyderabad Central',
        'lat': 17.3850,
        'lon': 78.4867,
      },
    ];
  }

  void _openInventory(Map<String, dynamic> warehouse) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => InventoryScreen(
              warehouseId: warehouse['id'],
              warehouseName: warehouse['city'],
              userEmail: widget.userEmail,
            ),
      ),
    );
  }

  Future<void> _subscribeToNotifications() async {
    if (_selectedWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a warehouse first')),
      );
      return;
    }

    final result = await InventoryService.subscribeToNotifications(
      warehouseId: _selectedWarehouseId!,
      email: widget.userEmail,
    );

    if (result.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Subscribed to order notifications!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Warehouse Manager',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.userName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: _subscribeToNotifications,
            tooltip: 'Subscribe to Notifications',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Switch Role',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadWarehouses,
                child: CustomScrollView(
                  slivers: [
                    _buildHeader(),
                    _buildStats(),
                    _buildWarehouseList(),
                  ],
                ),
              ),
    );
  }

  Widget _buildHeader() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back! 👋',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage inventory and track orders across ${_warehouses.length} warehouses',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.warehouse,
                value: '${_warehouses.length}',
                label: 'Warehouses',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.inventory,
                value: '150+',
                label: 'Products',
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.local_shipping,
                value: '24',
                label: 'Orders Today',
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseList() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Select Warehouse',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            );
          }

          final warehouse = _warehouses[index - 1];
          return _WarehouseCard(
            warehouse: warehouse,
            isSelected: _selectedWarehouseId == warehouse['id'],
            onTap: () {
              setState(() => _selectedWarehouseId = warehouse['id']);
              _openInventory(warehouse);
            },
          );
        }, childCount: _warehouses.length + 1),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  final Map<String, dynamic> warehouse;
  final bool isSelected;
  final VoidCallback onTap;

  const _WarehouseCard({
    required this.warehouse,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warehouse,
                color: Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warehouse['city'] ?? warehouse['id'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    warehouse['id'],
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
