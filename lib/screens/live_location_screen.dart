import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import '../utils/location_helper.dart';

class LiveLocationScreen extends StatefulWidget {
  const LiveLocationScreen({super.key});

  @override
  State<LiveLocationScreen> createState() => _LiveLocationScreenState();
}

class _LiveLocationScreenState extends State<LiveLocationScreen> {
  LocationStatus status = LocationStatus.loading;
  LocationResult? result;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => status = LocationStatus.loading);
    final (s, r) = await LocationHelper.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      status = s;
      result = r;
    });
    if (r != null) {
      _mapController.move(LatLng(r.latitude, r.longitude), 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFix = status == LocationStatus.granted && result != null;
    final centerLat = result?.latitude ?? AppConstants.officeLat;
    final centerLng = result?.longitude ?? AppConstants.officeLng;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text("Live Location", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: AppColors.textPrimary)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: LatLng(centerLat, centerLng), initialZoom: 16),
                  children: [
                    TileLayer(
                      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.punchin_app",
                    ),
                    CircleLayer(circles: [
                      CircleMarker(
                        point: const LatLng(AppConstants.officeLat, AppConstants.officeLng),
                        radius: AppConstants.officeRadiusMeters,
                        useRadiusInMeter: true,
                        color: AppColors.primary.withOpacity(0.15),
                        borderColor: AppColors.primary,
                        borderStrokeWidth: 1.5,
                      ),
                    ]),
                    MarkerLayer(markers: [
                      const Marker(
                        point: LatLng(AppConstants.officeLat, AppConstants.officeLng),
                        width: 34,
                        height: 34,
                        child: Icon(Icons.business, color: AppColors.primary, size: 30),
                      ),
                      if (hasFix)
                        Marker(
                          point: LatLng(result!.latitude, result!.longitude),
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.person_pin_circle,
                            color: result!.isWithinOfficeRange ? AppColors.success : AppColors.danger,
                            size: 34,
                          ),
                        ),
                    ]),
                  ],
                ),
                if (status == LocationStatus.loading)
                  const Positioned.fill(child: Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.surface, boxShadow: AppShadows.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusBanner(),
                if (hasFix) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(result!.address, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    switch (status) {
      case LocationStatus.loading:
        return const _Banner(icon: Icons.my_location, color: AppColors.info, text: "Getting your current location...");
      case LocationStatus.serviceDisabled:
        return _Banner(icon: Icons.location_off, color: AppColors.danger, text: "Turn on location services.", onRetry: _load);
      case LocationStatus.denied:
        return _Banner(icon: Icons.location_off, color: AppColors.danger, text: "Location permission denied.", onRetry: _load);
      case LocationStatus.mockDetected:
        return _Banner(icon: Icons.warning_amber_rounded, color: AppColors.danger, text: "Mock location detected.", onRetry: _load);
      case LocationStatus.error:
        return _Banner(icon: Icons.error_outline, color: AppColors.danger, text: "Couldn't get your location.", onRetry: _load);
      case LocationStatus.granted:
        final inRange = result?.isWithinOfficeRange ?? false;
        final distance = result?.distanceFromOffice.round() ?? 0;
        return _Banner(
          icon: inRange ? Icons.check_circle : Icons.location_on,
          color: inRange ? AppColors.success : AppColors.warning,
          text: inRange ? "You're at the office" : "${distance}m from office",
        );
    }
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onRetry;

  const _Banner({required this.icon, required this.color, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text("Retry")),
      ],
    );
  }
}
