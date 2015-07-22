import "dart:io";
import "dart:convert";
import "package:dslink_webctrl/api.dart";

main() async {
  var file = new File("test/config.json");
  var config = JSON.decode(await file.readAsString());
  var client = new WebCtrlClient(config["url"], config["username"], config["password"]);

  print(await client.getChildren("/"));
}
