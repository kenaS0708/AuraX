import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;

class OcrTextReader {
  Future<String> read(Uint8List jpegBytes) async {
    File? tmpFile;
    try {
      tmpFile = File(
        '${Directory.systemTemp.path}/lumen_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tmpFile.writeAsBytes(_prepareForOcr(jpegBytes), flush: true);

      final recognized = await FlutterTesseractOcr.extractText(
        tmpFile.path,
        language: 'rus+eng',
        args: {
          'psm': '11',
          'preserve_interword_spaces': '1',
          'user_defined_dpi': '300',
        },
      );
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

  Future<void> close() async {}

  Uint8List _prepareForOcr(Uint8List jpegBytes) {
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) return jpegBytes;

    var prepared = decoded;
    final maxSide = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (maxSide < 1800) {
      final scale = 1800 / maxSide;
      prepared = img.copyResize(
        prepared,
        width: (decoded.width * scale).round(),
        height: (decoded.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }

    prepared = img.grayscale(prepared);
    prepared = img.adjustColor(prepared, contrast: 1.65);
    return Uint8List.fromList(img.encodeJpg(prepared, quality: 95));
  }

  List<String> _reliableLines(String recognized) {
    final lines = <String>[];

    for (final rawLine in recognized.split(RegExp(r'\r?\n'))) {
      final text = rawLine.trim();
      if (!_isReliableLine(text)) continue;
      lines.add(text);
    }

    return lines.toSet().toList();
  }

  bool _isReliableLine(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return false;

    final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(normalized).length;
    final digits = RegExp(r'\d').allMatches(normalized).length;
    final words = RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').allMatches(normalized).length;
    final hasCyrillic = RegExp(r'[А-Яа-яЁё]').hasMatch(normalized);

    // Years, dates, isolated numbers and one/two-letter hallucinations are common false positives.
    if (letters < 4) return false;
    if (words == 0) return false;
    if (digits > letters && !hasCyrillic) return false;

    // For non-Cyrillic single-word results require a longer token, otherwise OCR can
    // hallucinate short Latin words on photos without readable text.
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
