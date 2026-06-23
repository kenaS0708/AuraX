import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'door_classifier.dart';
import 'door_detector.dart';
import 'yolo_labels.dart';

class Detection {
  final int classId;
  final double confidence;
  final double cx, cy, w, h;

  const Detection({
    required this.classId, required this.confidence,
    required this.cx, required this.cy,
    required this.w,  required this.h,
  });

  double get left   => (cx - w / 2).clamp(0.0, 1.0);
  double get right  => (cx + w / 2).clamp(0.0, 1.0);
  double get top    => (cy - h / 2).clamp(0.0, 1.0);
  double get bottom => (cy + h / 2).clamp(0.0, 1.0);
  double get area   => w * h;

  String get side {
    if (cx < 0.35) return 'слева';
    if (cx > 0.65) return 'справа';
    return 'прямо';
  }

  String get distance {
    if (area > 0.18) return 'вплотную';
    if (area > 0.06) return 'рядом';
    if (area > 0.01) return 'в нескольких шагах';
    return 'вдали';
  }

  int get priority => YoloLabels.priority[classId] ?? 3;
}

// COCO class IDs → наш classId
const _cocoMap = <int, int>{
  0:  0,  // person
  1:  1,  // bicycle
  2:  2,  // car
  3:  3,  // motorcycle
  5:  4,  // bus
  7:  5,  // truck
  9:  6,  // traffic light
  10: 12, // fire hydrant
  11: 7,  // stop sign
  13: 11, // bench
  56: 8,  // chair
  57: 9,  // couch
  59: 9,  // bed
  60: 10, // dining table
  62: 17, // tv
  72: 10, // refrigerator
};

// ML Kit labels для объектов которых нет в COCO
const _mlkitMap = <String, int>{
  'door':     15,
  'doorway':  14,
  'open door':14,
  'staircase':13,
  'stairs':   13,
  'stairway': 13,
  'crosswalk':16,
  'zebra crossing':16,
};

class YoloDetector {
  static const int _inputSize = 640;
  static const double _confThreshold = 0.30;
  static const double _iouThreshold  = 0.45;

  Interpreter? _tflite;
  ImageLabeler? _labeler;

  bool get isLoaded => _tflite != null;

  // Устанавливается из YoloModelManager после загрузки door.tflite
  DoorDetector?   doorDetector;
  DoorClassifier? doorClassifier;

  Future<void> load(String modelPath) async {
    _tflite?.close();
    _labeler?.close();

    // TFLite для COCO объектов
    try {
      final options = InterpreterOptions();
      try { options.addDelegate(GpuDelegate()); } catch (_) {}
      _tflite = Interpreter.fromFile(File(modelPath), options: options);
      debugPrint('✅ YOLOv8n TFLite загружен: ${File(modelPath).lengthSync() ~/ 1024}KB');
    } catch (e) {
      debugPrint('❌ TFLite ошибка: $e');
      rethrow;
    }

    // ML Kit для дверей/лестниц (дополнительно)
    try {
      _labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.75));
    } catch (_) {}
  }

  void dispose() {
    _tflite?.close();
    _labeler?.close();
    _tflite = null;
    _labeler = null;
  }

  Future<List<Detection>> detect(Uint8List jpegBytes) async {
    if (_tflite == null) return [];

    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return [];

    // Авто-яркость для тёмных кадров
    final bright = _autoBrighten(decoded);

    // Ресайз до 640×640 для YOLO
    final resized = img.copyResize(bright, width: _inputSize, height: _inputSize,
        interpolation: img.Interpolation.linear);

    final results = await Future.wait([
      _runYolo(resized, decoded.width.toDouble(), decoded.height.toDouble()),
    ]);
    final yoloDets = results[0] as List<Detection>;
    debugPrint('🟢 YOLO: ${yoloDets.length}');
    final all = [...yoloDets];
    all.sort((a, b) {
      final pc = a.priority.compareTo(b.priority);
      return pc != 0 ? pc : b.area.compareTo(a.area);
    });
    return all;
  }

  Future<List<Detection>> _runYolo(img.Image resized, double origW, double origH) async {
    // Input: [1, 640, 640, 3] float32
    final input = List.generate(1, (_) =>
      List.generate(_inputSize, (y) =>
        List.generate(_inputSize, (x) {
          final p = resized.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        })));

    // Output: [1, 84, 8400]
    final outShape = _tflite!.getOutputTensor(0).shape;
    final output = List.generate(1, (_) =>
      List.generate(outShape[1], (_) => List<double>.filled(outShape[2], 0.0)));

    _tflite!.run(input, output);
    return _parseYoloOutput(output[0], origW, origH);
  }

  List<Detection> _parseYoloOutput(List<List<double>> out, double origW, double origH) {
    final anchors = out[0].length; // 8400
    final raw = <Detection>[];

    for (int i = 0; i < anchors; i++) {
      int bestCls = 0;
      double bestScore = 0.0;
      for (int c = 0; c < 80; c++) {
        final s = out[4 + c][i];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < _confThreshold) continue;
      // Лог топ-детекций для диагностики (все классы, не только наши)
      if (bestScore > 0.25) {
        debugPrint('🔍 YOLO raw: cls=$bestCls score=${(bestScore*100).round()}% cx=${out[0][i].toStringAsFixed(2)} cy=${out[1][i].toStringAsFixed(2)}');
      }

      if (!_cocoMap.containsKey(bestCls)) continue;

      // onnx2tf даёт координаты в пикселях 0–640, нормализуем
      raw.add(Detection(
        classId:    _cocoMap[bestCls]!,
        confidence: bestScore,
        cx: (out[0][i] / _inputSize).clamp(0.0, 1.0),
        cy: (out[1][i] / _inputSize).clamp(0.0, 1.0),
        w:  (out[2][i] / _inputSize).clamp(0.0, 1.0),
        h:  (out[3][i] / _inputSize).clamp(0.0, 1.0),
      ));
    }

    return _nms(raw);
  }

  List<Detection> _nms(List<Detection> dets) {
    final byClass = <int, List<Detection>>{};
    for (final d in dets) (byClass[d.classId] ??= []).add(d);
    final result = <Detection>[];
    for (final list in byClass.values) {
      list.sort((a, b) => b.confidence.compareTo(a.confidence));
      final sup = List<bool>.filled(list.length, false);
      for (int i = 0; i < list.length; i++) {
        if (sup[i]) continue;
        result.add(list[i]);
        for (int j = i + 1; j < list.length; j++) {
          if (!sup[j] && _iou(list[i], list[j]) > _iouThreshold) sup[j] = true;
        }
      }
    }
    return result;
  }

  double _iou(Detection a, Detection b) {
    final x1 = (a.cx - a.w/2).clamp(0.0, 1.0);
    final y1 = (a.cy - a.h/2).clamp(0.0, 1.0);
    final x2 = (a.cx + a.w/2).clamp(0.0, 1.0);
    final y2 = (a.cy + a.h/2).clamp(0.0, 1.0);
    final bx1 = (b.cx - b.w/2).clamp(0.0, 1.0);
    final by1 = (b.cy - b.h/2).clamp(0.0, 1.0);
    final bx2 = (b.cx + b.w/2).clamp(0.0, 1.0);
    final by2 = (b.cy + b.h/2).clamp(0.0, 1.0);
    final ix1 = x1 > bx1 ? x1 : bx1;
    final iy1 = y1 > by1 ? y1 : by1;
    final ix2 = x2 < bx2 ? x2 : bx2;
    final iy2 = y2 < by2 ? y2 : by2;
    if (ix2 <= ix1 || iy2 <= iy1) return 0.0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    return inter / (a.w * a.h + b.w * b.h - inter);
  }

  Future<List<Detection>> _runLabeling(Uint8List jpegBytes) async {
    try {
      final tmpDir = (await getTemporaryDirectory()).path;
      final tmpFile = File('$tmpDir/mlkit_lbl.jpg');
      await tmpFile.writeAsBytes(jpegBytes);
      final labels = await _labeler!.processImage(InputImage.fromFilePath(tmpFile.path));
      debugPrint('🏷️ Labels: ${labels.map((l) => '${l.label}(${(l.confidence*100).round()}%)').join(', ')}');
      final result = <Detection>[];
      for (final lbl in labels) {
        final text = lbl.label.toLowerCase();
        int? cls;
        for (final e in _mlkitMap.entries) {
          if (text.contains(e.key)) { cls = e.value; break; }
        }
        if (cls == null) continue;
        result.add(Detection(classId: cls, confidence: lbl.confidence,
            cx: 0.5, cy: 0.6, w: 0.25, h: 0.4));
      }
      return result;
    } catch (e) {
      return [];
    }
  }

  img.Image _autoBrighten(img.Image src) {
    int sum = 0;
    for (int y = 0; y < src.height; y += 4) {
      for (int x = 0; x < src.width; x += 4) {
        final p = src.getPixel(x, y);
        sum += ((p.r + p.g + p.b) / 3).round();
      }
    }
    final avg = sum / ((src.width * src.height) / 16);
    if (avg >= 90) return src;
    return img.adjustColor(src, gamma: avg < 50 ? 0.5 : 0.7, brightness: 1.3);
  }
}
