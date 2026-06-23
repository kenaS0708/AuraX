import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum ModelStatus { notDownloaded, downloadingModel, downloadingMmproj, loading, ready, failed }

class _DownloadCancelled implements Exception {}

class LocalModelManager extends ChangeNotifier {
  static const _modelFileName  = 'gemma-4-E2B-it-Q4_K_M.gguf';
  static const _mmprojFileName = 'mmproj-F16.gguf';
  static const _baseUrl        = 'https://huggingface.co/unsloth/gemma-4-E2B-IT-GGUF/resolve/main';
  static const modelDownloadUrl  = '$_baseUrl/$_modelFileName';
  static const mmprojDownloadUrl = '$_baseUrl/$_mmprojFileName';

  // Минимальный размер готового файла
  static const _minModelBytes  = 2_900_000_000; // 2.9 GB из 3.1 GB
  static const _minMmprojBytes =   800_000_000; // 800 MB из ~1 GB

  ModelStatus _status      = ModelStatus.notDownloaded;
  double      _progress    = 0.0;
  String?     _errorMessage;
  LlamaParent? _parent;
  CancelToken? _cancelToken;
  bool _downloading = false;

  ModelStatus get status       => _status;
  double      get progress     => _progress;
  String?     get errorMessage => _errorMessage;
  bool        get isReady      => _status == ModelStatus.ready && _parent != null;

  Future<void> init() async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    final modelOk  = _fileOk('$dir/$_modelFileName',  _minModelBytes);
    final mmprojOk = _fileOk('$dir/$_mmprojFileName', _minMmprojBytes);
    if (modelOk && mmprojOk) {
      _status = ModelStatus.loading;
      notifyListeners();
      await _loadModel();
    }
  }

  bool _fileOk(String path, int minBytes) {
    final f = File(path);
    return f.existsSync() && f.lengthSync() >= minBytes;
  }

  // ── Скачивание ────────────────────────────────────────────

  Future<void> startDownload() async {
    if (_downloading) return;
    _downloading = true;
    _errorMessage = null;
    await WakelockPlus.enable();

    try {
      final dir = (await getApplicationDocumentsDirectory()).path;

      // Шаг 1 — основная модель (с авто-ретраями)
      if (!_fileOk('$dir/$_modelFileName', _minModelBytes)) {
        _status = ModelStatus.downloadingModel;
        notifyListeners();
        await _downloadWithRetry(
          url:      modelDownloadUrl,
          savePath: '$dir/$_modelFileName',
          onProgress: (done, total) {
            _progress = total > 0 ? done / total * 0.76 : _progress;
            notifyListeners();
          },
        );
      }
      _progress = 0.76;
      notifyListeners();

      // Шаг 2 — mmproj (с авто-ретраями)
      if (!_fileOk('$dir/$_mmprojFileName', _minMmprojBytes)) {
        _status = ModelStatus.downloadingMmproj;
        notifyListeners();
        await _downloadWithRetry(
          url:      mmprojDownloadUrl,
          savePath: '$dir/$_mmprojFileName',
          onProgress: (done, total) {
            _progress = 0.76 + (total > 0 ? done / total * 0.24 : 0);
            notifyListeners();
          },
        );
      }

      _progress = 1.0;
      _status   = ModelStatus.loading;
      notifyListeners();
      await _loadModel();
    } on _DownloadCancelled {
      // пользователь отменил — тихо выходим
    } catch (e) {
      _errorMessage = e.toString();
      _status       = ModelStatus.failed;
      notifyListeners();
    } finally {
      _downloading = false;
      _cancelToken = null;
      await WakelockPlus.disable();
    }
  }

  // Скачивание с бесконечными авто-ретраями при обрыве соединения
  Future<void> _downloadWithRetry({
    required String url,
    required String savePath,
    void Function(int done, int total)? onProgress,
  }) async {
    int attempt = 0;
    while (true) {
      if (!_downloading) throw _DownloadCancelled();
      try {
        await _download(url: url, savePath: savePath, onProgress: onProgress);
        return; // успех
      } on _DownloadCancelled {
        rethrow;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) throw _DownloadCancelled();
        // Обрыв соединения — ждём и повторяем
        attempt++;
        final wait = Duration(seconds: (attempt * 3).clamp(3, 30));
        debugPrint('⚠️ Download interrupted (attempt $attempt), retrying in ${wait.inSeconds}s: $e');
        await Future.delayed(wait);
      } catch (e) {
        // Другая ошибка — тоже ретраим
        attempt++;
        final wait = Duration(seconds: (attempt * 3).clamp(3, 30));
        debugPrint('⚠️ Download error (attempt $attempt), retrying in ${wait.inSeconds}s: $e');
        await Future.delayed(wait);
      }
    }
  }

  Future<void> retryDownload() async {
    _cancelToken?.cancel('retry');
    _downloading = false;
    await Future.delayed(const Duration(milliseconds: 300));
    // НЕ удаляем файлы — продолжаем с того места где остановились
    _status       = ModelStatus.notDownloaded;
    _progress     = 0;
    _errorMessage = null;
    _parent?.dispose();
    _parent = null;
    notifyListeners();
    await startDownload();
  }

  // Удаляет всё и начинает с нуля
  Future<void> deleteAndRedownload() async {
    _cancelToken?.cancel('delete');
    _downloading = false;
    _parent?.dispose();
    _parent = null;
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final dir = (await getApplicationDocumentsDirectory()).path;
      final mf = File('$dir/$_modelFileName');
      final pf = File('$dir/$_mmprojFileName');
      if (mf.existsSync()) mf.deleteSync();
      if (pf.existsSync()) pf.deleteSync();
    } catch (_) {}

    _status       = ModelStatus.notDownloaded;
    _progress     = 0;
    _errorMessage = null;
    notifyListeners();
    await startDownload();
  }

  // ── Resumable HTTP download ───────────────────────────────

  Future<void> _download({
    required String url,
    required String savePath,
    void Function(int done, int total)? onProgress,
  }) async {
    final file         = File(savePath);
    final existingSize = file.existsSync() ? file.lengthSync() : 0;

    _cancelToken = CancelToken();

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(hours: 3),
      followRedirects: true,
      maxRedirects: 8,
    ));

    // ВСЕГДА добавляем Range если файл уже есть — никогда не перезаписываем
    final headers = <String, dynamic>{};
    if (existingSize > 0) {
      headers['Range'] = 'bytes=$existingSize-';
    }

    // Узнаём полный размер через HEAD (опционально)
    int totalSize = 0;
    try {
      final head = await dio.head(url);
      totalSize = int.tryParse(head.headers.value('content-length') ?? '') ?? 0;
      // HEAD даёт размер всего файла, Range-запрос получит остаток
    } catch (_) {}

    // Файл уже полный — пропускаем
    if (totalSize > 0 && existingSize >= totalSize) {
      onProgress?.call(totalSize, totalSize);
      return;
    }

    final response = await dio.get<ResponseBody>(
      url,
      cancelToken: _cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        followRedirects: true,
        maxRedirects: 8,
      ),
    );

    final chunkLen = int.tryParse(
        response.headers.value('content-length') ?? '') ?? 0;
    final fullSize = totalSize > 0 ? totalSize : existingSize + chunkLen;

    // Всегда дописываем если файл уже существовал
    final openMode = existingSize > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly;

    final raf = await file.open(mode: openMode);
    int written = existingSize;

    final completer = Completer<void>();
    response.data!.stream.listen(
      (chunk) {
        raf.writeFromSync(chunk);
        written += chunk.length;
        if (fullSize > 0) onProgress?.call(written, fullSize);
      },
      onError: (e) { raf.closeSync(); completer.completeError(e); },
      onDone:  ()  { raf.closeSync(); completer.complete(); },
      cancelOnError: true,
    );

    await completer.future;
  }

  // ── Загрузка модели в память ──────────────────────────────

  Future<void> _loadModel() async {
    try {
      final dir        = (await getApplicationDocumentsDirectory()).path;
      final modelPath  = '$dir/$_modelFileName';
      final mmprojPath = '$dir/$_mmprojFileName';

      if (Platform.isAndroid) Llama.libraryPath = 'libmtmd.so';

      final parent = LlamaParent(
        LlamaLoad(
          path:           modelPath,
          mmprojPath:     mmprojPath,
          modelParams:    ModelParams()
            ..nGpuLayers = 0
            ..splitMode  = LlamaSplitMode.layer,
          contextParams:  ContextParams()
            ..nCtx        = 1024
            ..nBatch      = 512
            ..nUbatch     = 512
            ..nPredict    = 64
            ..nThreads    = 8
            ..nThreadsBatch = 8
            ..offloadKqv  = false
            ..opOffload   = false
            ..swaFull     = true,
          samplingParams: SamplerParams()
            ..temp = 0.8
            ..topK = 40
            ..topP = 0.9,
          verbose:        true,
        ),
        GemmaFormat(),
      );

      await parent.init();
      _parent = parent;
      _status = ModelStatus.ready;
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('🔴 _loadModel error: $e');
      _status = ModelStatus.failed;
    }
    notifyListeners();
  }

  // ── Инференс ─────────────────────────────────────────────

  Future<String?> analyze(Uint8List jpeg, {String? userPrompt}) async {
    final parent = _parent;
    if (!isReady || parent == null) return null;

    final prompt = (userPrompt != null && userPrompt.isNotEmpty)
        ? '<image>\n$userPrompt'
        : '<image>\nТы помощник для слабовидящего человека. '
          'Опиши только то, что важно для безопасного передвижения: '
          'препятствия на пути, открыта или закрыта дверь если есть, '
          'пешеходный переход и где он находится если есть, '
          'ступеньки или перепады высоты, '
          'люди или машины рядом если они создают опасность, '
          'важные надписи или знаки. '
          'Не описывай стены, пол, потолок, цвета и декор — только то что влияет на передвижение. '
          'Отвечай по-русски, 1-3 коротких предложения.';

    try {
      // Resize to max 224×224 — SigLIP uses 1 tile at this size → fewer tokens → faster
      Uint8List inputJpeg = jpeg;
      final decoded = img.decodeJpg(jpeg);
      if (decoded != null && (decoded.width > 224 || decoded.height > 224)) {
        final resized = img.copyResize(decoded, width: 224, height: 224,
            interpolation: img.Interpolation.average);
        inputJpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }
      final promptId = await parent.sendPromptWithImages(
          prompt, [LlamaImage.fromBytes(inputJpeg)]);
      final buffer = StringBuffer();
      final sub    = parent.stream.listen((t) => buffer.write(t));
      await parent.waitForCompletion(promptId);
      await sub.cancel();
      return buffer.toString().trim();
    } catch (_) { return null; }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _parent?.dispose();
    super.dispose();
  }
}
