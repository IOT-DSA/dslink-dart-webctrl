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
        },
        {
          "name": "root",
          "type": "string",
          "default": "/"
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

  timer = new Timer.periodic(new Duration(seconds: 5), (_) {
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

    if (c == null || path.replaceAll(c.path + "/", "") == "Get_Value") {
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

class ProxyNode extends LocalNodeImpl {
  ProxyNode(String path) : super(path) {
    updateFunction = () {
      if (myConn == null) {
        return;
      }

      var x = path.split("/").skip(2).join("/");

      x = "${myConn.rootPrefix}/${x}";

      if (x == "") {
        x = "/";
      }

      if (!x.startsWith("/")) {
        x = "/${x}";
      }

      if (x.endsWith("/")) {
        x = x.substring(0, x.length - 1);
      }

      myConn.client.queryValue(x).then((value) {
        if (value != null) {
          updateValue(value);
        }
      }).catchError((e, stack) {
        print(e);
        print(stack);
      });
    };

/*    link.addNode("${path}/Refresh", {
      r"$is": "refresh",
      r"$invokable": "write",
      r"$result": "values",
      r"$params": [],
      r"$columns": []
    });*/
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

    x = "${conn.rootPrefix}/${x}";

    if (x == "") {
      x = "/";
    }

    if (!x.startsWith("/")) {
      x = "/${x}";
    }

    if (x.endsWith("/")) {
      x = x.substring(0, x.length - 1);
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
        var node = link["${prefix}${p}"];
        if (value != null) {
          node.configs[r"$type"] = "dynamic";
          node.updateValue(value);
        }
      }
    }).catchError((e, stack) {
      print(e);
      print(stack);
    });
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

  void onCreated() {
    client = new WebCtrlClient(get(r"$$webctrl_url"), get(r"$$webctrl_username"), get(r"$$webctrl_password"));
    if (!initialized) {
      for (var c in children.keys) {
        removeChild(c);
      }
      initialize(this);
    }
  }

  void onLoadChild(x, y, z) {}

  String get rootPrefix => get(r"$$webctrl_root");
}
