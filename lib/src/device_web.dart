import 'package:web/web.dart' as web;

/// Web: browser name and user agent (used to tell visitors apart).
Map<String, Object?> osInfo() {
  final ua = web.window.navigator.userAgent;
  return {'os': 'web', 'user_agent': ua, 'browser': browserName(ua)};
}

/// A rough browser name read off the user agent.
String browserName(String ua) {
  if (ua.contains('Edg/')) return 'Edge';
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('SamsungBrowser')) return 'Samsung';
  if (ua.contains('Firefox/')) return 'Firefox';
  if (ua.contains('Chrome/') || ua.contains('CriOS/')) return 'Chrome';
  if (ua.contains('Safari/')) return 'Safari';
  return 'Browser';
}
