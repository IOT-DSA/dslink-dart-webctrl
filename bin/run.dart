import "dart:async";

import "package:dslink_webctrl/api.dart";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

Timer timer;

main(List<String> args) async {
  var np = new ProxyNodeProvider();

  link = new LinkProvider(
      args,
      "WebCtrl-",
      provider: np,
      autoInitialize: false
  );

  np.init({
    "Create_Connection": {
      r"$name": "Create Connection",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [
        {
          "name": "name",
          "type": "string",
          "placeholder": "MyConnection"
        },
        {
          "name": "url",
          "type": "string",
          "placeholder": ""
        },
        {
          "name": "username",
          "type": "string"
        },
        {
          "name": "password",
          "type": "string"
        }
      ],
      r"$is": "createConnection"
    }
  }, {
    "deleteParent": (String path) => new DeleteActionNode.forParent(path, np),
    "createConnection": (String path) => new CreateConnectionNode(path),
    "connection": (String path) => new ConnectionNode(path),
    "getValue": (String path) => new SimpleActionNode(path, (params) async {
      var t = new Path(path).parentPath;
      ConnectionNode n = link.provider.getNode(t);
      return {
        "value": await n.client.queryValue(params["name"])
      };
    }, link.provider)..configs.addAll({
      r"$name": "Get Value"
    }),
    "setValue": (String path) => new SimpleActionNode(path, (params) async {
      var value = params["value"];
      var t = new Path(path).parentPath;
      ConnectionNode n = link.provider.getNode(t);

      var success = false;

      var x = path.split("/").skip(2).join("/");

      x = "/${x}";

      if (x == "") {
        x = "/";
      }

      if (!x.startsWith("/")) {
        x = "/${x}";
      }

      if (x.endsWith("/")) {
        x = x.substring(0, x.length - 1);
      }

      try {
        await n.client.setValue(x, value);
        success = true;
      } catch (e) {
      }

      return {
        "success": success
      };
    }, link.provider),
    "refresh": (String path) => new RefreshActionNode(path)
  });

  link.init();
  link.connect();

  startTimer();
}

Duration interval = new Duration(seconds: 1);

void startTimer() {
  timer = new Timer.periodic(interval, (_) {
    for (var x in updateFunctions) {
      x();
    }
  });
}

List<Function> updateFunctions = [];

class ProxyNodeProvider extends SimpleNodeProvider {
  ProxyNodeProvider([Map m, Map profiles]) : super(m, profiles);

  @override
  LocalNode getNode(String path) {
    var connections = nodes.values.where((it) => it is ConnectionNode).toList();
    var c = connections.firstWhere((it) => path.startsWith(it.path), orElse: () => null);

    if (c == null || ["Get_Value", "Set_Value", "getHistory"].any((it) => path.endsWith(it))) {
      return super.getNode(path);
    }

    if (path.indexOf("/") == path.lastIndexOf("/")) {
      return c;
    }

    if (nodes.containsKey(path)) {
      return nodes[path];
    }

    return null;
  }

  @override
  LocalNode getOrCreateNode(String path, [bool addToTree = true, bool init = true]) {
    var node = getNode(path);

    if (node == null) {
      var mp = new Path(path);

      var cp = path.split("/").take(2).join("/");
      if (mp.isRoot || mp.path == "/sys" || mp.path == "/defs" || !nodes.containsKey(cp)) {
        return super.getOrCreateNode(path, addToTree);
      }

      node = new ProxyNode(path, this);
      SimpleNode pnode = getOrCreateNode(mp.parentPath);

      if (pnode != null) {
        pnode.children[mp.name] = node;
        pnode.onChildAdded(mp.name, node);
        pnode.updateList(mp.name);
      }

      if (addToTree) {
        nodes[path] = node;
      }
      node.onCreated();
    }

    return node;
  }
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path, link.provider);

  @override
  onInvoke(Map<String, dynamic> params) {
    try {
      var name = params["name"];
      var url = params["url"];
      var user = params["username"];
      var password = params["password"];
      var root = params["root"];

      if (root == null) root = "/";

      if (!url.contains("_common/webservices")) {
        if (url[url.length - 1] == "/") {
          url = "${url}_common/webservices/";
        } else {
          url = "${url}/_common/webservices/";
        }
      }

      if (!url.endsWith("/")) {
        url = "${url}/";
      }

      link.addNode("/${name}", {
        r"$is": "connection",
        r"$$webctrl_url": url,
        r"$$webctrl_username": user,
        r"$$webctrl_password": password,
        r"$$webctrl_root": root,
        "Get_Value": {
          r"$invokable": "read",
          r"$name": "Get Value",
          r"$params": [
            {
              "name": "name",
              "type": "string"
            }
          ],
          r"$result": "values",
          r"$columns": [
            {
              "name": "value",
              "type": "dynamic"
            }
          ],
          r"$is": "getValue"
        },
        "Delete_Connection": {
          r"$invokable": "write",
          r"$name": "Delete Connection",
          r"$params": [],
          r"$result": "values",
          r"$columns": [],
          r"$is": "deleteParent"
        }
      });
      ConnectionNode n = link.getNode("/${params["name"]}");
      link.save();
      n.onCreated();
      return {};
    } catch (e) {
      print(e);
    }
  }
}

class RefreshActionNode extends SimpleNode {
  RefreshActionNode(String path) : super(path, link.provider);

  @override
  onInvoke(Map<String, dynamic> params) {
    ProxyNode node = link.provider.getNode(new Path(path).parentPath);
    node.refresh();
    return {};
  }
}

class ProxyNode extends SimpleNode {
  ProxyNode(String path, [SimpleNodeProvider p]) : super(path, p == null ? link.provider : p) {
    updateFunction = () {
      if (myConn == null) {
        return;
      }

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

      myConn.client.queryValue(x).then((value) {
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
      link.addNode("${path}/Refresh", {
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

    refresh();
  }

  void addSettableIfNotExists() {
    if (!children.containsKey("Set_Value")) {
      link.addNode("${path}/Set_Value", {
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
      link.removeNode("${path}/Set_Value");
    }
  }

  void refresh() {
    for (var c in children.keys.toList()) {
      link.removeNode("${path}/${c}");
    }
    initialize(this is ConnectionNode ? this : null);
  }

  void onStartListListen() {
    _listing = true;
    initialize();
  }

  bool _listing = false;

  bool initialized = false;

  @override
  RespSubscribeListener subscribe(callback(ValueUpdate), [int cachelevel = 1]) {
    callbacks[callback] = cachelevel;

    if (hasSubscriber) {
      proxySubscribe();
    }

    return new RespSubscribeListener(this, callback);
  }

  @override
  void unsubscribe(callback(ValueUpdate)) {
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

  ConnectionNode myConn;

  void initialize([ConnectionNode conn]) {
    if (path.startsWith("/defs/")) {
      return;
    }

    initialized = true;

    if (conn == null) {
      var p = path.split("/").take(2).join("/");
      conn = link.getNode(p);
    }

    myConn = conn;

    var x = path.split("/").skip(2).join("/");

    x = "/${x}";

    if (x == "") {
      x = "/";
    }

    if (!x.startsWith("/")) {
      x = "/${x}";
    }

    if (x.endsWith("/")) {
      x = x.substring(0, x.length - 1);
    }

    if (x.startsWith("//")) {
      x = x.substring(1);
    }

    if (x == "") {
      x = "/";
    }

    conn.client.getChildren(x).then((c) async {
      var fullPaths = c.map((it) {
        var s = "${x == "/" ? "" : x}/${it}";
        return s;
      }).toList();
      var values;
      try {
        values = await conn.client.queryValues(fullPaths);
      } catch (e) {
        values = {};
      }
      var prefix = path.split("/").take(2).join("/");
      for (var p in fullPaths) {
        var value = values[p];
        ProxyNode node = link.provider.getOrCreateNode("${prefix}${p}");
        if (value != null) {
          node.configs[r"$type"] = "dynamic";
          node.addHistoryAction();

          if (value != null) {
            node.updateValue(value);
          }
        } else if (p.toString().endsWith("_tn")) {
          node.addHistoryAction();
        }
      }
    }).catchError((e, stack) {
      print(e);
    });
  }

  void addHistoryAction() {
    if (!children.containsKey("getHistory")) {
      var n = new GetHistoryNode("${path}/getHistory");
      addChild("getHistory", n);
      (link.provider as ProxyNodeProvider).nodes[n.path] = n;
      updateList("getHistory");
    }
  }
}

class GetHistoryNode extends SimpleNode {
  GetHistoryNode(String path) : super(path, link.provider) {
    configs[r"$is"] = "getHistory";
    configs[r"$name"] = "Get History";
    configs[r"$invokable"] = "read";
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    String range = params["Timerange"];

    if (range == null) {
      range = params["TimeRange"];
    }

    if (range == null) {
      range = params["timeRange"];
    }

    Duration interval = parseIntervalDuration(params["Interval"]);

    DateTime start;
    DateTime end;
    if (range != null) {
      List<String> l = range.split("/");
      start = DateTime.parse(l[0]);
      end = DateTime.parse(l[1]);
    }

    var p = path.split("/").take(2).join("/");
    var x = path.split("/").skip(2).join("/");
    x = x.substring(0, x.length - 11);
    ConnectionNode conn = link[p];

    x = "/${x}";

    if (x == "") {
      x = "/";
    }

    if (!x.startsWith("/")) {
      x = "/${x}";
    }

    if (x.endsWith("/")) {
      x = x.substring(0, x.length - 1);
    }

    if (x.startsWith("//")) {
      x = x.substring(1);
    }

    var rollupName = "last";

    if (params["Rollup"] is String) {
      rollupName = params["Rollup"];
    }

    try {
      var results = await conn.client.getTrendData(x, start: start, end: end);
      var list = [];

      int lastTimestamp = -1;
      int timestamp;

      Rollup rollup = rollups[rollupName]();

      if (rollup == null) {
        rollup = new LastRollup();
      }

      for (List<dynamic> x in results) {
        DateTime time = x[0];
        timestamp = time.millisecondsSinceEpoch;

        rollup.add(x[1]);

        if ((lastTimestamp < 0) && (timestamp < lastTimestamp)) {
          continue;
        }

        if (interval != null && interval.inMilliseconds != 0) {
          var diff = timestamp - lastTimestamp;
          if (diff < interval.inMilliseconds) {
            continue;
          }
          lastTimestamp = timestamp;
          list.add([time, rollup.value]);
          rollup.reset();
        } else {
          list.add([time, rollup.value]);
          rollup.reset();
        }
      }

      return list.map((x) {
        return [
          "${x[0].toIso8601String()}${ValueUpdate.TIME_ZONE}",
          x[1]
        ];
      }).toList();
    } catch (e) {
      return [];
    }
  }
}

class ConnectionNode extends ProxyNode {
  WebCtrlClient client;

  ConnectionNode(String path) : super(path);

  @override
  void load(Map m) {
    super.load(m);
    onCreated();
  }

  @override
  void onStartListListen() {
    _listing = true;
    initialize(this);
  }

  @override
  void onCreated() {
    if (client != null) {
      return;
    }

    super.onCreated();

    client = new WebCtrlClient(
      get(r"$$webctrl_url"),
      get(r"$$webctrl_username"),
      get(r"$$webctrl_password")
    );

    if (!initialized) {
      initialize(this);
    }
  }
}
