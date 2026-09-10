import 'dart:io';

import 'package:flutter/painting.dart';

/// 本地文件路径 → ImageProvider（io 端：FileImage）
ImageProvider? localFileImage(String path) => FileImage(File(path));
