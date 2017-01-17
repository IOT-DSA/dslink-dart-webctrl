library webctrl.api;

import "dart:convert";

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

  return [
    _gtn(time.month),
    "/",
    _gtn(time.day),
    "/",
    _gtn(time.year),
    " ",
    _realHour(time.hour),
    ":",
    _gtn(time.minute),
    ":",
    _gtn(time.second),
    " ",
    time.hour >= 12 ? "PM" : "AM"
  ].join();
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
  var suffix = parts[6].toString().trim().toUpperCase();

  if (suffix == "PM" && hour < 12) {
    hour += 12;
  }

  var time = new DateTime(year, month, day, hour, minute, second);

  return time;
}

final Map<dynamic, int> TYPES = {
  ["ms", "millis", "millisecond", "milliseconds"]: 1,
  ["s", "second", "seconds"]: 1000,
  ["m", "min", "minute", "minutes"]: 60000,
  ["h", "hr", "hour", "hours"]: 3600000,
  ["d", "day", "days"]: 86400000,
  ["w", "wk", "week", "weeks"]: 604800000,
  ["n", "month", "months"]: 2628000000,
  ["y", "year", "years"]: 31536000000
};

final List<String> ALL_TYPES = TYPES.keys.expand((key) => key).toList()..sort();
final RegExp INTERVAL_REGEX =
    new RegExp("^(\\d*?.?\\d*?)(${ALL_TYPES.join('|')})\$");

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
