import 'dart:math' as Math;

typedef Rollup RollupFactory();

abstract class Rollup {
  /// Value of the rollup based on current state.
  dynamic get value;
  /// Add a value to the rollup.
  void add(dynamic input);
  /// Reset rollup to default/empty state.
  void reset();

  static const none = 'none';
  static const delta = 'delta';
  static const first = 'first';
  static const last = 'last';
  static const max = 'max';
  static const min = 'min';
  static const count = 'count';
  static const sum = 'sum';
  static const avg = 'avg';

  static final Map<String, RollupFactory> rollups = {
    none: () => null,
    delta: () => new FirstRollup(),
    first: () => new FirstRollup(),
    last: () => new LastRollup(),
    max: () => new MaxRollup(),
    min: () => new MinRollup(),
    count: () => new CountRollup(),
    sum: () => new SumRollup(),
    avg: () => new AvgRollup()
  };

}

/// FirstRollup will store only the first value provided. Any others will be
/// ignored until the rollup is reset.
class FirstRollup implements Rollup {
  dynamic value;

  bool _set = false;

  void add(input) {
    if (_set) return;

    value = input;
    _set = true;
  }

  void reset() {
    _set = false;
  }
}

/// LastRollup will store the last value, overwriting any previously stored
/// values.
class LastRollup implements Rollup {
  dynamic value;

  void add(input) {
    value = input;
  }

  void reset() {}
}

/// Average Rollup will try to parse the values as numbers if they are not
/// already numbers. It will then provide an average of the currently added
/// values until the rollup is reset.
class AvgRollup implements Rollup {
  num _total = 0.0;
  int _count = 0;

  num get value => _count == 0 ? 0 : _total / _count;

  void add(input) {
    if (input is String) {
      input = num.parse(input, (e) => input.length);
    }

    if (input is! num) {
      return;
    }

    _total += input;
    _count++;
  }

  void reset() {
    _total = 0.0;
    _count = 0;
  }
}

/// SumRollup sums the values added into a total number.
class SumRollup implements Rollup {
  num value = 0.0;

  void add(input) {
    if (input is String) {
      input = num.parse(input, (e) => input.length);
    }

    if (input is! num) {
      return;
    }

    value += input;
  }

  void reset() {
    value = 0.0;
  }
}

/// Count rollup tracks only the number of values added to the roll up but
/// does not store the values at all.
class CountRollup implements Rollup {
  int value = 0;
  void add(input) {
    value++;
  }

  void reset() {
    value = 0;
  }
}

/// MaxRollup will track the inputs and return the largest value added.
class MaxRollup implements Rollup {
  num value;
  void add(input) {
    if (input is String) {
      input = num.parse(input, (e) => null);
    }

    if (input is! num) {
      return;
    }

    if (value == null) {
      value = input;
    } else {
      value = Math.max(value, input);
    }
  }

  void reset() {
    value = null;
  }

}

/// MinRollup will track inputs and return the smallest value added.
class MinRollup implements Rollup {
  num value;
  void add(input) {
    if (input is String) {
      input = num.parse(input, (e) => null);
    }

    if (input is! num) {
      return;
    }

    if (value == null) {
      value = input;
    } else {
      Math.min(value, input);
    }
  }

  void reset() {
    value = null;
  }
}
