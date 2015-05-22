import "dart:async";

import "package:dslink_webctrl/api.dart";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

Timer timer;

main(List<String> args) async {
  var np = new ProxyNodeProvider();
  np.init({
    "Create_Connection": {
      r"$name": "Create Connection",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [
        {
          "name": "name",
          "type": "string"
        },
        {
          "name": "url",
          "type": "string"
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
    })..configs.addAll({
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
    }),
    "refresh": (String path) => new RefreshActionNode(path)
  });

  link = new LinkProvider(
    args,
    "WebCtrl-",
    nodeProvider: np,
    provider: np
  );

  link.connect();

  startTimer();
}

Duration interval = new Duration(seconds: 3);

void startTimer() {
  timer = new Timer.periodic(interval, (_) {
    for (var x in updateFunctions) {
      x();
    }
  });
}

List<Function> updateFunctions = [];

class ProxyNodeProvider extends SimpleNodeProvider {
  ProxyNodeProvider([Map m, Map profiles]) {
    init(m, profiles);
  }

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
      return super.getNode(path);
    }

    var mp = new Path(path);
    ProxyNode node = new ProxyNode(path);
    ProxyNode pnode = link[mp.parentPath];
    pnode.children[mp.name] = node;
    pnode.updateList(mp.name);
    nodes[path] = node;
    node.onCreated();
    return node;
  }
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
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
  }
}

class RefreshActionNode extends SimpleNode {
  RefreshActionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    ProxyNode node = link.provider.getNode(new Path(path).parentPath);
    node.refresh();
    return {};
  }
}

class ProxyNode extends SimpleNode {
  ProxyNode(String path) : super(path) {
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
        print(e);
        print(stack);
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
  }

  void addSettableIfNotExists() {
    if (!children.containsKey("Set_Value")) {
      link.addNode("${path}/Set_Value", {
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
      removeChild("Set_Value");
    }
  }

  void refresh() {
    for (var c in children.keys) {
      removeChild(c);
    }
    initialize(this is ConnectionNode ? this : null);
  }

  @override
  bool get listReady {
    if (!initialized) {
      initialize();
      return false;
    }
    return true;
  }

  bool initialized = false;

  int subscriberCount = 0;

  @override
  RespSubscribeListener subscribe(callback(ValueUpdate), [int cachelevel = 1]) {
    callbacks[callback] = cachelevel;
    subscriberCount++;

    if (subscriberCount == 1) {
      proxySubscribe();
    }

    return new RespSubscribeListener(this, callback);
  }

  @override
  void unsubscribe(callback(ValueUpdate)) {
    super.unsubscribe(callback);
    subscriberCount--;
    if (subscriberCount == 0) {
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
    initialized = true;

    if (conn == null) {
      var p = path.split("/").take(2).join("/");
      conn = link[p];
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
        ProxyNode node = link["${prefix}${p}"];
        if (value != null) {
          node.configs[r"$type"] = "dynamic";
          node.addHistoryAction();
          node.updateValue(value);
        }
      }
    }).catchError((e, stack) {
      print(e);
      print(stack);
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
  GetHistoryNode(String path) : super(path) {
    configs[r"$is"] = "getHistory";
    configs[r"$name"] = "Get History";
    configs[r"$invokable"] = "read";
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    String range = params["Timerange"];
    Duration interval = parseInterval(params["Interval"]);

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

    try {
      var results = await conn.client.getTrendData(x, start: start, end: end);
      var list = [];

      int lastTimestamp = -1;
      int timestamp;

      for (List<dynamic> x in results) {
        DateTime time = x[0];
        timestamp = time.millisecondsSinceEpoch;

        if ((lastTimestamp < 0) && (timestamp < lastTimestamp)) {
          continue;
        }

        if (interval != null && interval.inMilliseconds != 0) {
          var diff = timestamp - lastTimestamp;
          if (diff < interval.inMilliseconds) {
            continue;
          }
          lastTimestamp = timestamp;
          list.add(x);
        } else {
          list.add(x);
        }
      }

      return list.map((it) => {
        "Ts": "${it[0].toIso8601String()}${ValueUpdate.TIME_ZONE}",
        "Value": it[1]
      }).toList();
    } catch (e) {
      return [];
    }
  }
}

class ConnectionNode extends ProxyNode {
  WebCtrlClient client;

  @override
  bool get listReady {
    if (!initialized) {
      initialize(this);
      return false;
    }
    return true;
  }

  ConnectionNode(String path) : super(path);

  @override
  void load(Map m, NodeProviderImpl provider) {
    super.load(m, provider);
    onCreated();
  }

  @override
  void onCreated() {
    super.onCreated();

    client = new WebCtrlClient(get(r"$$webctrl_url"), get(r"$$webctrl_username"), get(r"$$webctrl_password"));
    if (!initialized) {
      for (var c in children.keys) {
        removeChild(c);
      }
      initialize(this);
    }
  }
}
