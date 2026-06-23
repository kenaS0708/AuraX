import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Классифицирует состояние двери (open/closed/semi) по вырезанному региону.
/// Input:  [1, 3, 224, 224] NCHW float32
/// Output: [1, 3] — {0: Closed, 1: Open, 2: Semi}
class DoorClassifier {
  static const int _sz = 224;

  OrtSession? _session;
  bool get isLoaded => _session != null;

  Future<void> load(String modelPath) async {
    _session?.release();
    try {
      OrtEnv.instance.init();
      _session = OrtSession.fromFile(File(modelPath), OrtSessionOptions());
      debugPrint('✅ DoorClassifier загружен: ${File(modelPath).lengthSync() ~/ 1024}KB');
    } catch (e) {
      debugPrint('❌ DoorClassifier: $e');
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
  }

  // {0: Closed, 1: Open, 2: Semi, 3: no_door}
  static const double _threshold = 0.55;

  /// Классифицирует кадр. null = двери нет.
  Future<int?> classifyFrame(img.Image frame) async {
    if (_session == null) return null;

    final resized = img.copyResize(frame, width: _sz, height: _sz,
        interpolation: img.Interpolation.linear);

    final data = Float32List(_sz * _sz * 3);
    int ri = 0, gi = _sz * _sz, bi = _sz * _sz * 2;
    for (int y = 0; y < _sz; y++) {
      for (int x = 0; x < _sz; x++) {
        final p = resized.getPixel(x, y);
        data[ri++] = p.r / 255.0;
        data[gi++] = p.g / 255.0;
        data[bi++] = p.b / 255.0;
      }
    }

    try {
      final tensor = OrtValueTensor.createTensorWithDataList(data, [1, 3, _sz, _sz]);
      final outputs = await _session!.runAsync(OrtRunOptions(), {'images': tensor});
      tensor.release();

      final scores = (outputs?[0]?.value as List?)?.first as List?;
      for (final o in outputs ?? []) o?.release();
      if (scores == null) return null;

      final closed = scores[0] as double;
      final open   = scores[1] as double;
      final semi   = scores[2] as double;
      final noDoor = scores[3] as double;

      debugPrint('🚪 cls: C=${closed.toStringAsFixed(2)} O=${open.toStringAsFixed(2)} S=${semi.toStringAsFixed(2)} N=${noDoor.toStringAsFixed(2)}');

      // Если no_door побеждает — молчим
      if (noDoor >= closed && noDoor >= open && noDoor >= semi) return null;

      final best = [closed, open, semi].reduce((a, b) => a > b ? a : b);
      if (best < _threshold) return null;

      if (open >= closed && open >= semi) return 14; // открыта
      if (semi >= closed)                return 14; // полуоткрыта → открыта
      return 15; // закрыта
    } catch (e) {
      debugPrint('❌ DoorClassifier: $e');
      return null;
    }
  }

  /// Классифицирует вырезанный регион (для совместимости).
  Future<int> classify(img.Image crop) async =>
      (await classifyFrame(crop)) ?? 15;
}
