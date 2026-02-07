import 'package:flutter/material.dart';
import '../models.dart';

/// Top delivery address bar with location and ETA (like Blinkit header)
class DeliveryAddressBar extends StatelessWidget {
  final UserLocation? currentLocation;
  final String deliveryInfo;
  final VoidCallback onChangeLocation;

  const DeliveryAddressBar({
    super.key,
    required this.currentLocation,
    required this.deliveryInfo,
    required this.onChangeLocation,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChangeLocation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Location icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0C831F).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.location_on,
                color: Color(0xFF0C831F),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Address and ETA
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        currentLocation?.name ?? 'Set delivery location',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                  if (currentLocation != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      currentLocation!.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Delivery time badge
            if (deliveryInfo.isNotEmpty && !deliveryInfo.contains('🚫'))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.timer, size: 14, color: Color(0xFF0C831F)),
                    SizedBox(width: 4),
                    Text(
                      '10 min',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0C831F),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
