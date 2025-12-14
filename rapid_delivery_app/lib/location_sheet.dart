import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'models.dart';
import 'api_service.dart';

class LocationSearchSheet extends StatefulWidget {
  final Function(UserLocation) onLocationSelected;

  const LocationSearchSheet({super.key, required this.onLocationSelected});

  @override
  State<LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<LocationSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _suggestions = [];
  bool _isSearching = false;

  void _runSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    
    List<dynamic> results = await ApiService.searchLocations(query);
    
    if (mounted) {
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _useGPS() async {
    Navigator.pop(context); // Close sheet first
    // This logic returns to parent to handle the loading state there, 
    // or we can handle permissions here. Let's do a simple pass back.
    
    // Check perms
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    
    // Attempt reverse geocode for display name
    String displayName = "Current Location";
    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        displayName = "${placemarks.first.name}, ${placemarks.first.locality}";
      }
    } catch (e) {
      // ignore
    }

    widget.onLocationSelected(UserLocation(
      name: "My Location",
      address: displayName,
      lat: position.latitude,
      lon: position.longitude
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text("Select Delivery Location", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 15),
          
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Search 'LNMIIT' or 'Raja Park'...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _runSearch(_controller.text),
              ),
            ),
            onSubmitted: _runSearch,
          ),
          const SizedBox(height: 10),

          ListTile(
            leading: const Icon(Icons.my_location, color: Color(0xFF0C831F)),
            title: const Text("Use Current Location", style: TextStyle(color: Color(0xFF0C831F), fontWeight: FontWeight.bold)),
            onTap: _useGPS,
          ),
          const Divider(),

          Expanded(
            child: _isSearching 
              ? const Center(child: CircularProgressIndicator()) 
              : ListView.separated(
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final place = _suggestions[i];
                    final name = place['display_name'].split(',')[0];
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(place['display_name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        widget.onLocationSelected(UserLocation(
                          name: name,
                          address: place['display_name'],
                          lat: double.parse(place['lat']),
                          lon: double.parse(place['lon'])
                        ));
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}