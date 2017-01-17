import "dart:async";
import "dart:io";
import "dart:convert";
import 'dart:collection' show Queue;
import "dart:math" as Math;

import "package:http/http.dart" as http;
import "package:xml/xml.dart" as xml;
import "package:dslink/utils.dart" show logger;
import 'package:intl/intl.dart' show DateFormat;

import 'soap_envelopes.dart' as se;

class WCClient {
  http.Client _client;
  Uri _root;
  String user;
  String pass;
  DateFormat df;
  Queue<ValueRequest> _queue;
  bool _pending = false;

  static const Map<String, String> _headers = const <String, String>{
    'Content-Type': 'text/xml; charset=utf-8',
  };

  WCClient(this._root, this.user, this.pass) {
    _queue = new Queue<ValueRequest>();
    var tmp = new HttpClient();
//    var cred = new HttpClientBasicCredentials(user, pass);
//    tmp.authenticate = (Uri uri, String scheme, String realm) {
//      tmp.addCredentials(uri, realm, cred);
//      return true;
//    };
    tmp.badCertificateCallback = (a, b, c) => true;
    tmp.maxConnectionsPerHost = 100;
    _root = _root.replace(userInfo: '$user:$pass');
    _client = new http.IOClient(tmp);

    df = new DateFormat.yMd().add_jms();
  }

  /// getChildren returns a list of children nodes of the specified path.
  Future<List<String>> getChildren(String path, {bool retry = false}) async {
    xml.XmlDocument doc;
    String resp;
    try {
      resp = await _sendRequest(
          'Eval', se.Action.GetChildren, se.getChildren(path));
      if (resp == null) {
        logger.warning('GetChildren for path: "$path" failed');
        if (!retry) {
          logger.info('Retrying GetChildren for $path');
          return getChildren(path, retry: true);
        }
        return null;
      }
      doc = xml.parse(resp);
    } catch (e) {
      logger.warning('Unable to parse result: $resp', e);
      return null;
    }

    xml.XmlElement chdn = doc.findAllElements('getChildrenReturn')?.first;
    if (chdn == null) return null;
    return chdn.children
        .where((nd) => nd is xml.XmlElement)
        .map((xml.XmlElement el) => el.text)
        .toList();
  }

  /// queryValues returns values associated with the path(s) specified.
  Future<Map<String, dynamic>> queryValues(Iterable<String> paths,
      {bool retry = false}) async {
    var allPaths = paths.toList(growable: false);
    xml.XmlDocument doc;
    String resp;
    try {
      resp = await _sendRequest(
          'Eval', se.Action.GetValues, se.getValues(allPaths));
      if (resp == null) {
        logger.warning('QueryValues for paths failed');
        if (!retry) {
          logger.info('Retrying QueryValues $allPaths');
          return queryValues(allPaths, retry: true);
        }
        return null;
      }
      doc = xml.parse(resp);
    } catch (e) {
      logger.warning('Unable to parse results: $resp', e);
      return null;
    }

    xml.XmlElement chdn = doc.findAllElements('getValuesReturn')?.first;
    if (chdn == null) return null;
    var allVals = chdn.findElements('getValuesReturn');
    var i = 0;
    Map mp = {};
    for (var val in allVals) {
      var isNull = val.getAttribute('xsi:nil') == 'true';
      if (!isNull) {
        mp[allPaths[i]] = _resolveValue(val.text);
      } else {
        mp[allPaths[i]] = null;
      }
      i++;
    }

    return mp;
  }

  /// Query the value of an individual path, returns only the value.
  Future<dynamic> queryValue(String path) async {
    var req = new ValueRequest(path);
    _queue.add(req);
    _sendValReq();
    return req.value;
  }

  _sendValReq() async {
    if (_pending || _queue.isEmpty) return;

    _pending = true;
    var paths = <ValueRequest>[];
    var i = 0;

    while (_queue.isNotEmpty && i < 20) {
      paths.add(_queue.removeFirst());
    }

    var res = await queryValues(paths.map((vr) => vr.path));
    for (var vr in paths) {
      if (res == null) {
        vr._comp.complete(null);
      } else {
        vr._comp.complete(res[vr.path]);
      }
    }
    _pending = false;
    _sendValReq();
  }

  /// Set the path to a specific value.
  Future setValue(String path, dynamic value) async {
    var val = _toStringValue(value);
    if (val != null) {
      val = _escapeXml(val);
    }

    try {
      await _sendRequest('Eval', se.Action.SetValue, se.setValue(path, val));
    } catch (e) {
      logger.warning('Error setting value "$val" at $path', e);
    }
  }

  Future<List<List<dynamic>>> getTrendData(String path,
      {DateTime start,
      DateTime end,
      int maxRecords: 1000,
      bool limitFromStart: false}) async {

    xml.XmlDocument doc;
    String resp;
    try {
      var sdf = start == null ? null : df.format(start);
      var edf = end == null ? null : df.format(end);
      resp = await _sendRequest('Trend', se.Action.GetTrendData,
          se.getTrendData(path, sdf, edf, limitFromStart, maxRecords));
      if (resp == null) {
        logger.warning('getTrendData for $path failed');
        return null;
      }
      doc = xml.parse(resp);
    } catch (e) {
      logger.warning('Error getting trend data for $path', e);
      return null;
    }

    var data = doc.findAllElements('getTrendDataReturn')?.first;
    if (data == null) {
      logger.warning('TrendData was empty?');
      return null;
    }

    var list = [];
    for (var i = 0; i < data.children.length; i += 2) {
      DateTime date;
      try {
        date = df.parse(data.children[i].text);
      } catch (e) {
        logger.warning('Invalid return date: ${data.children[i].text}', e);
        continue;
      }

      if (start != null && date.isBefore(start)) continue;
      if (end != null && date.isAfter(end)) continue;

      var value = _resolveValue(data.children[i + 1].text);

      list.add([date, value]);
    }

    return list;

  }

  /// Close the client.
  void close() => _client.close();

  Future<String> _sendRequest(String adr, String action, String body) async {
    var headers = {}..addAll(_headers);
    headers['SOAPAction'] = ''; //= action;

    var uri =
        _root.replace(pathSegments: _root.pathSegments.toList()..add(adr));
    String respBody;
    try {
      var resp = await _client.post(uri, headers: headers, body: body);
          //.timeout(new Duration(seconds: 60));
      if (resp.statusCode != HttpStatus.OK) {
        logger.warning('Request failed. Status: ${resp.statusCode}.\n'
            'Request: ${body}\nResponse: ${resp.body}');
        return null;
      }

      respBody = resp.body;
    } catch (e) {
      logger.warning('Failed to send request to "$adr"', e);
      return null;
    }

    return respBody;
  }

  String _toStringValue(dynamic input) {
    if (input == null) return null;

    if (input is Map || input is List) {
      return JSON.encode(input);
    } else if (input is String) {
      return input;
    } else if (input is bool || input is num) {
      return '$input';
    }
    throw new ArgumentError.value(input, 'input', 'Invalid arguement type');
  }

  dynamic _resolveValue(String input) {
    if (input.startsWith("[ERROR]: Device is temporarily disabled")) {
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

  String _escapeXml(String input) => input
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&apos;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("&", "&amp;");
}

class ValueRequest {
  final String path;
  Completer<dynamic> _comp;
  Future get value => _comp.future;

  ValueRequest(this.path) {
    _comp = new Completer();
  }
}
