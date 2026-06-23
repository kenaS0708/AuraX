import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrTextReader {
  final TextRecognizer _recognizer = TextRecognizer();

  Future<String> read(Uint8List jpegBytes) async {
    File? tmpFile;
    try {
      tmpFile = File(
        '${Directory.systemTemp.path}/lumen_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmpFile.writeAsBytes(jpegBytes, flush: true);

      final inputImage = InputImage.fromFilePath(tmpFile.path);
      final recognized = await _recognizer.processImage(inputImage);
      return _normalize(recognized.text);
    } catch (e) {
      debugPrint('OCR error: $e');
      return '';
    } finally {
      try {
        await tmpFile?.delete();
      } catch (_) {}
    }
  }

  Future<void> close() => _recognizer.close();

  String _normalize(String text) {
    final cleaned = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('. ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.length <= 1200) return cleaned;
    return '${cleaned.substring(0, 1200).trim()}...';
  }
}
