String _envelope(String body) => '''
<soapenv:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:soap="http://soap.core.green.controlj.com">
  <soapenv:Header/>
  <soapenv:Body>
    $body
  </soapenv:Body>
</soapenv:Envelope>
''';

abstract class Action {
  static const GetChildren = 'GetChildren';
  static const GetValues = 'GetValues';
  static const SetValue = 'SetValue';
  static const GetTrendData = 'GetTrendData';
}

String getChildren(String path) {
  final body =
'''
  <soap:getChildren soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <expression xsi:type="xsd:string">$path</expression>
  </soap:getChildren>
''';

  return _envelope(body);
}

String getValues(Iterable<String> paths) {
  var pList = '';
  for (var p in paths) {
    pList += '<expression xsi:type="xsd:string" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">$p</expression>\n';
  }

  final body =
'''
<soap:getValues soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <expression soapenv:arrayType="xsd:string[]" xsi:type="soapenc:Array">
    $pList
  </expression>
</soap:getValues>
''';

  return _envelope(body);
}

String setValue(String path, String value) {
  final body =
'''
  <soap:setValue soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <expression xsi:type="xsd:string">$path</expression>
    <newValue xsi:type="xsd:string">$value</newValue>
    <changeReason xsi:type="xsd:string">dglux</changeReason>
  </soap:setValue>
''';

  return _envelope(body);
}

String getTrendData(String path, String start, String end, bool limit, int max) {
  final body =
'''
  <soap:getTrendData soapenv:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <trendLogPath xsi:type="xsd:string">$path</trendLogPath>
    <sTime xsi:type="xsd:string">$start</sTime>
    <eTime xsi:type="xsd:string">$end</eTime>
    <limitFromStart xsi:type="xsd:boolean">$limit</limitFromStart>
    <maxRecords xsi:type="xsd:int">$max</maxRecords>
  </soap:getTrendData>
''';

  return _envelope(body);
}

String _formatDate(DateTime date) {
  if (date == null) return '';

  var m = date.month.toString().padLeft(2, '0');
  var d = date.day.toString().padLeft(2, '0');
  var y = date.year;
  var a = 'AM';

  var h = date.hour;
  if (h == 0) {
    h = 12;
  } else if (h > 12) {
    h -= 12;
    a = 'PM';
  }
  var mm = date.minute.toString().padLeft(2, '0');
  var ss = date.second.toString().padLeft(2, '0');
  return '$m/$d/$y $h:$mm:$ss $a';
}
