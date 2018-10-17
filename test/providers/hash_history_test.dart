@TestOn('browser')
library route.providers.hash_history_test;

import 'dart:async';
import 'dart:html';

import 'package:dart2_constant/core.dart' as constant;
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:route_hierarchical/client.dart';
import 'package:route_hierarchical/history_provider.dart';

import '../util/mocks.dart';
import '../util/utils.dart';
import 'common_tests.dart';

main() {
  group('HashHistory', () {
    commonProviderTests(() => new Router(historyProvider: new HashHistory()));

    group('go', () {
      MockWindow mockWindow;
      HashHistory historyProvider;
      Router router;

      setUp(() {
        mockWindow = new MockWindow();
        historyProvider = new HashHistory(windowImpl: mockWindow);
        router = new Router(historyProvider: historyProvider);
      });

      test('should use location.assign/.replace when useFragment=true',
          () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        await router.go('articles', {});
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/articles'));

        await router.go('articles', {}, replace: true);
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/articles'));
      });

      test('should encode parameters in the URL', () async {
        router.root.addRoute(name: 'foo', path: '/foo/:param');
        await router.go('foo', {'param': 'something'});
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/foo/something'));
      });

      test('should encode query parameters in the URL', () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        final queryParams = {'foo': 'foo bar', 'bar': '%baz+aux'};
        await router.go('articles', {}, queryParameters: queryParams);
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last,
            equals('#/articles?foo=foo%20bar&bar=%25baz%2Baux'));
      });

      test('should work with hierarchical go', () async {
        router.root
          ..addRoute(
              name: 'a',
              path: '/:foo',
              mount: (child) => child..addRoute(name: 'b', path: '/:bar'));

        final routeA = router.root.findRoute('a');

        await router.go('a.b', {});
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/null/null'));

        await router.go('a.b', {'foo': 'aaaa', 'bar': 'bbbb'});
        expect(mockWindow.history.urlList.length, equals(2));
        expect(mockWindow.history.urlList.last, equals('#/aaaa/bbbb'));

        await router.go('b', {'bar': 'bbbb'}, startingFrom: routeA);
        expect(mockWindow.history.urlList.length, equals(3));
        expect(mockWindow.history.urlList.last, equals('#/aaaa/bbbb'));
      });

      test('should attempt to reverse default routes', () async {
        final counters = <String, int>{'aEnter': 0, 'bEnter': 0};
        router.root
          ..addRoute(
              name: 'a',
              defaultRoute: true,
              path: '/:foo',
              enter: (_) => counters['aEnter']++,
              mount: (child) => child
                ..addRoute(
                    name: 'b',
                    defaultRoute: true,
                    path: '/:bar',
                    enter: (_) => counters['bEnter']++));

        expect(counters, {'aEnter': 0, 'bEnter': 0});

        await router.route('');
        expect(counters, {'aEnter': 1, 'bEnter': 1});

        final routeA = router.root.findRoute('a');
        await router.go('b', {'bar': 'bbb'}, startingFrom: routeA);
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/null/bbb'));
      });

      test('should force reload already active routes', () async {
        final counters = <String, int>{'aEnter': 0, 'bEnter': 0};
        router.root
          ..addRoute(
              name: 'a',
              path: '/foo',
              enter: (_) => counters['aEnter']++,
              mount: (child) => child
                ..addRoute(
                    name: 'b',
                    path: '/bar',
                    enter: (_) => counters['bEnter']++));

        expect(counters, {'aEnter': 0, 'bEnter': 0});

        await router.go('a.b', {});
        expect(counters, {'aEnter': 1, 'bEnter': 1});
        await router.go('a.b', {});
        // didn't force reload, so should not change
        expect(counters, {'aEnter': 1, 'bEnter': 1});
        await router.go('a.b', {}, forceReload: true);
        expect(counters, {'aEnter': 2, 'bEnter': 2});
      });

      test('should update page title if the title property is set', () async {
        router.root.addRoute(name: 'foo', path: '/foo', pageTitle: 'Foo');
        await router.go('foo', {});
        verify(mockWindow.document.title = 'Foo');
      });

      test('should not change page title if the title property is not set',
          () async {
        router.root.addRoute(name: 'foo', path: '/foo');

        expect(mockWindow.document.title, equals('page title'));

        await router.go('foo', {});
        expect(mockWindow.document.title, equals('page title'));
      });

      test('should support dynamic pageTitle based on route params', () async {
        router.root.addRoute(
            name: 'foo',
            path: '/foo/:param',
            pageTitle: (Route route) =>
                'Foo: ${route.parameters['param']} - ${route.queryParameters['what']}');
        await router.go('foo', {'param': 'something'},
            queryParameters: {'what': 'ever'});
        expect(historyProvider.pageTitle, 'Foo: something - ever');
      });
    });

    group('gotoUrl', () {
      MockWindow mockWindow;
      HashHistory historyProvider;
      Router router;

      setUp(() {
        mockWindow = new MockWindow();
        historyProvider = new HashHistory(windowImpl: mockWindow);
        router = new Router(historyProvider: historyProvider);
      });

      test('should use history.push/.replaceState when using BrowserHistory',
          () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        await router.gotoUrl('/articles');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/articles'));

        await router.gotoUrl('/articles', replace: true);
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/articles'));
      });

      test('should support parameters in the URL', () async {
        router.root.addRoute(name: 'foo', path: '/foo/:param');
        await router.gotoUrl('/foo/something');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/foo/something'));
        expect(router.activePath.last.parameters, {'param': 'something'});
      });

      test('should support query parameters in the URL', () async {
        router.root.addRoute(name: 'articles', path: '/articles');
        await router.gotoUrl('/articles?foo=foo%20bar&bar=%25baz%2Baux');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last,
            equals('#/articles?foo=foo%20bar&bar=%25baz%2Baux'));
        expect(router.activePath.last.queryParameters,
            {'foo': 'foo bar', 'bar': '%baz+aux'});
      });

      test('should work with hierarchical routes', () async {
        router.root
          ..addRoute(
              name: 'a',
              path: '/:foo',
              mount: (child) => child..addRoute(name: 'b', path: '/:bar'));

        Route routeA = router.root.findRoute('a');
        Route routeB = router.root.findRoute('a.b');

        await router.gotoUrl('/aaaa');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/aaaa'));
        expect(routeA.isActive, true);
        expect(routeA.parameters, {'foo': 'aaaa'});
        expect(routeB.isActive, false);
        expect(routeB.parameters, isNull);

        await router.gotoUrl('/aaaa/bbbb');
        expect(mockWindow.history.urlList.length, equals(2));
        expect(mockWindow.history.urlList.last, equals('#/aaaa/bbbb'));
        expect(routeA.parameters, {'foo': 'aaaa'});
        expect(routeB.parameters, {'bar': 'bbbb'});
      });

      test('should update page title if the title property is set', () async {
        router.root.addRoute(name: 'foo', path: '/foo', pageTitle: 'Foo');

        await router.gotoUrl('/foo');
        verify(mockWindow.document.title = 'Foo');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/foo'));
      });

      test('should not change page title if the title property is not set',
          () async {
        router.root.addRoute(name: 'foo', path: '/foo');

        await router.gotoUrl('/foo');
        verifyNever(mockWindow.document.title = 'Foo');
        expect(mockWindow.history.urlList.length, equals(1));
        expect(mockWindow.history.urlList.last, equals('#/foo'));
      });

      test('should support dynamic pageTitle based on route properties',
          () async {
        router.root.addRoute(
            name: 'foo',
            path: '/foo/:param',
            pageTitle: (Route route) =>
                'Foo: ${route.parameters['param']} - ${route.queryParameters['what']}');
        await router.gotoUrl('/foo/something?what=ever');
        expect(historyProvider.pageTitle, 'Foo: something - ever');
      });
    });

    group('goBack', () {
      test('should go to the previous route', () async {
        MockWindow mockWindow = new MockWindow();
        Router router = new Router(
            historyProvider: new HashHistory(windowImpl: mockWindow));

        router.root.addRoute(name: 'foo', path: '/foo');
        router.root.addRoute(name: 'bar', path: '/bar');

        await router.go('foo', {});
        await router.go('bar', {});
        expect(mockWindow.history.urlList, equals(['#/foo', '#/bar']));

        router.goBack();
        expect(mockWindow.history.urlList, equals(['#/foo']));
      });
    });

    group('url', () {
      test('should reconstruct url', () async {
        final mockWindow = new MockWindow();
        final router = new Router(
            historyProvider: new HashHistory(windowImpl: mockWindow));
        router.root
          ..addRoute(
              name: 'a',
              defaultRoute: true,
              path: '/:foo',
              mount: (child) => child
                ..addRoute(name: 'b', defaultRoute: true, path: '/:bar'));

        final routeA = router.root.findRoute('a');

        await router.route('');
        expect(router.url('a.b'), '#/null/null');
        expect(router.url('a.b', parameters: {'foo': 'aaa'}), '#/aaa/null');
        expect(
            router.url('b', parameters: {'bar': 'bbb'}, startingFrom: routeA),
            '#/null/bbb');

        await router.route('/foo/bar');
        expect(router.url('a.b'), '#/foo/bar');
        expect(router.url('a.b', parameters: {'foo': 'aaa'}), '#/aaa/bar');
        expect(
            router.url('b', parameters: {'bar': 'bbb'}, startingFrom: routeA),
            '#/foo/bbb');
        expect(
            router.url('b',
                parameters: {'foo': 'aaa', 'bar': 'bbb'}, startingFrom: routeA),
            '#/foo/bbb');

        expect(
            router.url('b',
                parameters: {'bar': 'bbb'},
                queryParameters: {'param1': 'val1'},
                startingFrom: routeA),
            '#/foo/bbb?param1=val1');
      });
    });

    group('activePath', () {
      MockWindow mockWindow;
      Router router;

      setUp(() {
        mockWindow = new MockWindow();
        router = new Router(
            historyProvider: new BrowserHistory(windowImpl: mockWindow));
      });

      test('should correctly identify active path after relative go', () async {
        router.root
          ..addRoute(
              name: 'foo',
              path: '/foo',
              mount: (child) => child
                ..addRoute(
                    name: 'bar',
                    path: '/bar',
                    mount: (child) => child
                      ..addRoute(
                          name: 'baz', path: '/baz', mount: (child) => child))
                ..addRoute(
                    name: 'qux',
                    path: '/qux',
                    mount: (child) => child
                      ..addRoute(
                          name: 'aux', path: '/aux', mount: (child) => child)));

        final strPath =
            (List<Route> path) => path.map((Route r) => r.name).join('.');

        expect(strPath(router.activePath), '');

        await router.route('/foo');
        expect(strPath(router.activePath), 'foo');

        final foo = router.findRoute('foo');
        await router.go('bar', {}, startingFrom: foo);
        expect(strPath(router.activePath), 'foo.bar');
      });

      test(
          'should correctly identify active path after relative go from deeper active path',
          () async {
        router.root
          ..addRoute(
              name: 'foo',
              path: '/foo',
              mount: (child) => child
                ..addRoute(
                    name: 'bar',
                    path: '/bar',
                    mount: (child) => child
                      ..addRoute(
                          name: 'baz', path: '/baz', mount: (child) => child))
                ..addRoute(
                    name: 'qux',
                    path: '/qux',
                    mount: (child) => child
                      ..addRoute(
                          name: 'aux', path: '/aux', mount: (child) => child)));

        final strPath =
            (List<Route> path) => path.map((Route r) => r.name).join('.');

        expect(strPath(router.activePath), '');

        await router.route('/foo/qux/aux');
        expect(strPath(router.activePath), 'foo.qux.aux');

        final foo = router.findRoute('foo');
        await router.go('bar', {}, startingFrom: foo);
        expect(strPath(router.activePath), 'foo.bar');
      });
    });

    group('listen', () {
      group('fragment', () {
        test('should route current hash on listen', () {
          final mockWindow = new MockWindow();
          when(mockWindow.location.hash).thenReturn('#/foo');
          final router = new Router(
              historyProvider: new HashHistory(windowImpl: mockWindow));
          router.root.addRoute(name: 'foo', path: '/foo');
          router.onRouteStart
              .listen(expectAsync1((RouteStartEvent start) async {
            await start.completed;
            expect(router.findRoute('foo').isActive, isTrue);
          }, count: 1));
          router.listen(ignoreClick: true);
        });

        test('should process url changes for route rejection', () async {
          final mockWindow = new MockWindow();
          final router = new Router(
              historyProvider: new HashHistory(windowImpl: mockWindow));
          router.root
            ..addRoute(
                name: 'foo',
                path: '/foo',
                preEnter: (RoutePreEnterEvent e) {
                  Completer<bool> completer = new Completer();
                  completer.complete(false);
                  return e.allowEnter(completer.future);
                })
            ..addRoute(name: 'bar', path: '/bar');

          router.listen();

          await router.go('bar', {});
          expect(mockWindow.history.urlList.length, equals(1));
          expect(mockWindow.history.urlList.last, equals('#/bar'));

          when(mockWindow.location.hash).thenReturn('#/foo');
          mockWindow.changeHash('#/foo');

          await nextTick();
          expect(mockWindow.history.backCalled, isTrue);
        });
      });

      group('links', () {
        MockWindow mockWindow;
        HistoryProvider history;
        Router router;
        Element toRemove;

        setUp(() {
          mockWindow = new MockWindow();
          history = new HashHistory(windowImpl: mockWindow);
          router = new Router(historyProvider: history);
          router.root.addRoute(name: 'foo', path: '/foo', pageTitle: 'Foo');
        });

        tearDown(() {
          if (toRemove != null) {
            toRemove.remove();
            toRemove = null;
          }
        });

        test('it should be called if event triggered on anchor element',
            () async {
          AnchorElement anchor = new AnchorElement();
          anchor.href = '#/foo';
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals('page title'));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });

        test('it should not be called if anchor element has a target attribute',
            () async {
          AnchorElement anchor = new AnchorElement();
          anchor.href = '#/foo';
          anchor.target = '_blank';
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals('page title'));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('page title'));
          expect(router.findRoute('foo').isActive, isFalse);
        });

        test(
            'it should be called if event triggered on child of an anchor element',
            () async {
          Element anchorChild = new DivElement();
          AnchorElement anchor = new AnchorElement();
          anchor.href = '#/foo';
          anchor.append(anchorChild);
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals('page title'));
          expect(router.findRoute('foo').isActive, isFalse);

          anchorChild.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });

        test('should correctly resolve redirect routes', () async {
          router.root.addRedirect(path: '/bar', toRoute: 'foo');

          AnchorElement anchor = new AnchorElement();
          anchor.href = '#/bar';
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals('page title'));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });
      });
    });
  });
}
