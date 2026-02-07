import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Authentication Service for Rapid Delivery App
/// Supports both Google Sign-In (Buyers) and Warehouse Manager credentials
class AuthService {
  // =====================================================
  // GOOGLE SIGN-IN CONFIGURATION
  // =====================================================
  //
  // To enable Google Sign-In:
  // 1. Go to: https://console.cloud.google.com/apis/credentials
  // 2. Create OAuth 2.0 Client ID
  // 3. For Web: Add http://localhost as authorized origin
  // 4. Add client ID below
  //
  // FREE TIER: Google Sign-In is completely free!
  // =====================================================

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Add your web client ID here for Flutter Web:
    // clientId: 'YOUR_CLIENT_ID.apps.googleusercontent.com',
  );

  // =====================================================
  // DEMO WAREHOUSE MANAGER CREDENTIALS
  // ⚠️ FOR LOCAL DEVELOPMENT/TESTING ONLY
  // These are NOT real credentials - intentionally hardcoded
  // for demo purposes. In production, use proper auth system.
  // =====================================================
  // gitguardian:ignore - Demo credentials for local testing
  static final Map<String, WarehouseManager> _warehouseManagers = {
    // Jaipur Warehouses
    'manager_jaipur_central': WarehouseManager(
      id: 'manager_jaipur_central',
      email: 'manager.jaipur.central@rapid.com',
      password: 'jaipur123',
      name: 'Rajesh Kumar',
      warehouseId: 'wh_jaipur_central',
      warehouseName: 'Jaipur Central',
    ),
    'manager_jaipur_malviya': WarehouseManager(
      id: 'manager_jaipur_malviya',
      email: 'manager.jaipur.malviya@rapid.com',
      password: 'malviya123',
      name: 'Priya Sharma',
      warehouseId: 'wh_jaipur_malviya',
      warehouseName: 'Jaipur Malviya Nagar',
    ),
    'manager_lnmiit': WarehouseManager(
      id: 'manager_lnmiit',
      email: 'manager.lnmiit@rapid.com',
      password: 'lnmiit123',
      name: 'Amit Verma',
      warehouseId: 'wh_lnmiit',
      warehouseName: 'LNMIIT Jaipur',
    ),
    'manager_jaipur_amer': WarehouseManager(
      id: 'manager_jaipur_amer',
      email: 'manager.jaipur.amer@rapid.com',
      password: 'amer123',
      name: 'Sunita Devi',
      warehouseId: 'wh_jaipur_amer',
      warehouseName: 'Jaipur Amer',
    ),
    // Metro City Warehouses
    'manager_delhi': WarehouseManager(
      id: 'manager_delhi',
      email: 'manager.delhi@rapid.com',
      password: 'delhi123',
      name: 'Vikram Singh',
      warehouseId: 'wh_delhi_central',
      warehouseName: 'Delhi Central',
    ),
    'manager_mumbai': WarehouseManager(
      id: 'manager_mumbai',
      email: 'manager.mumbai@rapid.com',
      password: 'mumbai123',
      name: 'Rahul Patil',
      warehouseId: 'wh_mumbai_central',
      warehouseName: 'Mumbai Central',
    ),
    'manager_bangalore': WarehouseManager(
      id: 'manager_bangalore',
      email: 'manager.bangalore@rapid.com',
      password: 'bangalore123',
      name: 'Karthik Reddy',
      warehouseId: 'wh_bangalore_central',
      warehouseName: 'Bangalore Central',
    ),
    'manager_chennai': WarehouseManager(
      id: 'manager_chennai',
      email: 'manager.chennai@rapid.com',
      password: 'chennai123',
      name: 'Lakshmi Iyer',
      warehouseId: 'wh_chennai_central',
      warehouseName: 'Chennai Central',
    ),
    'manager_hyderabad': WarehouseManager(
      id: 'manager_hyderabad',
      email: 'manager.hyderabad@rapid.com',
      password: 'hyderabad123',
      name: 'Srinivas Rao',
      warehouseId: 'wh_hyderabad_central',
      warehouseName: 'Hyderabad Central',
    ),
  };

  /// Get all warehouse managers (for display in UI)
  static List<WarehouseManager> getAllManagers() {
    return _warehouseManagers.values.toList();
  }

  // =====================================================
  // GOOGLE SIGN-IN (for Buyers)
  // =====================================================

  /// Sign in with Google
  static Future<Map<String, String>?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) return null;

      // Save session
      await saveUserSession({
        'name': account.displayName ?? 'User',
        'email': account.email,
        'photo': account.photoUrl ?? '',
        'role': 'buyer',
      });

      return {
        'name': account.displayName ?? 'User',
        'email': account.email,
        'photo': account.photoUrl ?? '',
      };
    } catch (e) {
      print('Google Sign In Error: $e');
      return null;
    }
  }

  // =====================================================
  // WAREHOUSE MANAGER LOGIN
  // =====================================================

  /// Login as warehouse manager with email/password
  static Future<WarehouseManager?> loginAsManager({
    required String email,
    required String password,
  }) async {
    // Find manager by email and password
    for (final manager in _warehouseManagers.values) {
      if (manager.email.toLowerCase() == email.toLowerCase() &&
          manager.password == password) {
        // Save session
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', manager.name);
        await prefs.setString('user_email', manager.email);
        await prefs.setString('user_role', 'manager');
        await prefs.setString('warehouse_id', manager.warehouseId);
        await prefs.setString('warehouse_name', manager.warehouseName);
        await prefs.setBool('is_logged_in', true);

        return manager;
      }
    }
    return null;
  }

  // =====================================================
  // DEMO MODE (No Google setup required)
  // =====================================================

  /// Sign in as demo buyer (no Google required)
  static Future<Map<String, String>> signInAsDemo() async {
    final demoUser = {
      'name': 'Demo Buyer',
      'email': 'demo.buyer@rapiddelivery.com',
      'photo': '',
      'role': 'buyer',
    };
    await saveUserSession(demoUser);
    return demoUser;
  }

  // =====================================================
  // SESSION MANAGEMENT
  // =====================================================

  /// Sign out
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Sign Out Error: $e');
    }
    await clearSession();
  }

  /// Check if user is signed in
  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_logged_in') ?? false;
  }

  /// Get user role (buyer or manager)
  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  /// Get current user from SharedPreferences
  static Future<Map<String, String>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email');
    if (email == null) return null;

    return {
      'name': prefs.getString('user_name') ?? 'User',
      'email': email,
      'photo': prefs.getString('user_photo') ?? '',
      'role': prefs.getString('user_role') ?? 'buyer',
      'warehouseId': prefs.getString('warehouse_id') ?? '',
      'warehouseName': prefs.getString('warehouse_name') ?? '',
    };
  }

  /// Save user session
  static Future<void> saveUserSession(Map<String, String> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', user['name'] ?? '');
    await prefs.setString('user_email', user['email'] ?? '');
    await prefs.setString('user_photo', user['photo'] ?? '');
    await prefs.setString('user_role', user['role'] ?? 'buyer');
    await prefs.setBool('is_logged_in', true);
  }

  /// Clear user session
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

/// Warehouse Manager data model
class WarehouseManager {
  final String id;
  final String email;
  final String password;
  final String name;
  final String warehouseId;
  final String warehouseName;

  WarehouseManager({
    required this.id,
    required this.email,
    required this.password,
    required this.name,
    required this.warehouseId,
    required this.warehouseName,
  });
}
