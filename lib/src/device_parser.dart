class BrowserDetails {
  const BrowserDetails(this.name, this.version);
  final String name;
  final String version;
}

class WebOsDetails {
  const WebOsDetails(this.name, this.version);
  final String name;
  final String version;
}

BrowserDetails parseBrowser(String ua) {
  final edge = RegExp(r'Edg(?:e|A|iOS)?\/([0-9.]+)').firstMatch(ua);
  if (edge != null) return BrowserDetails('Edge', edge.group(1)!);

  final opera = RegExp(r'(?:OPR|Opera)\/([0-9.]+)').firstMatch(ua);
  if (opera != null) return BrowserDetails('Opera', opera.group(1)!);

  final samsung = RegExp(r'SamsungBrowser\/([0-9.]+)').firstMatch(ua);
  if (samsung != null) return BrowserDetails('Samsung', samsung.group(1)!);

  final firefox = RegExp(r'Firefox\/([0-9.]+)').firstMatch(ua);
  if (firefox != null) return BrowserDetails('Firefox', firefox.group(1)!);

  final chrome = RegExp(r'(?:Chrome|CriOS)\/([0-9.]+)').firstMatch(ua);
  if (chrome != null) return BrowserDetails('Chrome', chrome.group(1)!);

  if (ua.contains('Safari/')) {
    final safariVer = RegExp(r'Version\/([0-9.]+)').firstMatch(ua);
    return BrowserDetails('Safari', safariVer?.group(1) ?? '');
  }

  return const BrowserDetails('Browser', '');
}

String browserName(String ua) => parseBrowser(ua).name;

WebOsDetails parseWebOS(String ua) {
  final win = RegExp(r'Windows NT ([0-9.]+)').firstMatch(ua);
  if (win != null) {
    final v = win.group(1)!;
    return WebOsDetails('Windows', v == '10.0' ? '10/11' : v);
  }

  final mac = RegExp(r'Mac OS X ([0-9_]+)').firstMatch(ua);
  if (mac != null) {
    return WebOsDetails('macOS', mac.group(1)!.replaceAll('_', '.'));
  }

  final android = RegExp(r'Android ([0-9.]+)').firstMatch(ua);
  if (android != null) {
    return WebOsDetails('Android', android.group(1)!);
  }

  final ios = RegExp(r'(?:iPhone|iPad|iPod).*OS ([0-9_]+)').firstMatch(ua);
  if (ios != null) {
    return WebOsDetails('iOS', ios.group(1)!.replaceAll('_', '.'));
  }

  if (ua.contains('Ubuntu')) return const WebOsDetails('Ubuntu', '');
  if (ua.contains('Linux') || ua.contains('X11')) return const WebOsDetails('Linux', '');
  if (ua.contains('CrOS')) return const WebOsDetails('ChromeOS', '');

  return const WebOsDetails('web', '');
}

String parseWebArch(String ua) {
  if (ua.contains('x86_64') || ua.contains('Win64') || ua.contains('WOW64') || ua.contains('x64')) {
    return 'x86_64';
  }
  if (ua.contains('arm64') || ua.contains('aarch64')) {
    return 'arm64';
  }
  return '';
}
