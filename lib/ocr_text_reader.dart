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
      return _normalize(_reliableLines(recognized).join('\n'));
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

  List<String> _reliableLines(RecognizedText recognized) {
    final lines = <String>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (!_isReliableLine(text, line.confidence)) continue;
        lines.add(text);
      }
    }

    return lines.toSet().toList();
  }

  bool _isReliableLine(String text, double? confidence) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return false;

    // Android exposes confidence; iOS returns null. Be conservative when it is present.
    if (confidence != null && confidence < 0.72) return false;

    final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(normalized).length;
    final digits = RegExp(r'\d').allMatches(normalized).length;
    final words = RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').allMatches(normalized).length;
    final hasCyrillic = RegExp(r'[А-Яа-яЁё]').hasMatch(normalized);

    // Years, dates, isolated numbers and one/two-letter hallucinations are common false positives.
    if (letters < 4) return false;
    if (words == 0) return false;
    if (digits > letters && !hasCyrillic) return false;

    // For non-Cyrillic single-word results require a longer token, otherwise ML Kit often
    // hallucinates short Latin words on photos without readable text.
    if (!hasCyrillic && words == 1 && letters < 6) return false;

    return true;
  }

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
