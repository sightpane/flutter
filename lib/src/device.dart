import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'device_web.dart' if (dart.library.io) 'device_io.dart' as impl;

/// The envelope's `device` field: platform, operating system, screen and app.
class SightpaneDevice {
  static Map<String, Object?> collect({
    String release = '',
    String environment = '',
    String appName = '',
  }) {
    final views = ui.PlatformDispatcher.instance.views;
    final view = views.isEmpty ? null : views.first;
    return {
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      ...impl.osInfo(),
      'locale': ui.PlatformDispatcher.instance.locale.toLanguageTag(),
      if (view != null)
        'screen': {
          'w': (view.physicalSize.width / view.devicePixelRatio).round(),
          'h': (view.physicalSize.height / view.devicePixelRatio).round(),
          'dpr': view.devicePixelRatio,
        },
      'debug': kDebugMode,
      if (release.isNotEmpty) 'release': release,
      if (environment.isNotEmpty) 'environment': environment,
      if (appName.isNotEmpty) 'app': appName,
    };
  }
}
