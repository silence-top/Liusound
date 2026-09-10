import 'app_platform.dart';
import 'media_store.dart';
import 'media_store_android.dart';
import 'media_store_ios.dart';
import 'media_store_macos.dart';
import 'media_store_stub.dart';
import 'media_store_windows.dart';

MediaStore createMediaStore() {
  if (AppPlatform.isAndroid) return MediaStoreAndroid();
  if (AppPlatform.isIOS) return MediaStoreIos();
  if (AppPlatform.isWindows) return MediaStoreWindows();
  if (AppPlatform.isMacOS) return MediaStoreMacos();
  return MediaStoreStub();
}
