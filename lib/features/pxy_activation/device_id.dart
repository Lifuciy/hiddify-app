import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceId {
  static const _key = 'pxy_device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = const Uuid().v4();
    await _storage.write(key: _key, value: id);
    return id;
  }
}
