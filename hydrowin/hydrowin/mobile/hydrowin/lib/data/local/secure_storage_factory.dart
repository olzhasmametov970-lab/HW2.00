import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Единые опции защищённого хранилища (Keystore / Keychain).
FlutterSecureStorage createSecureStorage() {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    webOptions: WebOptions(
      dbName: 'hydrowin_secure',
      publicKey: 'hydrowin_web_storage_v1',
    ),
  );
}
