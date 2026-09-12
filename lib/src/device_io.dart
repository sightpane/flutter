import 'dart:io';

/// Native platforms: collect structured OS, kernel, platform category, and hardware info.
Map<String, Object?> osInfo() {
  final category = _platformCategory();
  final osDetails = _detectOS();
  final arch = _detectArch();
  final cores = Platform.numberOfProcessors;

  final map = <String, Object?>{
    'platform_category': category,
    'app_type': category,
    'os': osDetails.name,
    'os_version': osDetails.version,
    'locale_name': Platform.localeName,
    'arch': arch,
    'cpu_cores': cores,
  };

  if (category == 'desktop' && Platform.isLinux) {
    map['kernel'] = _readKernelType();
    map['kernel_version'] = _readKernelVersion();
  }

  return map;
}

String _platformCategory() {
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    return 'desktop';
  }
  if (Platform.isAndroid || Platform.isIOS || Platform.isFuchsia) {
    return 'mobile';
  }
  return 'desktop';
}

class _OsDetails {
  const _OsDetails(this.name, this.version);
  final String name;
  final String version;
}

_OsDetails _detectOS() {
  if (Platform.isLinux) {
    final osRelease = _parseOsRelease();
    final name = osRelease['NAME'] ?? 'Linux';
    final version = osRelease['VERSION_ID'] ?? osRelease['VERSION'] ?? '';
    return _OsDetails(name, version);
  }
  if (Platform.isMacOS) {
    final match = RegExp(r'Version\s+([0-9.]+)').firstMatch(Platform.operatingSystemVersion);
    final version = match != null ? match.group(1)! : Platform.operatingSystemVersion;
    return _OsDetails('macOS', version);
  }
  if (Platform.isWindows) {
    final match = RegExp(r'(?:Build\s+)?([0-9.]+)').firstMatch(Platform.operatingSystemVersion);
    final version = match != null ? match.group(1)! : Platform.operatingSystemVersion;
    return _OsDetails('Windows', version);
  }
  if (Platform.isAndroid) {
    return _OsDetails('Android', Platform.operatingSystemVersion);
  }
  if (Platform.isIOS) {
    return _OsDetails('iOS', Platform.operatingSystemVersion);
  }
  return _OsDetails(Platform.operatingSystem, Platform.operatingSystemVersion);
}

Map<String, String> _parseOsRelease() {
  try {
    final file = File('/etc/os-release');
    if (!file.existsSync()) return const {};
    final lines = file.readAsLinesSync();
    final map = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final key = trimmed.substring(0, eq).trim();
        var val = trimmed.substring(eq + 1).trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          val = val.substring(1, val.length - 1);
        }
        map[key] = val;
      }
    }
    return map;
  } catch (_) {
    return const {};
  }
}

String _readKernelType() {
  try {
    final f = File('/proc/sys/kernel/ostype');
    if (f.existsSync()) {
      final s = f.readAsStringSync().trim();
      if (s.isNotEmpty) return s;
    }
  } catch (_) {}
  return 'Linux';
}

String _readKernelVersion() {
  try {
    final f = File('/proc/sys/kernel/osrelease');
    if (f.existsSync()) {
      final s = f.readAsStringSync().trim();
      if (s.isNotEmpty) return s;
    }
  } catch (_) {}
  final match = RegExp(r'Linux\s+([^\s]+)').firstMatch(Platform.operatingSystemVersion);
  if (match != null) return match.group(1)!;
  return Platform.operatingSystemVersion;
}

String _detectArch() {
  final v = Platform.version.toLowerCase();
  if (v.contains('x64') || v.contains('x86_64')) return 'x86_64';
  if (v.contains('arm64') || v.contains('aarch64')) return 'arm64';
  if (v.contains('arm')) return 'arm';
  if (v.contains('x86') || v.contains('ia32')) return 'x86';
  return Platform.environment['HOSTTYPE'] ?? 'unknown';
}
