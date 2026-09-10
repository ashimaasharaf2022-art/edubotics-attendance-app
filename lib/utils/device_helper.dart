import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  /// Returns a stable identifier for this physical device. On Android
  /// this uses the ANDROID_ID, which stays the same across app
  /// reinstalls (but changes on factory reset). On web, there is no
  /// OS-level device ID, so we fall back to a browser fingerprint
  /// built from vendor + user agent. Note this is weaker than a real
  /// device ID: it can change if the user clears site data, switches
  /// browsers, or uses a different machine.
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return "${webInfo.vendor ?? 'unknown'}-${webInfo.userAgent ?? 'unknown'}";
    }

    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id;
  }

  static Future<String> getDeviceModel() async {
    final deviceInfo = DeviceInfoPlugin();

    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return "${webInfo.browserName}";
    }

    final androidInfo = await deviceInfo.androidInfo;
    return "${androidInfo.manufacturer} ${androidInfo.model}";
  }
}