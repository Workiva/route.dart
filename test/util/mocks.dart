// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library route.test.util.mocks;

import 'dart:async';
import 'dart:html';

import 'package:mockito/mockito.dart';
import 'package:route_hierarchical/client.dart';

class MockWindow extends Mock implements Window {
  @override
  MockHistory history;

  @override
  Location get location => _location;

  @override
  MockDocument document;

  StreamController<Event> _onHashChangeController;
  StreamController<PopStateEvent> _onPopStateController;
  List<String> _urlList;
  MockLocation _location;

  MockWindow({MockLocation mockLocation}) {
    _urlList = [];
    history = new MockHistory(_urlList);
    _location = mockLocation ?? new MockLocation(_urlList);
    document = new MockDocument();

    // keep track of a basic history list
    _onHashChangeController = new StreamController<Event>();
    when(this.onHashChange)
        .thenAnswer((i) => _onHashChangeController.stream.asBroadcastStream());
    _onPopStateController = new StreamController<PopStateEvent>();
    when(this.onPopState)
        .thenAnswer((i) => _onPopStateController.stream.asBroadcastStream());
  }

  changeHash(String hash) async {
    _onHashChangeController.add(new HashChangeEvent(hash, newUrl: hash));
    _onPopStateController.add(new PopStateEvent(hash));
  }
}

class MockHistory extends Mock implements History {
  List<String> urlList;
  MockHistory(this.urlList);
  bool backCalled = false;

  @override
  back() {
    backCalled = true;
    urlList.removeLast();
  }

  @override
  replaceState(Object data, String title, String url, [Map options]) {
    urlList.removeLast();
    urlList.add(url);
  }

  @override
  pushState(Object data, String title, String url, [Map options]) {
    urlList.add(url);
  }
}

class MockLocation extends Mock implements Location {
  List<String> urlList;
  MockLocation(this.urlList) {
    when(host).thenAnswer((i) => window.location.host);
    when(hash).thenAnswer((i) => '');
  }

  @override
  replace(String url) {
    urlList.removeLast();
    urlList.add(url);
  }

  @override
  assign([String url]) {
    urlList.add(url);
  }
}

class MockDocument extends Mock implements HtmlDocument {
  MockDocument() {
    when(title).thenAnswer((i) => 'page title');
  }
}

class MockMouseEvent extends Mock implements MouseEvent {
  MockMouseEvent({EventTarget target, List<Node> path}) {
    when(this.target).thenReturn(target);
    when(this.path).thenReturn(path);
  }

  MockMouseEvent.withAnchor({String target: '', String href: ''}) {
    AnchorElement anchor = new AnchorElement();
    anchor.href = href;
    anchor.target = target;

    when(this.target).thenReturn(anchor);
    when(this.path).thenReturn([anchor]);
  }
}

class MockRouter extends Mock implements Router {}

class MockRoutable implements Routable {
  bool routesConfigured = false;

  @override
  void configureRoute(Route router) {
    router
      ..addRoute(name: 'default', path: '', defaultRoute: true)
      ..addRoute(name: 'foo', path: '/foo')
      ..addRoute(name: 'bar', path: '/bar');
    routesConfigured = true;
  }
}

class MockRoutableDeep implements Routable {
  bool routesConfigured = false;
  Routable deepRoutable;

  @override
  void configureRoute(Route router) {
    router
      ..addRoute(name: 'default', path: '', defaultRoute: true)
      ..addRoute(
          name: 'foo',
          path: '/foo',
          mount: () async {
            return deepRoutable = new MockRoutable();
          });
    routesConfigured = true;
  }
}
