@TestOn('browser')
library route.providers.memory_history_test;

import 'dart:async';
import 'dart:html';

import 'package:dart2_constant/core.dart' as constant;
import 'package:route_hierarchical/client.dart';
import 'package:route_hierarchical/history_provider.dart';
import 'package:test/test.dart';

import '../util/utils.dart';
import 'common_tests.dart';

main() {
  group('MemoryHistory', () {
    commonProviderTests(() => new Router(historyProvider: new MemoryHistory()));

    group('go', () {
      List<String> urlHistory;
      MemoryHistory historyProvider;
      Router router;

      setUp(() {
        urlHistory = [''];
        historyProvider = new MemoryHistory(urlHistory: urlHistory);
        router = new Router(historyProvider: historyProvider);
      });

      test('should change the current url', () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        expect(urlHistory, equals(['']));
        await router.go('articles', {});
        expect(router.activePath.last.name, equals('articles'));
        expect(urlHistory, equals(['', '/articles']));

        await router.go('articles', {}, replace: true);
        expect(router.activePath.last.name, equals('articles'));
        expect(urlHistory, equals(['', '/articles']));
      });

      test('should encode parameters in the URL', () async {
        router.root.addRoute(name: 'foo', path: '/foo/:param');
        await router.go('foo', {'param': 'something'});
        expect(urlHistory, equals(['', '/foo/something']));
      });

      test('should encode query parameters in the URL', () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        final queryParams = {'foo': 'foo bar', 'bar': '%baz+aux'};
        await router.go('articles', {}, queryParameters: queryParams);
        expect(urlHistory,
            equals(['', '/articles?foo=foo%20bar&bar=%25baz%2Baux']));
      });

      test('should work with hierarchical go', () async {
        router.root
          ..addRoute(
              name: 'a',
              path: '/:foo',
              mount: (child) => child..addRoute(name: 'b', path: '/:bar'));

        final routeA = router.root.findRoute('a');

        await router.go('a.b', {});
        expect(urlHistory, equals(['', '/null/null']));

        await router.go('a.b', {'foo': 'aaaa', 'bar': 'bbbb'});
        expect(urlHistory, equals(['', '/null/null', '/aaaa/bbbb']));

        await router.go('b', {'bar': 'bbbb'}, startingFrom: routeA);
        expect(
            urlHistory, equals(['', '/null/null', '/aaaa/bbbb', '/aaaa/bbbb']));
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
        expect(urlHistory, equals(['', '/null/bbb']));
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
        expect(historyProvider.pageTitle, 'Foo');
      });

      test('should not change page title if the title property is not set',
          () async {
        router.root.addRoute(name: 'foo', path: '/foo');
        await router.go('foo', {});
        expect(historyProvider.pageTitle, '');
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
      List<String> urlHistory;
      MemoryHistory historyProvider;
      Router router;

      setUp(() {
        urlHistory = [''];
        historyProvider = new MemoryHistory(urlHistory: urlHistory);
        router = new Router(historyProvider: historyProvider);
      });

      test('should use history.push/.replaceState when using BrowserHistory',
          () async {
        router.root.addRoute(name: 'articles', path: '/articles');

        expect(urlHistory, equals(['']));
        await router.gotoUrl('/articles');
        expect(urlHistory, equals(['', '/articles']));

        await router.gotoUrl('/articles', replace: true);
        expect(urlHistory, equals(['', '/articles']));
      });

      test('should support parameters in the URL', () async {
        router.root.addRoute(name: 'foo', path: '/foo/:param');
        await router.gotoUrl('/foo/something');
        expect(urlHistory, equals(['', '/foo/something']));
        expect(router.activePath.last.parameters, {'param': 'something'});
      });

      test('should support query parameters in the URL', () async {
        router.root.addRoute(name: 'articles', path: '/articles');
        await router.gotoUrl('/articles?foo=foo%20bar&bar=%25baz%2Baux');
        expect(urlHistory,
            equals(['', '/articles?foo=foo%20bar&bar=%25baz%2Baux']));
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
        expect(urlHistory, equals(['', '/aaaa']));
        expect(routeA.isActive, true);
        expect(routeA.parameters, {'foo': 'aaaa'});
        expect(routeB.isActive, false);
        expect(routeB.parameters, isNull);

        await router.gotoUrl('/aaaa/bbbb');
        expect(urlHistory, equals(['', '/aaaa', '/aaaa/bbbb']));
        expect(routeA.parameters, {'foo': 'aaaa'});
        expect(routeB.parameters, {'bar': 'bbbb'});
      });

      test('should update page title if the title property is set', () async {
        router.root.addRoute(name: 'foo', path: '/foo', pageTitle: 'Foo');

        await router.gotoUrl('/foo');
        expect(historyProvider.pageTitle, 'Foo');
        expect(urlHistory, equals(['', '/foo']));
      });

      test('should not change page title if the title property is not set',
          () async {
        router.root.addRoute(name: 'foo', path: '/foo');

        await router.gotoUrl('/foo');
        expect(historyProvider.pageTitle, '');
        expect(urlHistory, equals(['', '/foo']));
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
        List<String> urlHistory = [];
        Router router = new Router(
            historyProvider: new MemoryHistory(urlHistory: urlHistory));

        router.root.addRoute(name: 'foo', path: '/foo');
        router.root.addRoute(name: 'bar', path: '/bar');

        await router.go('foo', {});
        await router.go('bar', {});
        expect(urlHistory, equals(['/foo', '/bar']));

        router.goBack();
        expect(urlHistory, equals(['/foo']));
      });
    });

    group('url', () {
      test('should reconstruct url', () async {
        final router = new Router(historyProvider: new MemoryHistory());
        router.root
          ..addRoute(
              name: 'a',
              defaultRoute: true,
              path: '/:foo',
              mount: (child) => child
                ..addRoute(name: 'b', defaultRoute: true, path: '/:bar'));

        final routeA = router.root.findRoute('a');

        await router.route('');
        expect(router.url('a.b'), router.normalizeUrl('/null/null'));
        expect(router.url('a.b', parameters: {'foo': 'aaa'}),
            router.normalizeUrl('/aaa/null'));
        expect(
            router.url('b', parameters: {'bar': 'bbb'}, startingFrom: routeA),
            router.normalizeUrl('/null/bbb'));

        await router.route('/foo/bar');
        expect(router.url('a.b'), router.normalizeUrl('/foo/bar'));
        expect(router.url('a.b', parameters: {'foo': 'aaa'}),
            router.normalizeUrl('/aaa/bar'));
        expect(
            router.url('b', parameters: {'bar': 'bbb'}, startingFrom: routeA),
            router.normalizeUrl('/foo/bbb'));
        expect(
            router.url('b',
                parameters: {'foo': 'aaa', 'bar': 'bbb'}, startingFrom: routeA),
            router.normalizeUrl('/foo/bbb'));

        expect(
            router.url('b',
                parameters: {'bar': 'bbb'},
                queryParameters: {'param1': 'val1'},
                startingFrom: routeA),
            router.normalizeUrl('/foo/bbb?param1=val1'));
      });
    });

    group('activePath', () {
      Router router;

      setUp(() {
        router = new Router(historyProvider: new MemoryHistory());
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
      group('links', () {
        HistoryProvider history;
        Router router;
        Element toRemove;

        setUp(() {
          history = new MemoryHistory();
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
          anchor.href = router.normalizeUrl('/foo');
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals(''));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });

        test('it should not be called if anchor element has a target attribute',
            () async {
          AnchorElement anchor = new AnchorElement();
          anchor.href = '/foo';
          anchor.target = '_blank';
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals(''));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals(''));
          expect(router.findRoute('foo').isActive, isFalse);
        });

        test(
            'it should be called if event triggered on child of an anchor element',
            () async {
          Element anchorChild = new DivElement();
          AnchorElement anchor = new AnchorElement();
          anchor.href = router.normalizeUrl('/foo');
          anchor.append(anchorChild);
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals(''));
          expect(router.findRoute('foo').isActive, isFalse);

          anchorChild.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });

        test('should correctly resolve redirect routes', () async {
          router.root.addRedirect(path: '/bar', toRoute: 'foo');

          AnchorElement anchor = new AnchorElement();
          anchor.href = router.normalizeUrl('/bar');
          document.body.append(toRemove = anchor);

          router.listen(appRoot: anchor);

          expect(history.pageTitle, equals(''));
          expect(router.findRoute('foo').isActive, isFalse);

          anchor.click();

          await new Future.delayed(constant.Duration.zero);
          expect(history.pageTitle, equals('Foo'));
          expect(router.findRoute('foo').isActive, isTrue);
        });
      });
    });

    test('should support history.back', () async {
      List<String> urlHistory = [''];
      MemoryHistory memHistory = new MemoryHistory(urlHistory: urlHistory);
      final router = new Router(historyProvider: memHistory);
      router.root
        ..addRoute(name: 'foo', path: '/foo')
        ..addRoute(name: 'bar', path: '/bar');

      expect(urlHistory, equals(['']));
      await router.go('foo', {});
      expect(urlHistory, equals(['', '/foo']));

      await router.go('bar', {});
      expect(urlHistory, equals(['', '/foo', '/bar']));

      memHistory.back();
      await nextTick();
      expect(urlHistory, equals(['', '/foo']));
    });
  });
}
