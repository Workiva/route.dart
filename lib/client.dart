// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library route.client;

import 'dart:async';
import 'dart:html';
import 'dart:math';

import 'package:logging/logging.dart';

import 'src/utils.dart';

import 'history_provider.dart';
export 'history_provider.dart';
import 'link_matcher.dart';
import 'url_matcher.dart';
export 'url_matcher.dart';
import 'url_template.dart';

part 'route_handle.dart';
part 'route_view.dart';
part 'routable.dart';

final _logger = new Logger('route');
const _PATH_SEPARATOR = '.';

typedef void RoutePreEnterEventHandler(RoutePreEnterEvent event);
typedef void RouteEnterEventHandler(RouteEnterEvent event);
typedef void RoutePreLeaveEventHandler(RoutePreLeaveEvent event);
typedef void RouteLeaveEventHandler(RouteLeaveEvent event);

typedef String PageTitleHandler(Route route);

/**
 * WindowClickHandler can be used as a hook into [Router] to
 * modify behavior right after user clicks on an element, and
 * before the URL in the browser changes.
 */
typedef void WindowClickHandler(Event e);

/**
 * [Route] represents a node in the route tree.
 */
abstract class Route {
  /**
   * Name of the route. Used when querying routes.
   */
  String get name;

  /**
   * A path fragment [UrlMatcher] for this route.
   */
  UrlMatcher get path;

  /**
   * Parent route in the route tree.
   */
  Route get parent;

  /**
   * Indicates whether this route is currently active. Root route is always
   * active.
   */
  bool get isActive;

  /**
   * Returns parameters for the currently active route. If the route is not
   * active the getter returns null.
   */
  Map get parameters;

  /**
   * Returns query parameters for the currently active route. If the route is
   * not active the getter returns null.
   */
  Map get queryParameters;

  /**
   * Whether to trigger the leave event when only the parameters change.
   */
  bool get dontLeaveOnParamChanges;

  /**
   * Used to set page title when the route [isActive].
   *
   * pageTitle can be a static String or a PageTitleHandler
   */
  dynamic pageTitle;

  /**
   * Returns a stream of [RoutePreEnterEvent] events. The [RoutePreEnterEvent]
   * event is fired when the route is matched during the routing, but before
   * any previous routes were left, or any new routes were entered. The event
   * starts at the root and propagates from parent to child routes.
   *
   * At this stage it's possible to veto entering of the route by calling
   * [RoutePreEnterEvent.allowEnter] with a [Future] returns a boolean value
   * indicating whether enter is permitted (true) or not (false).
   */
  Stream<RoutePreEnterEvent> get onPreEnter;

  /**
   * Returns a stream of [RoutePreLeaveEvent] events. The [RoutePreLeaveEvent]
   * event is fired when the route is NOT matched during the routing, but before
   * any routes are actually left, or any new routes were entered.
   *
   * At this stage it's possible to veto leaving of the route by calling
   * [RoutePreLeaveEvent.allowLeave] with a [Future] returns a boolean value
   * indicating whether enter is permitted (true) or not (false).
   */
  Stream<RoutePreLeaveEvent> get onPreLeave;

  /**
   * Returns a stream of [RouteLeaveEvent] events. The [RouteLeaveEvent]
   * event is fired when the route is being left. The event starts at the leaf
   * route and propagates from child to parent routes.
   */
  Stream<RouteLeaveEvent> get onLeave;

  /**
   * Returns a stream of [RouteEnterEvent] events. The [RouteEnterEvent] event
   * is fired when route has already been made active, but before subroutes
   * are entered.  The event starts at the root and propagates from parent
   * to child routes.
   */
  Stream<RouteEnterEvent> get onEnter;

  void addRoute(
      {String name,
      Pattern path,
      bool defaultRoute: false,
      RouteEnterEventHandler enter,
      RoutePreEnterEventHandler preEnter,
      RoutePreLeaveEventHandler preLeave,
      RouteLeaveEventHandler leave,
      mount,
      dontLeaveOnParamChanges: false,
      dynamic pageTitle,
      List<Pattern> watchQueryParameters});

  void addRedirect({Pattern path, String toRoute});

  /**
   * Queries sub-routes using the [routePath] and returns the matching [Route].
   *
   * [routePath] is a dot-separated list of route names. Ex: foo.bar.baz, which
   * means that current route should contain route named 'foo', the 'foo' route
   * should contain route named 'bar', and so on.
   *
   * If no match is found then null is returned.
   */
  Route findRoute(String routePath);

  /**
   * Create an return a new [RouteHandle] for this route.
   */
  RouteHandle newHandle();

  @override
  String toString() => '[Route: $name]';
}

/**
 * Route is a node in the tree of routes. The edge leading to the route is
 * defined by path.
 */
class RouteImpl extends Route {
  @override
  final String name;
  @override
  final UrlMatcher path;
  List<UrlMatcher> redirects;
  @override
  final RouteImpl parent;
  @override
  final dynamic pageTitle;

  /// Child routes map route names to `Route` instances
  final _routes = <String, RouteImpl>{};

  final StreamController<RouteEnterEvent> _onEnterController;
  final StreamController<RoutePreEnterEvent> _onPreEnterController;
  final StreamController<RoutePreLeaveEvent> _onPreLeaveController;
  final StreamController<RouteLeaveEvent> _onLeaveController;

  final List<Pattern> _watchQueryParameters;

  /// The default child route
  RouteImpl _defaultRoute;

  /// For deferred route loading support
  RoutableFactory _routableFactory;

  /// The currently active child route
  RouteImpl _currentRoute;
  RouteEvent _lastEvent;
  @override
  final bool dontLeaveOnParamChanges;

  @override
  Stream<RoutePreEnterEvent> get onPreEnter => _onPreEnterController.stream;
  @override
  Stream<RoutePreLeaveEvent> get onPreLeave => _onPreLeaveController.stream;
  @override
  Stream<RouteLeaveEvent> get onLeave => _onLeaveController.stream;
  @override
  Stream<RouteEnterEvent> get onEnter => _onEnterController.stream;

  RouteImpl._new(
      {this.name,
      this.path,
      this.parent,
      this.dontLeaveOnParamChanges: false,
      this.pageTitle,
      watchQueryParameters})
      : _onEnterController =
            new StreamController<RouteEnterEvent>.broadcast(sync: true),
        _onPreEnterController =
            new StreamController<RoutePreEnterEvent>.broadcast(sync: true),
        _onPreLeaveController =
            new StreamController<RoutePreLeaveEvent>.broadcast(sync: true),
        _onLeaveController =
            new StreamController<RouteLeaveEvent>.broadcast(sync: true),
        _watchQueryParameters = watchQueryParameters,
        redirects = [];

  @override
  void addRoute(
      {String name,
      Pattern path,
      bool defaultRoute: false,
      RouteEnterEventHandler enter,
      RoutePreEnterEventHandler preEnter,
      RoutePreLeaveEventHandler preLeave,
      RouteLeaveEventHandler leave,
      mount,
      dontLeaveOnParamChanges: false,
      dynamic pageTitle,
      List<Pattern> watchQueryParameters}) {
    if (name == null) {
      throw new ArgumentError('name is required for all routes');
    }
    if (name.contains(_PATH_SEPARATOR)) {
      throw new ArgumentError('name cannot contain dot.');
    }
    if (_routes.containsKey(name)) {
      throw new ArgumentError('Route $name already exists');
    }
    if (!((pageTitle == null) ||
        (pageTitle is String) ||
        (pageTitle is PageTitleHandler))) {
      throw new ArgumentError('pageTitle must be a String or PageTitleHandler');
    }

    final matcher =
        path is UrlMatcher ? path : new UrlTemplate(path.toString());

    final route = new RouteImpl._new(
        name: name,
        path: matcher,
        parent: this,
        dontLeaveOnParamChanges: dontLeaveOnParamChanges,
        pageTitle: pageTitle,
        watchQueryParameters: watchQueryParameters);

    route
      ..onPreEnter.listen(preEnter)
      ..onPreLeave.listen(preLeave)
      ..onEnter.listen(enter)
      ..onLeave.listen(leave);

    if (mount != null) {
      if (mount is RoutableFactory) {
        route._routableFactory = mount;
      } else if (mount is Function) {
        mount(route);
      } else if (mount is Routable) {
        mount.configureRoute(route);
      }
    }

    if (defaultRoute) {
      if (_defaultRoute != null) {
        _logger.warning(
            'Only one default route is supported at each level of the route'
            ' hierarchy. ${_defaultRoute.name} has already been specified'
            ' as the default for this level, so $name will not serve as the'
            ' default.');
      } else {
        _defaultRoute = route;
      }
    }
    _routes[name] = route;
  }

  @override
  void addRedirect({Pattern path, String toRoute}) {
    // use the specified path matcher to route to an existing named path
    if (_routes[toRoute] == null) {
      throw new ArgumentError('redirect must specify an existing route name');
    }

    final matcher =
        path is UrlMatcher ? path : new UrlTemplate(path.toString());
    _routes[toRoute].redirects.add(matcher);
  }

  @override
  Route findRoute(String routePath) {
    RouteImpl currentRoute = this;
    List<String> subRouteNames = routePath.split(_PATH_SEPARATOR);
    while (subRouteNames.isNotEmpty) {
      final routeName = subRouteNames.removeAt(0);
      currentRoute = currentRoute._routes[routeName];
      if (currentRoute == null) {
        _logger.warning('Invalid route name: $routeName $_routes');
        return null;
      }
    }
    return currentRoute;
  }

  String _getHead(String tail) {
    for (RouteImpl route = this; route.parent != null; route = route.parent) {
      final currentRoute = route.parent._currentRoute;
      if (currentRoute == null) {
        throw new StateError(
            'Route ${route.parent.name} has no current route.');
      }

      tail = currentRoute._reverse(tail);
    }
    return tail;
  }

  String _getTailUrl(Route routeToGo, Map parameters) {
    String tail = '';
    for (RouteImpl route = routeToGo; route != this; route = route.parent) {
      tail = route.path.reverse(
          parameters: _joinParams(
              parameters == null ? route.parameters : parameters,
              route._lastEvent),
          tail: tail);
    }
    return tail;
  }

  Map _joinParams(Map parameters, RouteEvent lastEvent) =>
      lastEvent == null ? parameters : new Map.from(lastEvent.parameters)
        ..addAll(parameters);

  /**
   * Returns a URL for this route. The tail (url generated by the child path)
   * will be passes to the UrlMatcher to be properly appended in the
   * right place.
   */
  String _reverse(String tail) =>
      path.reverse(parameters: _lastEvent.parameters, tail: tail);

  /**
   * Create an return a new [RouteHandle] for this route.
   */
  @override
  RouteHandle newHandle() {
    _logger.finest('newHandle for $this');
    return new RouteHandle._new(this);
  }

  /**
   * Indicates whether this route is currently active. Root route is always
   * active.
   */
  @override
  bool get isActive =>
      parent == null ? true : identical(parent._currentRoute, this);

  /**
   * Returns parameters for the currently active route. If the route is not
   * active the getter returns null.
   */
  @override
  Map get parameters {
    if (isActive) {
      return _lastEvent == null
          ? const {}
          : new Map.from(_lastEvent.parameters);
    }
    return null;
  }

  /**
   * Returns parameters for the currently active route. If the route is not
   * active the getter returns null.
   */
  @override
  Map get queryParameters {
    if (isActive) {
      return _lastEvent == null
          ? const {}
          : new Map.from(_lastEvent.queryParameters);
    }
    return null;
  }
}

/**
 * Route enter or leave event.
 */
abstract class RouteEvent {
  final String path;
  final Map parameters;
  final Map queryParameters;
  final Route route;

  RouteEvent(this.path, this.parameters, this.queryParameters, this.route);
}

class RoutePreEnterEvent extends RouteEvent {
  final _allowEnterFutures = <Future<bool>>[];

  RoutePreEnterEvent(path, parameters, queryParameters, route)
      : super(path, parameters, queryParameters, route);

  RoutePreEnterEvent._fromMatch(_Match m)
      : this(m.urlMatch.tail, m.urlMatch.parameters, {}, m.route);

  /**
   * Can be called with a future which will complete with a boolean
   * value allowing (true) or disallowing (false) the current navigation.
   */
  void allowEnter(Future<bool> allow) {
    _allowEnterFutures.add(allow);
  }
}

class RouteEnterEvent extends RouteEvent {
  RouteEnterEvent(path, parameters, queryParameters, route)
      : super(path, parameters, queryParameters, route);

  RouteEnterEvent._fromMatch(_Match m)
      : this(m.urlMatch.match, m.urlMatch.parameters, m.queryParameters,
            m.route);
}

class RouteLeaveEvent extends RouteEvent {
  RouteLeaveEvent(route) : super('', {}, {}, route);
}

class RoutePreLeaveEvent extends RouteEvent {
  final _allowLeaveFutures = <Future<bool>>[];

  RoutePreLeaveEvent(route) : super('', {}, {}, route);

  /**
   * Can be called with a future which will complete with a boolean
   * value allowing (true) or disallowing (false) the current navigation.
   */
  void allowLeave(Future<bool> allow) {
    _allowLeaveFutures.add(allow);
  }
}

/**
 * Event emitted when routing starts.
 */
class RouteStartEvent {
  /**
   * URI that was passed to [Router.route].
   */
  final String uri;

  /**
   * Future that completes to a boolean value of whether the routing was
   * successful.
   */
  final Future<bool> completed;

  RouteStartEvent._new(this.uri, this.completed);
}

/**
 * Stores a set of [UrlTemplate] to [Handler] associations and provides methods
 * for calling a handler for a URL path, listening to [Window] history events,
 * and creating HTML event handlers that navigate to a URL.
 */
class Router {
  HistoryProvider _history;
  final RouteImpl root;
  final _onRouteStart =
      new StreamController<RouteStartEvent>.broadcast(sync: true);
  final bool sortRoutes;
  bool _listen = false;
  WindowClickHandler _clickHandler;

  /**
   * [useFragment] determines whether this Router uses pure paths with
   * [History.pushState] or paths + fragments and [Location.assign]. The default
   * value is null which then determines the behavior based on
   * [History.supportsState].
   *
   * If [historyProvider] isn't explicitly specified, the proper provider will
   * be selected based upon [useFragment].
   * [useFragment] == true => HashProvider
   * [useFragment] == false => BrowserProvider
   */
  Router(
      {bool useFragment,
      HistoryProvider historyProvider,
      bool sortRoutes: true,
      RouterLinkMatcher linkMatcher})
      : this._init(null,
            useFragment: useFragment,
            historyProvider: historyProvider,
            sortRoutes: sortRoutes,
            linkMatcher: linkMatcher);

  Router._init(Router parent,
      {bool useFragment,
      HistoryProvider historyProvider,
      this.sortRoutes,
      RouterLinkMatcher linkMatcher})
      : root = new RouteImpl._new() {
    useFragment = useFragment ?? !History.supportsState;
    _history = historyProvider ??
        (useFragment ? new HashHistory() : new BrowserHistory());
    linkMatcher ??= new DefaultRouterLinkMatcher();
    _clickHandler = (e) => _history.clickHandler(e, linkMatcher, this.gotoUrl);
  }

  /**
   * A stream of route calls.
   */
  Stream<RouteStartEvent> get onRouteStart => _onRouteStart.stream;

  /**
   * Finds a matching [Route] added with [addRoute], parses the path
   * and invokes the associated callback. Search for the matching route starts
   * at [startingFrom] route or the root [Route] if not specified. By default
   * the common path from [startingFrom] to the current active path and target
   * path will be ignored (i.e. no leave or enter will be executed on them).
   *
   * This method does not perform any navigation, [go] should be used for that.
   * This method is used to invoke a handler after some other code navigates the
   * window, such as [listen].
   *
   * Setting [forceReload] to true (default false) will force the matched routes
   * to reload, even if they are already active and none of the parameters
   * changed.
   */
  Future<bool> route(String path,
      {Route startingFrom, bool forceReload: false}) {
    _logger.finest('route path=$path startingFrom=$startingFrom '
        'forceReload=$forceReload');
    RouteImpl baseRoute;
    List<RouteImpl> trimmedActivePath;
    if (startingFrom == null) {
      baseRoute = root;
      trimmedActivePath = activePath;
    } else {
      baseRoute = _dehandle(startingFrom);
      trimmedActivePath =
          activePath.sublist(activePath.indexOf(baseRoute) + 1).toList();
    }
    final treePath = _matchingTreePath(path, baseRoute);

    // Figure out the list of routes that will be left
    final future =
        _preLeave(path, treePath, trimmedActivePath, baseRoute, forceReload)
            .then((success) {
      // if the route change was successful, change the pageTitle
      if ((success) && (treePath.isNotEmpty)) {
        Route tailRoute = treePath.last.route;
        var pageTitle = tailRoute.pageTitle;
        _history.pageTitle =
            pageTitle is String ? pageTitle : pageTitle?.call(tailRoute);
      }
      return success;
    });
    _onRouteStart.add(new RouteStartEvent._new(path, future));

    return future;
  }

  bool isUrlActive(String path, {Route startingFrom}) {
    // get the tree path corresponding to this route
    Route baseRoute = startingFrom == null ? root : _dehandle(startingFrom);
    List<_Match> treePath = _matchingTreePath(path, baseRoute);

    // are all route segments active with matching parameters?
    for (_Match matcher in treePath) {
      // is the route active?
      if (!matcher.route.isActive) {
        return false;
      }

      // do the route parameters match?
      for (String key in matcher.urlMatch.parameters.keys) {
        if (!matcher.route.parameters.containsKey(key) ||
            matcher.route.parameters[key] != matcher.urlMatch.parameters[key]) {
          return false;
        }
      }
    }
    return true;
  }

  List<RouteView> getRoutePathForUrl(String path, {Route startingFrom}) {
    // get the tree path corresponding to this route
    Route baseRoute = startingFrom == null ? root : _dehandle(startingFrom);
    List<_Match> treePath = _matchingTreePath(path, baseRoute);
    return treePath.map((matcher) {
      return new RouteView(matcher.route,
          parameters: matcher.urlMatch.parameters,
          queryParameters: matcher.queryParameters);
    }).toList();
  }

  /**
   * Called before leaving the current route.
   *
   * If none of the preLeave listeners veto the leave, chain call [_preEnter].
   *
   * If at least one preLeave listeners veto the leave, returns a Future that
   * will resolve to false. The current route will not change.
   */
  Future<bool> _preLeave(String path, List<_Match> treePath,
      List<RouteImpl> activePath, RouteImpl baseRoute, bool forceReload) {
    List<RouteImpl> mustLeave = activePath;
    RouteImpl leaveBase = baseRoute;
    for (int i = 0, ll = min(activePath.length, treePath.length); i < ll; i++) {
      if (mustLeave.first == treePath[i].route &&
          (treePath[i].route.dontLeaveOnParamChanges ||
              !(forceReload ||
                  _paramsChanged(treePath[i].route, treePath[i])))) {
        mustLeave = mustLeave.skip(1).toList();
        leaveBase = leaveBase._currentRoute;
      } else {
        break;
      }
    }
    // Reverse the list to ensure child is left before the parent.
    mustLeave = mustLeave.toList().reversed.toList();

    List<Future<bool>> preLeaving = <Future<bool>>[];
    mustLeave.forEach((toLeave) {
      final event = new RoutePreLeaveEvent(toLeave);
      toLeave._onPreLeaveController.add(event);
      preLeaving.addAll(event._allowLeaveFutures);
    });

    return Future.wait(preLeaving).then((List<bool> results) {
      if (!results.any((r) => r == false)) {
        final leaveFn = () => _leave(mustLeave, leaveBase);
        return _preEnter(
            path, treePath, activePath, baseRoute, leaveFn, forceReload);
      }
      return new Future.value(false);
    });
  }

  void _leave(Iterable<RouteImpl> mustLeave, Route leaveBase) {
    mustLeave.forEach((toLeave) {
      final event = new RouteLeaveEvent(toLeave);
      toLeave._onLeaveController.add(event);
    });
    if (!mustLeave.isEmpty) {
      _unsetAllCurrentRoutesRecursively(leaveBase);
    }
  }

  void _unsetAllCurrentRoutesRecursively(RouteImpl r) {
    if (r._currentRoute != null) {
      _unsetAllCurrentRoutesRecursively(r._currentRoute);
      r._currentRoute = null;
    }
  }

  Future<bool> _preEnter(
      String path,
      List<_Match> treePath,
      List<Route> activePath,
      RouteImpl baseRoute,
      Function leaveFn,
      bool forceReload) {
    List<_Match> toEnter = treePath;
    String tail = path;
    RouteImpl enterBase = baseRoute;
    for (int i = 0, ll = min(toEnter.length, activePath.length); i < ll; i++) {
      if (toEnter.first.route == activePath[i] &&
          !(forceReload || _paramsChanged(activePath[i], treePath[i]))) {
        tail = treePath[i].urlMatch.tail;
        toEnter = toEnter.skip(1).toList();
        enterBase = enterBase._currentRoute;
      } else {
        break;
      }
    }
    if (toEnter.isEmpty) {
      leaveFn();
      return new Future.value(true);
    }

    // Check the last route segment to see if its child routes are loaded.
    // If not, load the child routes and short-circuit the current routing
    // operation by immediately re-routing with the same path.
    if (toEnter.isNotEmpty && toEnter.last.route._routableFactory != null) {
      RouteImpl lastRoute = toEnter.last.route;
      return lastRoute._routableFactory().then((Routable routable) {
        routable.configureRoute(lastRoute);
        lastRoute._routableFactory = null;
        return this.route(path);
      });
    }

    List<Future<bool>> preEnterFutures = <Future<bool>>[];
    toEnter.forEach((_Match matchedRoute) {
      final preEnterEvent = new RoutePreEnterEvent._fromMatch(matchedRoute);
      matchedRoute.route._onPreEnterController.add(preEnterEvent);
      preEnterFutures.addAll(preEnterEvent._allowEnterFutures);
    });
    return Future.wait(preEnterFutures).then((List<bool> results) {
      if (!results.any((v) => v == false)) {
        leaveFn();
        _enter(enterBase, toEnter, tail);
        return new Future.value(true);
      }
      return new Future.value(false);
    });
  }

  void _enter(RouteImpl startingFrom, Iterable<_Match> treePath, String path) {
    RouteImpl base = startingFrom;
    treePath.forEach((_Match matchedRoute) {
      final event = new RouteEnterEvent._fromMatch(matchedRoute);
      base._currentRoute = matchedRoute.route;
      base._currentRoute._lastEvent = event;
      matchedRoute.route._onEnterController.add(event);
      base = matchedRoute.route;
    });
  }

  /// Returns the direct child routes of [baseRoute] matching the given [path]
  List<_Match> _matchList(String path, RouteImpl baseRoute) {
    List<_Match> matchList = [];
    baseRoute._routes.values.forEach((RouteImpl r) {
      // check for a conventional route match
      UrlMatch match = r.path.match(path);
      if (match != null) {
        matchList.add(new _Match(r, match, _parseQuery(r, path), false));
      } else {
        // check for a redirect route match
        for (UrlMatcher redirect in r.redirects) {
          match = redirect.match(path);
          if (match != null) {
            matchList.add(new _Match(r, match, _parseQuery(r, path), false));
          }
        }
      }
    });

    return sortRoutes
        ? (matchList..sort((m1, m2) => m1.route.path.compareTo(m2.route.path)))
        : matchList;
  }

  /// Returns the path as a list of [_Match]
  List<_Match> _matchingTreePath(String path, RouteImpl baseRoute) {
    final treePath = <_Match>[];
    _Match match;
    do {
      match = null;
      List<_Match> matchList = _matchList(path, baseRoute);
      if (matchList.isNotEmpty) {
        if (matchList.length > 1) {
          List<Route> matchedRoutes = [];
          matchList.forEach((match) => matchedRoutes.add(match.route));
          _logger.finest("More than one route matches $path $matchedRoutes");
        }
        match = matchList.first;
      } else {
        if (baseRoute._defaultRoute != null) {
          match = new _Match(
              baseRoute._defaultRoute, new UrlMatch('', '', {}), {}, true);
        }
      }
      if (match != null) {
        treePath.add(match);
        baseRoute = match.route;
        path = match.urlMatch.tail;
      }
    } while (match != null);
    return treePath;
  }

  bool _paramsChanged(RouteImpl route, _Match match) {
    final lastEvent = route._lastEvent;
    return lastEvent == null ||
        lastEvent.path != match.urlMatch.match ||
        !mapsShallowEqual(lastEvent.parameters, match.urlMatch.parameters) ||
        !mapsShallowEqual(
            _filterQueryParams(
                lastEvent.queryParameters, route._watchQueryParameters),
            _filterQueryParams(
                match.queryParameters, route._watchQueryParameters));
  }

  Map _filterQueryParams(
      Map queryParameters, List<Pattern> watchQueryParameters) {
    if (watchQueryParameters == null) {
      return queryParameters;
    }
    Map result = {};
    queryParameters.keys.forEach((key) {
      if (watchQueryParameters
          .any((pattern) => pattern.matchAsPrefix(key) != null)) {
        result[key] = queryParameters[key];
      }
    });
    return result;
  }

  Future<bool> reload({Route startingFrom}) {
    List<RouteImpl> path = activePath;
    RouteImpl baseRoute = startingFrom == null ? root : _dehandle(startingFrom);
    if (baseRoute != root) {
      path = path.skipWhile((r) => r != baseRoute).skip(1).toList();
    }
    String reloadPath = '';
    for (int i = path.length - 1; i >= 0; i--) {
      reloadPath = path[i]._reverse(reloadPath);
    }
    reloadPath += _buildQuery(path.isEmpty ? {} : path.last.queryParameters);
    return route(reloadPath, startingFrom: startingFrom, forceReload: true);
  }

  /// Navigates to a given relative route path, and parameters.
  Future<bool> go(String routePath, Map parameters,
      {Route startingFrom,
      bool replace: false,
      Map queryParameters,
      bool forceReload: false}) {
    RouteImpl baseRoute = startingFrom == null ? root : _dehandle(startingFrom);
    final routeToGo = _findRoute(baseRoute, routePath);
    final newTail = baseRoute._getTailUrl(routeToGo, parameters) +
        _buildQuery(queryParameters);
    String newUrl = baseRoute._getHead(newTail);
    _logger.finest('go $newUrl');
    return route(newTail, startingFrom: baseRoute, forceReload: forceReload)
        .then((success) {
      if (success) {
        _go(activeUrl, replace);
      }
      return success;
    });
  }

  /// Navigate to the previous url via the historyProvider's back mechanism
  void goBack() {
    _history.back();
  }

  /// Returns an absolute URL for a given relative route path and parameters.
  String url(String routePath,
      {Route startingFrom, Map parameters, Map queryParameters}) {
    RouteImpl baseRoute = startingFrom == null ? root : _dehandle(startingFrom);
    parameters = parameters == null ? {} : parameters;
    final routeToGo = _findRoute(baseRoute, routePath);
    final tail = baseRoute._getTailUrl(routeToGo, parameters);
    return normalizeUrl(
        baseRoute._getHead(tail) + _buildQuery(queryParameters));
  }

  String normalizeUrl(String url) {
    return _history.urlStub + url;
  }

  /// Attempts to find [Route] for the specified [routePath] relative to the
  /// [baseRoute]. If nothing is found throws a [StateError].
  Route _findRoute(Route baseRoute, String routePath) {
    final route = baseRoute.findRoute(routePath);
    if (route == null) {
      throw new StateError('Invalid route path: $routePath');
    }
    return route;
  }

  /// Build an query string from a parameter `Map`
  String _buildQuery(Map queryParams) {
    if (queryParams == null || queryParams.isEmpty) {
      return '';
    }
    return '?' +
        queryParams.keys
            .map((key) => '$key=${Uri.encodeComponent(queryParams[key])}')
            .join('&');
  }

  Route _dehandle(Route r) => r is RouteHandle ? r._getHost(r) : r;

  /// Parse the query string to a parameter `Map`
  Map<String, String> _parseQuery(Route route, String path) {
    Map<String, String> params = <String, String>{};
    if (path.indexOf('?') == -1) return params;
    final queryStr = path.substring(path.indexOf('?') + 1);
    queryStr.split('&').forEach((String keyValPair) {
      List<String> keyVal = _parseKeyVal(keyValPair);
      final key = keyVal[0];
      if (key.isNotEmpty) {
        params[key] = Uri.decodeComponent(keyVal[1]);
      }
    });
    return params;
  }

  /**
   * Parse a key value pair (`"key=value"`) and returns a list of
   * `["key", "value"]`.
   */
  List<String> _parseKeyVal(String kvPair) {
    if (kvPair.isEmpty) {
      return const ['', ''];
    }
    final splitPoint = kvPair.indexOf('=');

    return (splitPoint == -1)
        ? [kvPair, '']
        : [kvPair.substring(0, splitPoint), kvPair.substring(splitPoint + 1)];
  }

  /**
   * Listens for window history events and invokes the router. On older
   * browsers the hashChange event is used instead.
   */
  void listen({bool ignoreClick: false, Element appRoot}) {
    _logger.finest('listen ignoreClick=$ignoreClick');
    if (_listen) {
      throw new StateError('listen can only be called once');
    }
    _listen = true;

    // modified with history alternative
    _history.onChange.listen((_) {
      // only route if the new url isn't already active
      if (activeUrl != _history.path) {
        route(_history.path).then((allowed) {
          // if not allowed, we need to restore the browser location
          if (!allowed) {
            _history.back();
          } else if (activeUrl != _history.path) {
            // replace the url in the case of redirects entered into browser address bar
            _go(activeUrl, true);
          }
        });
      }
    });
    route(_history.path).then((allowed) {
      if (!allowed) {
        _logger.fine('Initial route not allowed: ${_history.path}');
        route('');
      }
    });

    if (!ignoreClick) {
      if (appRoot == null) {
        appRoot = window.document.documentElement;
      }
      _logger.finest('listen on win');
      appRoot.onClick
          .where((MouseEvent e) => !(e.ctrlKey || e.metaKey || e.shiftKey))
          .listen(_clickHandler);
    }
  }

  /**
   * Navigates the browser to the path produced by [url] with [args] by calling
   * [History.pushState], then invokes the handler associated with [url].
   *
   * On older browsers [Location.assign] is used instead with the fragment
   * version of the UrlTemplate.
   */
  Future<bool> gotoUrl(String url, {bool replace: false}) {
    return route(url).then((success) {
      if (success) {
        _go(activeUrl, replace);
      }
      return success;
    });
  }

  void _go(String path, bool replace) {
    _history.go(path, replace);
  }

  /**
   * Returns the current active route path in the route tree.
   * Excludes the root path.
   */
  List<RouteImpl> get activePath {
    final res = <RouteImpl>[];
    RouteImpl route = root;

    while (route._currentRoute != null) {
      route = route._currentRoute;
      res.add(route);
    }
    return res;
  }

  /**
   * Returns the url string corresponding to the current active route path
   */
  String get activeUrl {
    String activeUrl = '';
    List<RouteImpl> path = activePath;
    for (int i = path.length - 1; i >= 0; i--) {
      activeUrl = path[i]._reverse(activeUrl);
    }
    activeUrl += _buildQuery(path.isEmpty ? {} : path.last.queryParameters);
    return activeUrl;
  }

  /**
   * A shortcut for router.root.findRoute().
   */
  Route findRoute(String routePath) => root.findRoute(routePath);
}

class _Match {
  final RouteImpl route;
  final UrlMatch urlMatch;
  final Map queryParameters;
  final bool isDefault;

  _Match(this.route, this.urlMatch, this.queryParameters, this.isDefault);
}
