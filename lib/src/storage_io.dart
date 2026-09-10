import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'storage.dart';

SightpaneStorage createDefaultStorage({String? path, String? apiKey}) =>
    FileSightpaneStorage(path: path, apiKey: apiKey);

/// File-based persistent storage for native platforms.
class FileSightpaneStorage implements SightpaneStorage {
  FileSightpaneStorage({String? path, String? apiKey})
      : _file = File(
          path ??
              '${Directory.systemTemp.path}/sightpane_offline_${_sanitize(apiKey)}.json',
        );

  FileSightpaneStorage.path(String path) : _file = File(path);

  final File _file;

  static String _sanitize(String? key) {
    if (key == null || key.isEmpty) return 'default';
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  @override
  Future<void> write(List<SightpaneItem> items) async {
    try {
      if (items.isEmpty) {
        if (_file.existsSync()) {
          _file.deleteSync();
        }
        return;
      }
      final jsonList = items.map((i) => i.toJson()).toList();
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(jsonList), flush: true);
    } catch (_) {
      // Ignore disk/filesystem failures gracefully
    }
  }

  @override
  Future<List<SightpaneItem>> read() async {
    try {
      if (!_file.existsSync()) return [];
      final content = _file.readAsStringSync();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content);
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
      if (_file.existsSync()) {
        _file.deleteSync();
      }
    } catch (_) {}
  }
}
