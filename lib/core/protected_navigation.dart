import 'package:flutter/material.dart';

/// Owns the root Navigator so authentication loss can remove protected routes
/// immediately instead of leaving them above the rebuilt login root.
class ProtectedNavigation {
  ProtectedNavigation._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final observer = _ProtectedRouteObserver();

  static void removeRoutesAboveRoot() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    observer.removeRoutesAboveRoot(navigator);
  }
}

class _ProtectedRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _routes[index] = newRoute;
    } else {
      if (oldRoute != null) _routes.remove(oldRoute);
      if (newRoute != null) _routes.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void removeRoutesAboveRoot(NavigatorState navigator) {
    for (final route in _routes.skip(1).toList().reversed) {
      navigator.removeRoute(route);
    }
  }
}
