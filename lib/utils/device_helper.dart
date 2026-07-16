import 'package:device_info_plus/device_info_plus.dart';

class DeviceHelper {
  /// Returns a stable identifier for this physical device. On Android
  /// this uses the ANDROID_ID, which stays the same across app
  /// reinstalls (but changes on factory reset).
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return androidInfo.id;
  }

  static Future<String> getDeviceModel() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    return "${androidInfo.manufacturer} ${androidInfo.model}";
  }
}