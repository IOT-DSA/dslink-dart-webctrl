import "dart:async";

import "package:dslink_webctrl/api.dart";

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";

LinkProvider link;

Timer timer;

main(List<String> args) async {
  link = new LinkProvider(
    args,
    "WebCtrl-",
    defaultNodes: {
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
    },
    profiles: {
      "createConnection": (String path) => new CreateConnectionNode(path),
      "connection": (String path) => new ConnectionNode(path),
      "getValue": (String path) => new SimpleActionNode(path, (params) async {
        var t = new Path(path).parentPath;
        ConnectionNode n = link.provider.getNode(t);
        return {
          "value": await n.client.queryValue(params["name"])
        };
      })
    }
  );

  link.connect();
}

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path) : super(path);

  @override
  onInvoke(Map<String, dynamic> params) {
    var name = params["name"];
    var url = params["url"];
    var user = params["username"];
    var password = params["password"];
    link.addNode("/${name}", {
      r"$is": "connection",
      r"$$webctrl_url": url,
      r"$$webctrl_username": user,
      r"$$webctrl_password": password,
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
    link.save();
    return {};
  }
}

class ConnectionNode extends SimpleNode {
  WebCtrlClient client;

  ConnectionNode(String path) : super(path);

  @override
  void onCreated() {
    client = new WebCtrlClient(get(r"$$webctrl_url"), get(r"$$webctrl_username"), get(r"$$webctrl_password"));
  }
}
