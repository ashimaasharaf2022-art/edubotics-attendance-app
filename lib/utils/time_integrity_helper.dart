import 'package:ntp/ntp.dart';

/// Compares the device's local clock against real network time (NTP).
/// If someone manually sets their phone's clock backward/forward to
/// game the attendance calculator, the drift between device time and
/// true network time will exceed the tolerance and the check fails.
class TimeIntegrityHelper {
  static Future<bool> isDeviceTimeValid({Duration tolerance = const Duration(minutes: 5)}) async {
    try {
      final networkTime = await NTP.now(lookUpAddress: 'time.google.com');
      final deviceTime = DateTime.now();
      final drift = deviceTime.difference(networkTime).abs();
      return drift <= tolerance;
    } catch (_) {
      // If NTP is unreachable (poor network), fail open rather than
      // blocking a legitimate employee who just has no signal.
      return true;
    }
  }
}