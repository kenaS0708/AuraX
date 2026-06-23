import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'blind_detector.dart';
import 'yolo_detector.dart';

enum YoloStatus { loading, ready, failed }

class YoloModelManager extends ChangeNotifier {
  static const _blindAsset = 'assets/models/blind.onnx';

  YoloStatus _status = YoloStatus.loading;
  String?    _error;

  final BlindDetector blindDetector = BlindDetector();
  // Заглушка для совместимости с существующим кодом
  final YoloDetector  detector      = YoloDetector();

  YoloStatus get status  => _status;
  String?    get error   => _error;
  bool       get isReady => _status == YoloStatus.ready;
  double     get progress => isReady ? 1.0 : 0.0;

  Future<void> init() async {
    _status = YoloStatus.loading;
    notifyListeners();
    try {
      final dir  = (await getApplicationDocumentsDirectory()).path;
      final dest = File('$dir/blind.onnx');
      final data = await rootBundle.load(_blindAsset);
      await dest.writeAsBytes(data.buffer.asUint8List());
      await blindDetector.load(dest.path);
      _status = YoloStatus.ready;
    } catch (e) {
      _error  = e.toString();
      _status = YoloStatus.failed;
      debugPrint('❌ YoloModelManager: $_error');
    }
    notifyListeners();
  }

  Future<void> downloadAndLoad() => init();

  @override
  void dispose() {
    blindDetector.dispose();
    super.dispose();
  }
}
