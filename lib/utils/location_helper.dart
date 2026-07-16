import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'app_constants.dart';

enum LocationStatus { loading, granted, denied, serviceDisabled, error, mockDetected }

class LocationResult {
  final double latitude;
  final double longitude;
  final String address;
  final double distanceFromOffice;
  final bool isMocked;

  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.distanceFromOffice,
    this.isMocked = false,
  });

  bool get isWithinOfficeRange => distanceFromOffice <= AppConstants.officeRadiusMeters;
}

class LocationHelper {
  static Future<(LocationStatus, LocationResult?)> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return (LocationStatus.serviceDisabled, null);

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return (LocationStatus.denied, null);
      }
      if (permission == LocationPermission.deniedForever) return (LocationStatus.denied, null);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      // isMocked is populated by the OS on Android when a fake-GPS app
      // (or Developer Options "mock location app") supplied this fix
      // instead of the real hardware sensor.
      if (position.isMocked) {
        return (LocationStatus.mockDetected, null);
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        AppConstants.officeLat,
        AppConstants.officeLng,
      );

      String address = "Unknown location";
      try {
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [p.street, p.subLocality, p.locality]
              .where((s) => s != null && s.isNotEmpty)
              .join(", ");
          if (address.isEmpty) address = "Unknown location";
        }
      } catch (_) {}

      return (
        LocationStatus.granted,
        LocationResult(
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
          distanceFromOffice: distance,
          isMocked: false,
        ),
      );
    } catch (_) {
      return (LocationStatus.error, null);
    }
  }
}