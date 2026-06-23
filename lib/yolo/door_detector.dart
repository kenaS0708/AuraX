import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'yolo_detector.dart';

/// Детектор дверей на базе специализированной YOLOv8n ONNX модели.
/// Классы: 0=door_open → classId 14, 1=door_closed → classId 15
/// Входной тензор: [1, 3, 640, 640] float32 (NCHW)
/// Выходной тензор: [1, 6, 8400] — 4 bbox + 2 класса
class DoorDetector {
  static const int _sz = 640;
  static const double _conf = 0.35;
  static const double _iou  = 0.45;

  OrtSession? _session;
  bool get isLoaded => _session != null;

  Future<void> load(String modelPath) async {
    _session?.release();
    try {
      OrtEnv.instance.init();
      final opts = OrtSessionOptions();
      _session = OrtSession.fromFile(File(modelPath), opts);
      debugPrint('✅ DoorDetector (ONNX) загружен: ${File(modelPath).lengthSync() ~/ 1024}KB');
    } catch (e) {
      debugPrint('❌ DoorDetector: $e');
      rethrow;
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
  }

  Future<List<Detection>> detect(img.Image resized640) async {
    if (_session == null) return [];
    try {
      // Строим NCHW float32 тензор [1, 3, 640, 640]
      final inputData = Float32List(_sz * _sz * 3);
      int rOff = 0;
      int gOff = _sz * _sz;
      int bOff = _sz * _sz * 2;
      for (int y = 0; y < _sz; y++) {
        for (int x = 0; x < _sz; x++) {
          final p = resized640.getPixel(x, y);
          inputData[rOff++] = p.r / 255.0;
          inputData[gOff++] = p.g / 255.0;
          inputData[bOff++] = p.b / 255.0;
        }
      }

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData,
        [1, 3, _sz, _sz],
      );

      final inputs = {'images': inputTensor};
      final outputs = await _session!.runAsync(OrtRunOptions(), inputs);
      inputTensor.release();

      // output0: [1, 6, 8400]
      final out = outputs?[0]?.value as List?;
      if (out == null) return [];

      // out[0] → batch=0 → List<List<double>> shape [6][8400]
      final batch = out[0] as List;
      final rows = batch.map((r) => (r as List).cast<double>()).toList();

      for (final o in outputs ?? []) o?.release();

      return _parse(rows);
    } catch (e) {
      debugPrint('❌ DoorDetector.detect: $e');
      return [];
    }
  }

  List<Detection> _parse(List<List<double>> rows) {
    final n = rows[0].length;
    final raw = <Detection>[];

    double maxOpen = 0, maxClosed = 0;

    for (int i = 0; i < n; i++) {
      final s0 = rows[4][i];
      final s1 = rows[5][i];
      if (s0 > maxOpen)   maxOpen   = s0;
      if (s1 > maxClosed) maxClosed = s1;

      if (s1 < _conf) continue;
      final bestScore = s1;

      // class 0 = state_A, class 1 = state_B (определим тестом что есть что)
      final classId = s0 >= s1 ? 14 : 15;
      debugPrint('🚪 s0=${s0.toStringAsFixed(2)} s1=${s1.toStringAsFixed(2)} → ${classId==14?"open":"closed"}');

      raw.add(Detection(
        classId:    classId,
        confidence: bestScore,
        cx: (rows[0][i] / _sz).clamp(0.0, 1.0),
        cy: (rows[1][i] / _sz).clamp(0.0, 1.0),
        w:  (rows[2][i] / _sz).clamp(0.0, 1.0),
        h:  (rows[3][i] / _sz).clamp(0.0, 1.0),
      ));
    }
    debugPrint('🚪 maxScores: s0(open)=${maxOpen.toStringAsFixed(2)} s1(closed)=${maxClosed.toStringAsFixed(2)} detections=${raw.length}');
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
    final ax1 = (a.cx - a.w / 2).clamp(0.0, 1.0);
    final ay1 = (a.cy - a.h / 2).clamp(0.0, 1.0);
    final ax2 = (a.cx + a.w / 2).clamp(0.0, 1.0);
    final ay2 = (a.cy + a.h / 2).clamp(0.0, 1.0);
    final bx1 = (b.cx - b.w / 2).clamp(0.0, 1.0);
    final by1 = (b.cy - b.h / 2).clamp(0.0, 1.0);
    final bx2 = (b.cx + b.w / 2).clamp(0.0, 1.0);
    final by2 = (b.cy + b.h / 2).clamp(0.0, 1.0);
    final ix1 = ax1 > bx1 ? ax1 : bx1;
    final iy1 = ay1 > by1 ? ay1 : by1;
    final ix2 = ax2 < bx2 ? ax2 : bx2;
    final iy2 = ay2 < by2 ? ay2 : by2;
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }
}
