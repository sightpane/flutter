import 'dart:collection';

import 'models.dart';

/// Fixed-size ring buffer; once it is full the oldest breadcrumb drops out.
class BreadcrumbBuffer {
  BreadcrumbBuffer(this.capacity);
  final int capacity;
  final _items = ListQueue<SightpaneBreadcrumb>();

  void add(SightpaneBreadcrumb b) {
    _items.addLast(b);
    while (_items.length > capacity) {
      _items.removeFirst();
    }
  }

  List<SightpaneBreadcrumb> snapshot() => List.unmodifiable(_items);
  int get length => _items.length;
  void clear() => _items.clear();
}
