import 'dart:async';

import 'package:dslink/dslink.dart';

import 'common.dart';
import '../rollups.dart';
import '../api.dart';
import '../client.dart';

class GetHistoryNode extends SimpleNode {
  static const String _rollUp = 'Rollup';
  static const String _timeRange = 'Timerange';
  static const String _interval = 'Interval';

  GetHistoryNode(String path, SimpleNodeProvider provider)
      : super(path, provider) {
    configs[r"$is"] = "getHistory";
    configs[r"$name"] = "Get History";
    configs[r"$invokable"] = "read";
  }

  Future<WCClient> getClient() {
    var p = parent;
    while (p != null && p is! ConnectionHandle) {
      p = p.parent;
    }

    return (p as ConnectionHandle)?.client;
  }

  @override
  onInvoke(Map<String, dynamic> params) async {
    print('Params: ${params}');

    String range = params[_timeRange];
    range ??= params["TimeRange"];
    range ??= params["timeRange"];

    var iv = params[_interval];
    Duration interval = parseIntervalDuration(iv);

    DateTime start;
    DateTime end;
    var reqNum = 1000;
    if (range != null) {
      List<String> l = range.split("/");
      start = DateTime.parse(l[0]);
      end = DateTime.parse(l[1]);
      var dur = end.difference(start);
      reqNum = dur.inHours + 10;
    }

    var x = parent.path.split("/").skip(2).join("/");

    x = "/${x}";

    if (x.startsWith("//")) {
      x = x.substring(1);
    }

    if (x.length > 1 && x.endsWith("/")) {
      x = x.substring(0, x.length - 1);
    }

    var rollupName = "last";

    if (params[_rollUp] is String) {
      rollupName = params[_rollUp].toString().toLowerCase();
    }

    var rollup = Rollup.rollups[rollupName] == null
        ? new LastRollup()
        : Rollup.rollups[rollupName]();

    var cl = await getClient();
    try {
      var results =
          await cl.getTrendData(x, start: start, end: end, maxRecords: reqNum);
      var list = [];

      results.sort((a, b) {
        DateTime c = a[0];
        DateTime d = b[0];
        return c.compareTo(d);
      });

      if (interval.inMilliseconds <= 0) {
        return results.map((x) {
          return ["${x[0].toIso8601String()}${ValueUpdate.TIME_ZONE}", x[1]];
        }).toList();
      }

      if (iv == '1N') {
        return byMonth(start, end, rollup, results);
      }

      var st = start;
      var cutOff = start.add(interval);
      var remaining = false;
      var i = 0;
      while (st.compareTo(end) != 1) {
        // Iterator is beyond the results, but still not done timerange.
        if (i >= results.length) {
          list.add([cutOff, rollup.value]);
          rollup.reset();

          st = cutOff;
          cutOff = cutOff.add(interval);
          remaining = false;
          continue;
        }

        var cur = results[i];
        // This result is before the start range? (shouldn't happen)
        if (st.compareTo(cur[0]) == 1) {
          i++; // skip this result.
          continue;
        }

        // Date is beyond cut off for interval.
        if (cutOff.compareTo(cur[0]) == -1) {
          list.add([cutOff, rollup.value]);
          rollup.reset();
          remaining = false;

          st = cutOff;
          cutOff = cutOff.add(interval);
          continue;
        }

        rollup.add(cur[1]);
        i++;
        remaining = true;
      }

      if (remaining) {
        list.add([cutOff, rollup.value]);
      }

      print('Returning: $list');
      return list.map((x) {
        return ["${x[0].toIso8601String()}"/*${ValueUpdate.TIME_ZONE}"*/, x[1]];
      }).toList();
    } catch (e) {
      return [];
    }
  }

  List<List> byMonth(DateTime start, DateTime end, Rollup rollup, List<List> results) {
    var st = new DateTime(start.year, start.month, 1);
    DateTime getCutoff() {
      if (st.month == 12) {
        return new DateTime(st.year + 1, 1, 1);
      } else {
        return new DateTime(st.year, st.month + 1, 1);
      }
    }

    var cutOff = getCutoff();
    var dayDur = new Duration(days: 1);
    var list = <List>[];

    var i = 0;
    bool remaining = false;
    while (st.compareTo(end) != 1) {
      // Iterator is beyond the results, but still not done timerange.
      if (i >= results.length) {
        list.add([cutOff.subtract(dayDur) , rollup.value]);
        rollup.reset();

        st = cutOff;
        cutOff = getCutoff();
        remaining = false;
        continue;
      }

      var cur = results[i];
      // This result is before the start range? (shouldn't happen)
      if (cur[0].month < st.month) {
        i++; // skip this result.
        continue;
      }

      // Date is beyond cut off for interval.
      if (cur[0].month >= cutOff.month) {
        list.add([cutOff.subtract(dayDur), rollup.value]);
        rollup.reset();
        remaining = false;

        st = cutOff;
        cutOff = getCutoff();
        continue;
      }

      rollup.add(cur[1]);
      i++;
      remaining = true;
    }

    if (remaining) {
      list.add([cutOff, rollup.value]);
    }

    return list.map((x) {
      return ["${x[0].toIso8601String()}"/*${ValueUpdate.TIME_ZONE}"*/, x[1]];
    }).toList();

  }
}
