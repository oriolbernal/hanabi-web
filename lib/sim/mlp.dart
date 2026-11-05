import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A small network exported from PyTorch:
/// `{"activation": "tanh" | "relu", "layers": [{"w": [[...]], "b": [...]}, ...]}`
/// (tanh when the activation is not said). A layer may instead hold its
/// weights as bytes, `{"q": base64 of int16 (little-endian), "bits": 16,
/// "scale": [one per row], "rows": n, "cols": m, "b": [...]}`, each weight
/// being q * scale of its row: a third of the size of the text, for the
/// large self-play network.
class Mlp {
  Mlp(Map<String, dynamic> weights)
    : _relu = weights['activation'] == 'relu',
      _layers = [
        for (final l in weights['layers'] as List)
          (
            _weights(l as Map<String, dynamic>),
            [for (final v in l['b'] as List) (v as num).toDouble()],
          ),
      ];

  static List<Float64List> _weights(Map<String, dynamic> l) {
    if (l['q'] == null) {
      return [
        for (final row in l['w'] as List)
          Float64List.fromList([
            for (final v in row as List) (v as num).toDouble(),
          ]),
      ];
    }
    final bytes = base64Decode(l['q'] as String);
    final List<int> q = l['bits'] == 16
        ? Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2)
        : Int8List.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final rows = l['rows'] as int, cols = l['cols'] as int;
    final scale = l['scale'] as List;
    return [
      for (var r = 0; r < rows; r++)
        Float64List.fromList([
          for (var c = 0; c < cols; c++)
            q[r * cols + c] * (scale[r] as num).toDouble(),
        ]),
    ];
  }

  final bool _relu;
  final List<(List<Float64List>, List<double>)> _layers;

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

  static double _dot(Float64List a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  double _activate(double v, bool hidden) {
    if (!hidden) return v;
    if (_relu) return v > 0 ? v : 0;
    if (v.abs() > 20) return v.sign;
    final e = exp(2 * v);
    return (e - 1) / (e + 1); // tanh
  }
}
