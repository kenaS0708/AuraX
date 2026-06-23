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
          'tessedit_char_whitelist':
              '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
              'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
              'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
              ' .,!?-:;()',
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
      final text = _cleanReliableLine(rawLine);
      if (text == null) continue;
      lines.add(text);
    }

    return lines.toSet().toList();
  }

  String? _cleanReliableLine(String rawLine) {
    final chunks = rawLine
        .split(RegExp(r'[§=|_~<>\\[\\]{}()]+|[.!?;:]+'))
        .map(_cleanChunk)
        .where((chunk) => chunk != null)
        .cast<String>()
        .toList();

    if (chunks.isEmpty) return null;
    chunks.sort((a, b) => _lineQuality(b).compareTo(_lineQuality(a)));

    final best = chunks.first;
    if (!_isReliableLine(best)) return null;
    return best;
  }

  String? _cleanChunk(String chunk) {
    final tokens = RegExp(r'[A-Za-zА-Яа-яЁё0-9-]+')
        .allMatches(chunk)
        .map((m) => m.group(0)!)
        .where(_isUsefulToken)
        .toList();

    if (tokens.isEmpty) return null;
    if (!tokens.any((token) => RegExp(r'[A-Za-zА-Яа-яЁё]{4,}').hasMatch(token))) {
      return null;
    }

    return tokens.join(' ');
  }

  bool _isUsefulToken(String token) {
    final hasCyrillic = RegExp(r'[А-Яа-яЁё]').hasMatch(token);
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(token);
    final hasLetters = RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(token);
    final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(token).length;

    if (!hasLetters) return token.length >= 2;
    if (hasCyrillic && hasLatin) return false;
    if (letters < 3) return false;
    if (hasLatin && letters < 6) return false;
    return true;
  }

  int _lineQuality(String text) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    var score = 0;
    for (final token in tokens) {
      final cyrillic = RegExp(r'[А-Яа-яЁё]').allMatches(token).length;
      final latin = RegExp(r'[A-Za-z]').allMatches(token).length;
      score += cyrillic * 3;
      score += latin;
      if (RegExp(r'^[А-ЯЁ][а-яё]+$').hasMatch(token)) score += 4;
      if (token.length <= 3) score -= 3;
    }
    return score;
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
