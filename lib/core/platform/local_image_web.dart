import 'package:flutter/painting.dart';

/// web 端本地文件路径无意义（Phase 2 视需求接 IndexedDB blob），恒 null
ImageProvider? localFileImage(String path) => null;
