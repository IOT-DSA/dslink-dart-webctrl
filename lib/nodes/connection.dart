import 'dart:async';

import 'package:dslink/dslink.dart';

import 'common.dart';
import 'proxy.dart';
import '../client.dart';

class CreateConnectionNode extends SimpleNode {
  CreateConnectionNode(String path, this.link)
      : super(path, link.provider);

  final LinkProvider link;

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

      provider.addNode("/${name}", {
        r"$is": "connection",
        r"$$webctrl_url": url,
        r"$$webctrl_username": user,
        r"$$webctrl_password": password,
        r"$$webctrl_root": root,
        "Get_Value": {
          r"$invokable": "read",
          r"$name": "Get Value",
          r"$params": [
            {"name": "name", "type": "string"}
          ],
          r"$result": "values",
          r"$columns": [
            {"name": "value", "type": "dynamic"}
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
      ConnectionNode n = provider.getNode("/${params["name"]}");
      link.save();
      n.onCreated();
      return {};
    } catch (e) {
      print(e);
    }
  }
}

class ConnectionNode extends ProxyNode implements ConnectionHandle {
  WCClient _client;
  Completer<WCClient> _comp;
  Future<WCClient> get client async {
    if (_client != null) return _client;
    return _comp.future;
  }

  ConnectionNode(String path, NodeProvider provider) : super(path, provider) {
    _comp = new Completer<WCClient>();
  }

  @override
  void load(Map m) {
    super.load(m);
    onCreated();
  }

  @override
  void onStartListListen() {
    if (initialized) return;
    initialize(_client);
  }

  @override
  void onCreated() {
    if (_client != null) {
      return;
    }

    super.onCreated();

    var uri = Uri.parse(get(r"$$webctrl_url"));

    _client = new WCClient(
        uri, get(r"$$webctrl_username"), get(r"$$webctrl_password"));
    _comp.complete(_client);

    if (!initialized) {
      initialize(_client);
    }
  }
}
