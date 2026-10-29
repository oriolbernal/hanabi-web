import 'dart:math';

/// A small tanh network exported from PyTorch by `rl/export.py`:
/// `{"layers": [{"w": [[...]], "b": [...]}, ...]}`.
class Mlp {
  Mlp(Map<String, dynamic> weights)
    : _layers = [
        for (final l in weights['layers'] as List)
          (
            [
              for (final row in l['w'] as List)
                [for (final v in row as List) (v as num).toDouble()],
            ],
            [for (final v in l['b'] as List) (v as num).toDouble()],
          ),
      ];

  final List<(List<List<double>>, List<double>)> _layers;

  /// Raw scores of the last layer; higher means preferred.
  List<double> call(List<double> input) {
    var x = input;
    for (var l = 0; l < _layers.length; l++) {
      final (w, b) = _layers[l];
      final hidden = l < _layers.length - 1;
      x = [
        for (var o = 0; o < w.length; o++)
          _activate(_dot(w[o], x) + b[o], hidden),
      ];
    }
    return x;
  }

  static double _dot(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double _activate(double v, bool hidden) {
    if (!hidden) return v;
    if (v.abs() > 20) return v.sign;
    final e = exp(2 * v);
    return (e - 1) / (e + 1); // tanh
  }
}
