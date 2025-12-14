class Product {
  final String id;
  final String name;
  final String unit;
  final String imageEmoji;
  final double price;

  Product({
    required this.id, 
    required this.name, 
    required this.unit,
    required this.imageEmoji, 
    required this.price
  });
}

class UserLocation {
  final String name;     // e.g. "Home", "Office"
  final String address;  // e.g. "LNMIIT Campus"
  final double lat;
  final double lon;

  UserLocation({
    required this.name, 
    required this.address, 
    required this.lat, 
    required this.lon
  });
}