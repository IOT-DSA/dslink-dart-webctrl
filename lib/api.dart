library webctrl.api;

import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;
import "package:xml/xml.dart" hide parse;
import "package:xml/xml.dart" as xml;
import "package:crypto/crypto.dart" show CryptoUtils;

class WebCtrlClient {
  final String url;
  final String auth;
  final http.Client client = new http.Client();

  WebCtrlClient(this.url, String username, String password) :
    auth = _createBasicAuthorization(username, password);

  Future<XmlDocument> request(String action, xmlData) async {
    if (xmlData is XmlNode) {
      xmlData = (xmlData as XmlNode).toXmlString();
    }

    print("REQ");
    var response = await client.post("${url}/${action}", headers: {
      "Authorization": "Basic ${auth}",
      "SOAPAction": "",
      "Content-Type": "text/xml; charset=utf-8"
    }, body: xmlData);

    if (response.statusCode != 200) {
      throw new Exception("Got Status Code: ${response.statusCode}:\nRequest Body: ${xmlData}\nResponse Body: ${response.body}");
    }

    return xml.parse(response.body);
  }

  Future<xml.XmlDocument> queryValuesXml(List<String> paths) async {
    var x = """
<soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap="http://soap.core.green.controlj.com">
  <soapenv:Header/>
  <soapenv:Body>
    <soap:getValues soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <expression soapenv:arrayType="xsd:string[]" xsi:type="soapenc:Array">
      {{DATA}}
      </expression>
    </soap:getValues>
  </soapenv:Body>
</soapenv:Envelope>
    """;

    x = x.replaceAll("{{DATA}}", paths.map((it) =>
      '<expression xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">${it}</expression>').join());
    return await request("Eval", x);
  }

  Future<List<List<dynamic>>> getTrendData(String path, {DateTime start, DateTime end, int maxRecords: 1000, bool limitFromStart: false}) async {
    var x = """
    <soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap="http://soap.core.green.controlj.com">
  <soapenv:Header/>
  <soapenv:Body>
    <soap:getTrendData soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <trendLogPath xsi:type="xsd:string">${path}</trendLogPath>
      <sTime xsi:type="xsd:string">${formatWebCtrlDate(start)}</sTime>
      <eTime xsi:type="xsd:string">${formatWebCtrlDate(end)}</eTime>
      <limitFromStart xsi:type="xsd:boolean">${limitFromStart}</limitFromStart>
      <maxRecords xsi:type="xsd:int">${maxRecords}</maxRecords>
    </soap:getTrendData>
  </soapenv:Body>
</soapenv:Envelope>
    """;

    XmlDocument response;

    try {
      response = await request("Trend", x);
      XmlElement e = response.findAllElements("getTrendDataReturn").first;
      var list = [];
      for (var i = 0; i < e.children.length; i += 2) {
        var lts = e.children[i].text;
        var lv = e.children[i + 1].text;
        list.add([parseWebCtrlDate(lts), resolveStringValue(lv)]);
      }
      return list;
    } catch (e) {
      if (e.toString().contains("Trends are not enabled")) {
        throw new Exception("Trends are not enabled for this node.");
      } else if (e.toString().contains("valid trend location")) {
        throw new Exception("This node is not a valid trend location.");
      }
      rethrow;
    }
  }

  Future<dynamic> queryValue(String path) async =>
    (await queryValues([path]))[path];

  Future<Map<String, dynamic>> queryValues(List<String> paths) async {
    XmlDocument doc = await queryValuesXml(paths);
    XmlElement e = doc.findAllElements("getValuesReturn").first;
    var i = 0;
    var map = {};
    for (XmlElement child in e.children.where((it) => it is XmlElement)) {
      var isNullAttr = child.attributes.firstWhere((it) => it.name.local == "nil", orElse: () => null);
      var isNull = false;
      if (isNullAttr != null && isNullAttr.value == "true") {
        isNull = true;
      }
      dynamic val;
      if (isNull) {
        val = null;
      } else {
        val = resolveStringValue(child.text);
      }
      map[paths[i]] = val;
      i++;
    }
    return map;
  }

  Future<xml.XmlDocument> getChildrenXml(String path) async {
    var x = """
<soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap="http://soap.core.green.controlj.com">
  <soapenv:Header/>
  <soapenv:Body>
    <soap:getChildren soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <expression xsi:type="xsd:string">${path}</expression>
    </soap:getChildren>
  </soapenv:Body>
</soapenv:Envelope>
    """;

    return await request("Eval", x);
  }

  Future<List<String>> getChildren(String path) async {
    XmlDocument doc = await getChildrenXml(path);
    XmlElement e = doc.findAllElements("getChildrenReturn").first;

    return e.children.where((it) => it is XmlElement).map((it) => it.text).toList();
  }

  Future setValue(String path, dynamic value) async {
    var v = toStringValue(value);
    if (v != null) {
      v = escapeXml(v);
    }

    var x = """
<soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap="http://soap.core.green.controlj.com">
  <soapenv:Header/>
  <soapenv:Body>
    <soap:setValue soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <expression xsi:type="xsd:string">${path}</expression>
      <newValue xsi:type="xsd:string">${v}</newValue>
      <changeReason xsi:type="xsd:string">dglux</changeReason>
    </soap:setValue>
  </soapenv:Body>
</soapenv:Envelope>
    """;

    return await request("Eval", x);
  }

  Future<List<String>> getChildrenRecursive(String path) async {
    var list = [];
    var c = await getChildren(path);
    list.addAll(c);
    for (var x in c) {
      list.addAll(await getChildrenRecursive("${path == "/" ? "" : path}/${x}"));
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> getNodeData(String parentPath) async {
    var list = [];
    var childrenNames = await getChildren(parentPath);
    for (var c in childrenNames) {
      list.add({
        "name": c,
        "path": "${parentPath == "/" ? "" : parentPath}/${c}"
      });
    }
    return list;
  }
}

String toStringValue(input) {
  if (input == null) return null;

  if (input is Map || input is List) {
    return JSON.encode(input);
  } else if (input is String) {
    return input;
  } else if (input is bool || input is num) {
    return input.toString();
  } else {
    throw new Exception("Invalid Input");
  }
}

dynamic resolveStringValue(String input) {
  if (input.startsWith("[ERROR]: Device is temporarily disabled.")) {
    return null;
  }

  var n = num.parse(input, (x) => null);
  if (n != null) {
    return n;
  }

  var lt = input.toLowerCase().trim();

  if (lt == "true" || lt == "false") {
    return lt == "true";
  }

  return input;
}

String escapeXml(String input) {
  return input
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("&", "&amp;");
}

String _gtn(int x) => x >= 10 ? x.toString() : "0${x}";
int _realHour(int x) => ((x + 11) % 12 + 1);

String formatWebCtrlDate(DateTime time) {
  if (time == null) return "";
  return "${_gtn(time.month)}/${_gtn(time.day)}/${_gtn(time.year)} ${_realHour(time.hour)}:${_gtn(time.minute)}:${_gtn(time.second)} ${time.hour >= 12 ? "PM" : "AM"}";
}

DateTime parseWebCtrlDate(String input) {
  var parts = input.split(":").join(" ").split("/").join(" ").split(" ");
  if (parts.length != 7) {
    throw new FormatException("Invalid Input");
  }
  var month = int.parse(parts[0]);
  var day = int.parse(parts[1]);
  var year = int.parse(parts[2]);
  var hour = int.parse(parts[3]);
  var minute = int.parse(parts[4]);
  var second = int.parse(parts[5]);
  var suffix = parts[6];

  return new DateTime(
    year,
    month,
    day,
    suffix == "PM" ? (hour + 12) : hour,
    minute,
    second
  );
}

String _createBasicAuthorization(String username, String password) {
  return CryptoUtils.bytesToBase64(UTF8.encode("${username}:${password}"));
}

final Map<dynamic, int> TYPES = {
  ["ms", "millis", "millisecond", "milliseconds"]: 1,
  ["s", "second", "seconds"]: 1000,
  ["m", "min", "minute", "minutes"]: 60000,
  ["h", "hr", "hour", "hours"]: 3600000,
  ["d", "day", "days"]: 86400000,
  ["w", "wk", "week", "weeks"]: 604800000,
  ["month", "months"]: 2628000000,
  ["y", "year", "years"]: 31536000000
};

final List<String> ALL_TYPES = TYPES.keys.expand((key) => key).toList()..sort();
final RegExp INTERVAL_REGEX = new RegExp("^(\\d*?.?\\d*?)(${ALL_TYPES.join('|')})\$");

Duration parseIntervalDuration(String input) =>
  new Duration(milliseconds: parseInterval(input));

int parseInterval(String input) {
  /// Sanitize Input
  input = input.trim().toLowerCase().replaceAll(" ", "");

  if (input == "default" || input == "none") {
    return 0;
  }

  if (!INTERVAL_REGEX.hasMatch(input)) {
    throw new FormatException("Bad Interval Syntax: ${input}");
  }

  var match = INTERVAL_REGEX.firstMatch(input);
  var multiplier = num.parse(match[1]);
  var typeName = match[2];
  var typeKey = TYPES.keys.firstWhere((x) => x.contains(typeName));
  var type = TYPES[typeKey];
  return (multiplier * type).round();
}

main() {
  print(parseInterval("1ms"));
  print(parseInterval("10ms"));
  print(parseInterval("15m"));
  print(parseInterval("1d"));
  print(parseInterval("2d"));
  print(parseInterval("2.5d"));
  print(parseInterval("2 days"));
  print(parseInterval("1 millisecond"));
}
