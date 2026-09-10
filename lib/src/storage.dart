export 'storage_web.dart' if (dart.library.io) 'storage_io.dart';

import 'models.dart';
import 'storage_web.dart' if (dart.library.io) 'storage_io.dart' as impl;

/// Storage interface for the offline queue.
abstract class SightpaneStorage {
  Future<void> write(List<SightpaneItem> items);
  Future<List<SightpaneItem>> read();
  Future<void> clear();

  /// Creates a platform-appropriate storage (file on native platforms, localStorage on web).
  static SightpaneStorage createDefault({String? path, String? apiKey}) =>
      impl.createDefaultStorage(path: path, apiKey: apiKey);
}

/// In-memory storage for testing and transient environments.
class InMemorySightpaneStorage implements SightpaneStorage {
  final List<SightpaneItem> _items = [];

  @override
  Future<void> write(List<SightpaneItem> items) async {
    _items
      ..clear()
      ..addAll(items);
  }

  @override
  Future<List<SightpaneItem>> read() async => List<SightpaneItem>.from(_items);

  /// Synchronous read for test assertions.
  List<SightpaneItem> readSync() => List<SightpaneItem>.from(_items);

  @override
  Future<void> clear() async => _items.clear();
}
