import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The phone's maker and model, which `dart:io` does not expose. Read straight
/// from the OS through FFI rather than a plugin, so the SDK stays pure Dart.
/// Anything that cannot be read is left out; the rest of the device map does
/// not depend on it.
Map<String, Object?> deviceModel() {
  try {
    if (Platform.isAndroid) return androidModel(_systemProperty);
    if (Platform.isIOS) {
      return iosModel(
        _sysctlString('hw.machine'),
        Platform.environment['SIMULATOR_MODEL_IDENTIFIER'],
      );
    }
  } catch (_) {
    // A symbol missing from this libc: report the device without a model.
  }
  return const {};
}

/// Android's `Build.MANUFACTURER`, `Build.BRAND` and `Build.MODEL` come from
/// these properties. `ro.product.marketname` is the name on the box on the
/// devices whose maker sets it (Xiaomi, OnePlus, Oppo…); the others only have
/// the model code, such as `SM-S918B`.
@visibleForTesting
Map<String, Object?> androidModel(String Function(String name) prop) {
  final manufacturer = prop('ro.product.manufacturer');
  final brand = prop('ro.product.brand');
  final model = prop('ro.product.model');
  final name = prop('ro.product.marketname');
  return {
    if (manufacturer.isNotEmpty) 'manufacturer': manufacturer,
    if (brand.isNotEmpty) 'brand': brand,
    if (model.isNotEmpty) 'model': model,
    if (name.isNotEmpty) 'model_name': name,
  };
}

/// An iPhone reports an identifier such as `iPhone17,3`; the backend turns it
/// into "iPhone 16", so a new lineup does not need an SDK release. In the
/// simulator `hw.machine` is the Mac's architecture and the simulated device is
/// in the environment instead.
@visibleForTesting
Map<String, Object?> iosModel(String machine, String? simulatorModel) {
  final model = simulatorModel != null && simulatorModel.isNotEmpty
      ? simulatorModel
      : machine;
  return {
    'manufacturer': 'Apple',
    'brand': 'Apple',
    if (model.isNotEmpty) 'model': model,
  };
}

typedef _PropGetC = Int32 Function(Pointer<Uint8> name, Pointer<Uint8> value);
typedef _PropGet = int Function(Pointer<Uint8> name, Pointer<Uint8> value);

String _systemProperty(String name) {
  final libc = DynamicLibrary.open('libc.so');
  final get = libc.lookupFunction<_PropGetC, _PropGet>('__system_property_get');
  final key = utf8.encode(name);
  const valueSize = 92; // PROP_VALUE_MAX
  return _withMemory(libc, key.length + 1 + valueSize, (mem) {
    mem.asTypedList(key.length).setAll(0, key);
    final value = mem + (key.length + 1);
    final n = get(mem, value);
    return n > 0 ? _decode(value.asTypedList(valueSize), n) : '';
  });
}

typedef _SysctlC = Int32 Function(
  Pointer<Uint8> name,
  Pointer<Uint8> oldp,
  Pointer<Uint64> oldlenp,
  Pointer<Void> newp,
  Size newlen,
);
typedef _Sysctl = int Function(
  Pointer<Uint8> name,
  Pointer<Uint8> oldp,
  Pointer<Uint64> oldlenp,
  Pointer<Void> newp,
  int newlen,
);

String _sysctlString(String name) {
  final libc = DynamicLibrary.process();
  final sysctl = libc.lookupFunction<_SysctlC, _Sysctl>('sysctlbyname');
  final key = utf8.encode(name);
  const valueSize = 64;
  // The length first, where malloc's alignment suits a 64-bit integer.
  return _withMemory(libc, 8 + valueSize + key.length + 1, (mem) {
    final len = mem.cast<Uint64>()..value = valueSize;
    final value = mem + 8;
    final keyPtr = mem + (8 + valueSize);
    keyPtr.asTypedList(key.length).setAll(0, key);
    if (sysctl(keyPtr, value, len, nullptr, 0) != 0) return '';
    return _decode(value.asTypedList(valueSize), len.value);
  });
}

typedef _MallocC = Pointer<Uint8> Function(Size size);
typedef _Malloc = Pointer<Uint8> Function(int size);
typedef _FreeC = Void Function(Pointer<Uint8> ptr);
typedef _Free = void Function(Pointer<Uint8> ptr);

/// Runs [f] with [size] zeroed bytes of native memory from [libc]'s own
/// allocator; package:ffi's would be a new dependency for two short strings.
T _withMemory<T>(DynamicLibrary libc, int size, T Function(Pointer<Uint8>) f) {
  final mem = libc.lookupFunction<_MallocC, _Malloc>('malloc')(size);
  if (mem == nullptr) throw StateError('malloc($size) failed');
  try {
    mem.asTypedList(size).fillRange(0, size, 0);
    return f(mem);
  } finally {
    libc.lookupFunction<_FreeC, _Free>('free')(mem);
  }
}

/// The text up to the first NUL, within the [n] bytes the call reported.
String _decode(Uint8List buf, int n) {
  var end = buf.indexOf(0);
  if (end < 0 || end > n) end = n.clamp(0, buf.length);
  return utf8.decode(buf.sublist(0, end), allowMalformed: true).trim();
}
