import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';

class CoverCacheManager extends CacheManager {
  static const _key = 'coverArtCache';
  static CoverCacheManager? _instance;

  factory CoverCacheManager() => _instance ??= CoverCacheManager._();

  CoverCacheManager._()
    : super(
        Config(
          _key,
          stalePeriod: const Duration(days: 365),
          maxNrOfCacheObjects: 4000,
          fileService: CoverHttpFileService(),
        ),
      );
}

class CoverHttpFileService extends HttpFileService {
  CoverHttpFileService()
    : super(
        httpClient: kIsWeb
            ? null
            : IOClient(
                HttpClient()
                  ..connectionTimeout = const Duration(seconds: 15)
                  ..maxConnectionsPerHost = 8,
              ),
      ) {
    concurrentFetches = 8;
  }
}
