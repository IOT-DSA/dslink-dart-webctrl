import "dart:async";

import 'package:dslink_webctrl/nodes.dart';

import "package:dslink/dslink.dart";
import "package:dslink/nodes.dart";


Timer timer;

int helped = 0;

main(List<String> args) async {
  LinkProvider link;
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
    "createConnection": (String path) => new CreateConnectionNode(path, link),
    "connection": (String path) => new ConnectionNode(path, np),
    "getValue": (String path) => new SimpleActionNode(path, (params) async {
      var t = new Path(path).parentPath;
      ConnectionNode n = link.provider.getNode(t);
      var cl = await n.client;

      return {
        "value": await cl.queryValue(params["name"])
      };
    }, link.provider)..configs.addAll({
      r"$name": "Get Value"
    }),
    "setValue": (String path) => new SimpleActionNode(path, (params) async {
      var value = params["value"];
      var t = new Path(path).parentPath;
      ConnectionNode n = link.provider.getNode(t);
      var cl = await n.client;

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
        await cl.setValue(x, value);
        success = true;
      } catch (e) {
      }

      return {
        "success": success
      };
    }, link.provider),
    "refresh": (String path) => new RefreshActionNode(path, np)
  });

  link.init();
  link.connect();

  ProxyNode.startTimer();
}
