import 'dart:io';

/// Native platforms: there is no browser, so the operating system name is what
/// tells visitors apart.
Map<String, Object?> osInfo() => {
  'os': Platform.operatingSystem,
  'os_version': Platform.operatingSystemVersion,
  'locale_name': Platform.localeName,
  'browser': '${Platform.operatingSystem} app',
};
