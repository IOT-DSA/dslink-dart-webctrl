import 'dart:async';

import 'package:dslink/dslink.dart';
import 'package:dslink/utils.dart' show logger;

import 'common.dart';
import 'get_history.dart';
import 'proxy_provider.dart';
import '../client.dart';

class RefreshActionNode extends SimpleNode {
  RefreshActionNode(String path, NodeProvider provider) : super(path, provider);

  @override
  onInvoke(Map<String, dynamic> params) {
    (parent as ProxyNode)?.refresh();
    return {};
  }
}

class ProxyNode extends SimpleNode {
  static Set<Function> updateFunctions = new Set<Function>();
  static Timer timer;
  static void startTimer() {
    Duration interval = new Duration(seconds: 5);
    timer = new Timer.periodic(interval, (_) {
      for (var x in updateFunctions) {
        x();
      }
    });
  }

  WCClient _client;
  bool _refreshing = false;

  String get remotePath {
    var x = path.split("/").skip(2).join("/");
    x = "/${x}";
    if (!x.startsWith("/")) {
      x = "/${x}";
    }

    if (x.endsWith("/")) {
      x = x.substring(0, x.length - 1);
    }

    if (x == "") {
      x = "/";
    }
    return x;
  }

  Future<WCClient> getClient() async {
    if (_client != null) return _client;

    var p = parent;
    while (p != null && p is! ConnectionHandle) {
      p = p.parent;
    }

    return _client = await (p as ConnectionHandle)?.client;
  }

  ProxyNode(String path, SimpleNodeProvider p) : super(path, p) {
    updateFunction = () async {
      var cl = await getClient();
      if (cl == null) {
        return;
      }

      var x = remotePath;

      cl.queryValue(x).then((value) {
        if (value != null) {
          updateValue(value);
          addSettableIfNotExists();
        } else {
          removeSettable();
        }
      }).catchError((e, stack) {
      });
    };
  }

  @override
  void onCreated() {
    if (!children.containsKey("Refresh")) {
      provider.addNode("${path}/Refresh", {
        r"$is": "refresh",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [],
        r"$columns": []
      });
    }

    if (callbacks.isNotEmpty) {
      updateFunctions.add(updateFunction);
    }

  }

  void addSettableIfNotExists() {
    if (!children.containsKey("Set_Value")) {
      provider.addNode("${path}/Set_Value", {
        r"$name": "Set",
        r"$is": "setValue",
        r"$invokable": "write",
        r"$result": "values",
        r"$params": [
          {
            "name": "value",
            "type": "dynamic"
          }
        ],
        r"$columns": [
          {
            "name": "success",
            "type": "bool"
          }
        ]
      });
    }
  }

  void removeSettable() {
    if (children.containsKey("Set_Value")) {
      provider.removeNode("${path}/Set_Value");
    }
  }

  void refresh() {
    if (_refreshing) return;
    for (var c in children.keys.toList()) {
      provider.removeNode("${path}/${c}");
    }
    initialized = false;
    _refreshing = true;
    initialize(_client);
  }

  void onStartListListen() {
    if (initialized) return;
    initialize();
  }

  bool initialized = false;

  @override
  RespSubscribeListener subscribe(callback(ValueUpdate callback), [int cachelevel = 0]) {
    onSubscribe();
    if (!hasSubscriber) {
      proxySubscribe();
    }

    callbacks[callback] = cachelevel;

    return new RespSubscribeListener(this, callback);
  }

  @override
  void unsubscribe(callback(ValueUpdate)) {
    onUnsubscribe();
    super.unsubscribe(callback);
    if (!hasSubscriber) {
      proxyUnsubscribe();
    }
  }

  Function updateFunction;

  void proxySubscribe() {
    updateFunctions.add(updateFunction);
  }

  void proxyUnsubscribe() {
    updateFunctions.remove(updateFunction);
  }

  void initialize([WCClient client]) {
    if (path.startsWith("/defs/")) {
      return;
    }

    if (client != null) {
      _client = client;
    }

    if (_client == null) {
      getClient().then(initialize);
      return;
    }

    var x = remotePath;

    initialized = true;
    _client.getChildren(x).then((List<String> c) async {
      if (c == null) return;
      var fullPaths = c.map((it) {
        var s = "${x == "/" ? "" : x}/${it}";
        return s;
      }).toList();

      var values;
      try {
        values = await _client.queryValues(fullPaths);
        if (values == null) values = {};
      } catch (e) {
        values = {};
      }
      var prefix = path.split("/").take(2).join("/");
      for (var p in fullPaths) {
        var value = values[p];
        ProxyNode node = provider.getOrCreateNode("${prefix}${p}");
        if (value != null) {
          node.configs[r"$type"] = "dynamic";
          node.addHistoryAction();
          node.updateValue(value);
        } else if (p.toString().endsWith("_tn")) {
          node.addHistoryAction();
        }
      }
      _refreshing = false;
    }).catchError((e, stack) {
      _refreshing = false;
      logger.warning('Error getting children', e, stack);
    });
  }

  void addHistoryAction() {
    if (!children.containsKey("getHistory")) {
      var n = new GetHistoryNode("${path}/getHistory", provider);
      addChild("getHistory", n);
      (provider as ProxyNodeProvider).nodes[n.path] = n;
      updateList("getHistory");
    }
  }
}
