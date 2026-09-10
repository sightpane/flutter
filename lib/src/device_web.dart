import 'package:web/web.dart' as web;

import 'device_parser.dart';

export 'device_parser.dart';

/// Web: browser name, browser version, operating system, and hardware info.
Map<String, Object?> osInfo() {
  final ua = web.window.navigator.userAgent;
  final b = parseBrowser(ua);
  final o = parseWebOS(ua);
  return {
    'platform_category': 'web',
    'os': o.name,
    'os_version': o.version,
    'user_agent': ua,
    'browser': b.name,
    'browser_version': b.version,
    'arch': parseWebArch(ua),
    'cpu_cores': web.window.navigator.hardwareConcurrency,
  };
}
