import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'yolo_detector.dart';

/// ONNX детектор специально для слабовидящих.
/// Модель: blind_v3 (YOLOv8n, 9 классов)
/// 0=crosswalk 1=stairs 2=door 3=pothole 4=pole
/// 5=person 6=vehicle 7=traffic_light 8=obstacle
/// Input:  [1, 3, 640, 640] NCHW float32
/// Output: [1, 13, 8400]  (4 bbox + 9 классов)
class BlindDetector {
  static const int    _sz   = 640;
  static const double _conf = 0.30;
  static const double _iou  = 0.45;
  static const int    _nc   = 9;

  OrtSession? _session;
  bool get isLoaded => _session != null;

  Future<void> load(String modelPath) async {
    _session?.release();
    try {
      OrtEnv.instance.init();
      _session = OrtSession.fromFile(File(modelPath), OrtSessionOptions());
      debugPrint('✅ BlindDetector загружен: ${File(modelPath).lengthSync() ~/ 1024}KB');
    } catch (e) {
      debugPrint('❌ BlindDetector: $e');
      rethrow;
    }
  }

  void dispose() { _session?.release(); _session = null; }

  Future<List<Detection>> detect(img.Image frame) async {
    if (_session == null) return [];
    try {
      final resized = img.copyResize(frame, width: _sz, height: _sz,
          interpolation: img.Interpolation.linear);

      // NCHW float32
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

      final tensor = OrtValueTensor.createTensorWithDataList(data, [1, 3, _sz, _sz]);
      final outputs = await _session!.runAsync(OrtRunOptions(), {'images': tensor});
      tensor.release();

      // [1, 12, 8400]
      final batch = (outputs?[0]?.value as List?)?.first as List?;
      for (final o in outputs ?? []) o?.release();
      if (batch == null) return [];

      final rows = batch.map((r) => (r as List).cast<double>()).toList();
      return _parse(rows);
    } catch (e) {
      debugPrint('❌ BlindDetector.detect: $e');
      return [];
    }
  }

  List<Detection> _parse(List<List<double>> rows) {
    final n = rows[0].length;
    final raw = <Detection>[];

    // Debug: find max score across all anchors
    double globalMax = 0;
    int globalMaxCls = 0;
    int globalMaxAnchor = 0;
    for (int i = 0; i < n; i++) {
      for (int c = 0; c < _nc; c++) {
        final s = rows[4 + c][i];
        if (s > globalMax) { globalMax = s; globalMaxCls = c; globalMaxAnchor = i; }
      }
    }
    debugPrint('🔍 BlindDet: rows=${rows.length} anchors=$n maxScore=${globalMax.toStringAsFixed(3)} cls=$globalMaxCls anchor=$globalMaxAnchor');

    for (int i = 0; i < n; i++) {
      int    bestCls   = 0;
      double bestScore = 0;
      for (int c = 0; c < _nc; c++) {
        final s = rows[4 + c][i];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < _conf) continue;

      raw.add(Detection(
        classId:    bestCls,
        confidence: bestScore,
        cx: (rows[0][i] / _sz).clamp(0.0, 1.0),
        cy: (rows[1][i] / _sz).clamp(0.0, 1.0),
        w:  (rows[2][i] / _sz).clamp(0.0, 1.0),
        h:  (rows[3][i] / _sz).clamp(0.0, 1.0),
      ));
    }

    debugPrint('🟢 BlindDet: ${raw.length} перед NMS');
    return _nms(raw);
  }

  List<Detection> _nms(List<Detection> dets) {
    final byClass = <int, List<Detection>>{};
    for (final d in dets) (byClass[d.classId] ??= []).add(d);
    final res = <Detection>[];
    for (final list in byClass.values) {
      list.sort((a, b) => b.confidence.compareTo(a.confidence));
      final sup = List<bool>.filled(list.length, false);
      for (int i = 0; i < list.length; i++) {
        if (sup[i]) continue;
        res.add(list[i]);
        for (int j = i + 1; j < list.length; j++) {
          if (!sup[j] && _iouOf(list[i], list[j]) > _iou) sup[j] = true;
        }
      }
    }
    return res;
  }

  double _iouOf(Detection a, Detection b) {
    final ax1 = (a.cx - a.w/2).clamp(0.0, 1.0);
    final ay1 = (a.cy - a.h/2).clamp(0.0, 1.0);
    final ax2 = (a.cx + a.w/2).clamp(0.0, 1.0);
    final ay2 = (a.cy + a.h/2).clamp(0.0, 1.0);
    final bx1 = (b.cx - b.w/2).clamp(0.0, 1.0);
    final by1 = (b.cy - b.h/2).clamp(0.0, 1.0);
    final bx2 = (b.cx + b.w/2).clamp(0.0, 1.0);
    final by2 = (b.cy + b.h/2).clamp(0.0, 1.0);
    final ix1 = ax1 > bx1 ? ax1 : bx1;
    final iy1 = ay1 > by1 ? ay1 : by1;
    final ix2 = ax2 < bx2 ? ax2 : bx2;
    final iy2 = ay2 < by2 ? ay2 : by2;
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }
}
