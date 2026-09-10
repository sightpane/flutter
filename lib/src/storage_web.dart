import 'dart:convert';
import 'package:web/web.dart' as web;

import 'models.dart';
import 'storage.dart';

SightpaneStorage createDefaultStorage({String? path, String? apiKey}) =>
    WebSightpaneStorage(key: path ?? 'sightpane_offline_${_sanitize(apiKey)}');

String _sanitize(String? key) {
  if (key == null || key.isEmpty) return 'default';
  return key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

/// Web storage using localStorage.
class WebSightpaneStorage implements SightpaneStorage {
  WebSightpaneStorage({required this.key});

  final String key;

  @override
  Future<void> write(List<SightpaneItem> items) async {
    try {
      if (items.isEmpty) {
        web.window.localStorage.removeItem(key);
        return;
      }
      final jsonList = items.map((i) => i.toJson()).toList();
      web.window.localStorage.setItem(key, jsonEncode(jsonList));
    } catch (_) {}
  }

  @override
  Future<List<SightpaneItem>> read() async {
    try {
      final raw = web.window.localStorage.getItem(key);
      if (raw == null || raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => SightpaneItem.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> clear() async {
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {}
  }
}

/// Web stub for FileSightpaneStorage.
class FileSightpaneStorage implements SightpaneStorage {
  FileSightpaneStorage({String? path, String? apiKey}) {
    throw UnsupportedError(
      'FileSightpaneStorage is not supported on web. Use WebSightpaneStorage or SightpaneStorage.createDefault().',
    );
  }

  FileSightpaneStorage.path(String path) {
    throw UnsupportedError(
      'FileSightpaneStorage is not supported on web. Use WebSightpaneStorage or SightpaneStorage.createDefault().',
    );
  }

  @override
  Future<void> write(List<SightpaneItem> items) async {}

  @override
  Future<List<SightpaneItem>> read() async => [];

  @override
  Future<void> clear() async {}
}
