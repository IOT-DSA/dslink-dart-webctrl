import "dart:io";
import "dart:convert";
import "package:dslink_webctrl/api.dart";
import 'package:dslink_webctrl/client.dart';

main() async {
  var file = new File("test/config.json");
  var config = JSON.decode(await file.readAsString());
  var uri = Uri.parse(config['url']);
  var client = new WCClient(uri, config["username"], config["password"]);

  print(await client.getTrendData("/trees/geographic/#discovery_es/#power_meters_167/#pv_power_meter_167/demand_tn"));
}
