import 'package:dslink/dslink.dart';

import 'common.dart';
import 'proxy.dart';

class ProxyNodeProvider extends SimpleNodeProvider {
  ProxyNodeProvider([Map m, Map profiles]) : super(m, profiles);

  @override
  LocalNode getNode(String path) {
    var connections = nodes.values.where((it) => it is ConnectionHandle).toList();
    var c = connections.firstWhere((it) => path.startsWith(it.path), orElse: () => null);

    if (c == null || path.endsWith('Get_Value') || path.endsWith('Set_value')) {
      return super.getNode(path);
    } else if (path.endsWith('getHistory')) {
      var nd = super.getNode(path);
      if (nd != null) return nd;

      var p = new Path(path);
      var pNd = getOrCreateNode(p.parentPath) as ProxyNode;
      pNd.addHistoryAction();
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
