import 'package:flutter/widgets.dart';

import '../client.dart';
import '../models.dart';

/// Records route transitions as `navigation` breadcrumbs; it can just as well
/// be added to go_router's `observers` list.
class SightpaneNavigatorObserver extends NavigatorObserver {
  SightpaneNavigatorObserver({this.routeNameOf});

  /// Customizes the route name; defaults to `settings.name`.
  final String? Function(Route<dynamic> route)? routeNameOf;

  String _name(Route<dynamic>? r) {
    if (r == null) return '';
    final custom = routeNameOf?.call(r);
    if (custom != null) return custom;
    return r.settings.name ?? r.runtimeType.toString();
  }

  void _record(String action, Route<dynamic>? to, Route<dynamic>? from) {
    final c = Sightpane.maybeClient;
    if (c == null) return;
    final toName = _name(to);
    if (toName.isNotEmpty) c.currentRoute = toName;
    c.addBreadcrumb(
      SightpaneBreadcrumb(
        category: 'navigation',
        message: '$action $toName',
        data: {'from': _name(from), 'to': toName},
      ),
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('push', route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('pop', previousRoute, route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record('replace', newRoute, oldRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record('remove', previousRoute, route);
}
