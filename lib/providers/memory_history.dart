part of route.history_provider;

class MemoryHistory implements HistoryProvider {
  // keep a list of urls
  List<String> _urlList;

  String _pageTitle = '';

  // keep track of a unique namespace for internal urls
  final String _namespace = 'router${new Uuid().v4()}:';

  // broadcast changes to url
  StreamController<String> _urlStreamController;
  Stream<String> _urlStream;

  MemoryHistory({List<String> urlHistory}) {
    _urlList = urlHistory ?? [''];
    _urlStreamController = new StreamController<String>();
    _urlStream = _urlStreamController.stream.asBroadcastStream();
  }

  @override
  Stream get onChange => _urlStream;

  @override
  String get path => _urlList.isNotEmpty ? _urlList.last : '';

  @override
  String get urlStub => _namespace;

  @override
  String get pageTitle => _pageTitle;

  @override
  set pageTitle(String title) {
    if (title != null) {
      _pageTitle = title;
    }
  }

  @override
  void clickHandler(Event e, RouterLinkMatcher linkMatcher,
      Future<bool> gotoUrl(String url)) {
    Element el = e.target;
    while (el != null && el is! AnchorElement) {
      el = el.parent;
    }

    if (el == null) return;
    assert(el is AnchorElement);
    AnchorElement anchor = el;
    if (!linkMatcher.matches(anchor)) {
      return;
    }
    if (anchor.target != null && anchor.target.isNotEmpty) {
      // Prevent router from swallowing links that should open in another window
      return;
    }
    if (anchor.origin.startsWith(urlStub)) {
      e.preventDefault();
      gotoUrl(anchor.pathname);
    }
  }

  @override
  void go(String path, bool replace) {
    if (replace) {
      _urlList.removeLast();
    }
    _urlList.add(path);
    _urlStreamController.add(path);
  }

  @override
  void back() {
    if (_urlList.length > 1) {
      _urlList.removeLast();
      _urlStreamController.add(_urlList.last);
    }
  }
}
