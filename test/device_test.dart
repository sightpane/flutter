import 'package:flutter_test/flutter_test.dart';
import 'package:sightpane/src/device.dart';
import 'package:sightpane/src/device_parser.dart';

void main() {
  test('SightpaneDevice.collect gathers platform, os, and hardware details', () {
    final dev = SightpaneDevice.collect(
      release: '1.2.3',
      environment: 'prod',
      appName: 'test_app',
    );

    expect(dev['platform'], isNotEmpty);
    expect(dev['platform_category'], anyOf('desktop', 'mobile', 'web'));
    expect(dev['app_type'], anyOf('desktop', 'mobile', 'web'));
    expect(dev.containsKey('browser'), isFalse);
    expect(dev['os'], isNotEmpty);
    expect(dev['arch'], isNotEmpty);
    expect(dev['cpu_cores'], isA<int>());
    expect(dev['release'], '1.2.3');
    expect(dev['environment'], 'prod');
    expect(dev['app'], 'test_app');

    if (dev['platform_category'] == 'desktop' && dev['os'] == 'Ubuntu') {
      expect(dev['kernel'], 'Linux');
      expect(dev['kernel_version'], isNotEmpty);
    }
  });

  test('parseBrowser extracts Chrome, Firefox, Safari, Edge, Opera and versions', () {
    final chromeUA =
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.6613.120 Safari/537.36';
    final chrome = parseBrowser(chromeUA);
    expect(chrome.name, 'Chrome');
    expect(chrome.version, '128.0.6613.120');

    final ffUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0';
    final ff = parseBrowser(ffUA);
    expect(ff.name, 'Firefox');
    expect(ff.version, '129.0');

    final edgeUA =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 Edg/127.0.2651.105';
    final edge = parseBrowser(edgeUA);
    expect(edge.name, 'Edge');
    expect(edge.version, '127.0.2651.105');

    final safariUA =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15';
    final safari = parseBrowser(safariUA);
    expect(safari.name, 'Safari');
    expect(safari.version, '17.5');
  });

  test('parseWebOS extracts Windows, macOS, Android, iOS, Linux and versions', () {
    final winUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/128.0.0.0';
    final win = parseWebOS(winUA);
    expect(win.name, 'Windows');
    expect(win.version, '10/11');

    final macUA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15';
    final mac = parseWebOS(macUA);
    expect(mac.name, 'macOS');
    expect(mac.version, '10.15.7');

    final androidUA = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) Mobile Chrome/128.0.0.0';
    final android = parseWebOS(androidUA);
    expect(android.name, 'Android');
    expect(android.version, '14');

    final iosUA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) Mobile/15E148';
    final ios = parseWebOS(iosUA);
    expect(ios.name, 'iOS');
    expect(ios.version, '17.5');
  });

  test('parseWebArch detects x86_64 and arm64', () {
    expect(parseWebArch('Mozilla/5.0 (X11; Linux x86_64)'), 'x86_64');
    expect(parseWebArch('Mozilla/5.0 (Macintosh; Apple Silicon arm64)'), 'arm64');
  });
}
