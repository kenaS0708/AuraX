import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'ble_manager.dart';
import 'local_model.dart';
import 'yolo/yolo_model_manager.dart';
import 'yolo/scene_describer.dart';

enum UiPhase {
  idle, scanning, connecting, connected,
  capturing, receiving, uploading, speaking,
  recording, errorа
}

class AppState extends ChangeNotifier {
  static const _defaultServerUrl = 'https://10.199.255.206:8000/upload';
  static const _defaultBleName = 'ESP32-CAM';

  UiPhase _phase = UiPhase.idle;
  String _statusText = 'Нажмите для съёмки';
  Uint8List? _lastPhoto;
  final List<Uint8List> _photos = [];
  String? _aiResponse;
  int _receiveProgress = 0;
  bool _isBleConnected = false;
  String _serverUrl = _defaultServerUrl;
  String _bleDeviceName = _defaultBleName;
  bool _isRealtimeMode = false;
  bool _isNavigating = false;
  Map<String, dynamic>? _pendingNavDest;
  double? _compassHeading;
  bool _isServerOnline = false;
  Timer? _pingTimer;

  UiPhase get phase => _phase;
  String get statusText => _statusText;
  Uint8List? get lastPhoto => _lastPhoto;
  List<Uint8List> get photos => List.unmodifiable(_photos);
  String? get aiResponse => _aiResponse;
  int get receiveProgress => _receiveProgress;
  bool get isBleConnected => _isBleConnected;
  String get serverUrl => _serverUrl;
  String get bleDeviceName => _bleDeviceName;
  bool get isRealtimeMode => _isRealtimeMode;
  bool get isNavigating => _isNavigating;
  Map<String, dynamic>? get pendingNavDest => _pendingNavDest;
  bool get isServerOnline => _isServerOnline;
  LocalModelManager get localModel => _localModel;
  YoloModelManager get yoloModel => _yoloModel;

  late final BleManager _bleManager;
  final LocalModelManager _localModel = LocalModelManager();
  final YoloModelManager  _yoloModel  = YoloModelManager();
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Completer<Uint8List>? _realtimeJpegCompleter;
  String? _pendingAudioPath;
  bool _recordingStarted = false;
  DateTime? _recordingStartTime;
  Timer? _navTimer;
  late final String _sessionId;

  AppState() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _bleManager = BleManager(onStateChanged: _onBleState);
    _initTts();
    _loadSettings();
    // Gemma отключена — используем YOLO
    _yoloModel.addListener(notifyListeners);
    _yoloModel.init();
    FlutterCompass.events?.listen((e) {
      if (e.heading != null) _compassHeading = e.heading;
    });
    _startPinging();
  }

  // ── Пинг сервера ─────────────────────────────────────────────

  void _startPinging() {
    _pingServer();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pingServer());
  }

  Future<void> _pingServer() async {
    try {
      final base = Uri.parse(_serverUrl);
      final pingUrl = base.replace(path: '/health');
      final response = await _buildHttpClient()
          .get(pingUrl)
          .timeout(const Duration(seconds: 5));
      final online = response.statusCode < 500;
      if (online != _isServerOnline) {
        _isServerOnline = online;
        notifyListeners();
      }
    } catch (_) {
      if (_isServerOnline) {
        _isServerOnline = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url') ?? _defaultServerUrl;
    // Сбрасываем битый URL с двойным слешем
    _serverUrl = saved.contains('//upload') && saved.contains(':8080//upload')
        ? _defaultServerUrl
        : saved;
    _bleDeviceName = prefs.getString('ble_device_name') ?? _defaultBleName;
    notifyListeners();
  }

  Future<void> saveSettings(String url, String bleName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url.trim());
    await prefs.setString('ble_device_name', bleName.trim());
    _serverUrl = url.trim();
    _bleDeviceName = bleName.trim();
    notifyListeners();
  }

  String get _realtimeUrl {
    try {
      return Uri.parse(_serverUrl).replace(path: '/realtime').toString();
    } catch (_) {
      return _serverUrl;
    }
  }

  String get _navUpdateUrl {
    try {
      return Uri.parse(_serverUrl).replace(path: '/navigate/update').toString();
    } catch (_) {
      return _serverUrl;
    }
  }

  String get _navStartUrl {
    try {
      return Uri.parse(_serverUrl).replace(path: '/navigate/start').toString();
    } catch (_) {
      return _serverUrl;
    }
  }

  http.Client _buildHttpClient() => IOClient(
    HttpClient()..badCertificateCallback = (cert, host, port) => true,
  );

  Future<Position?> _getPosition() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Тоны ─────────────────────────────────────────────────────

  /// Генерирует WAV-файл с синусоидой в памяти (без внешних файлов)
  Uint8List _buildBeepWav({required double freq, required int durationMs}) {
    const sampleRate = 22050;
    final numSamples = (sampleRate * durationMs / 1000).round();
    final pcm = ByteData(numSamples * 2);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      // Огибающая: плавное нарастание 15мс и спад 15мс
      final fadeLen = (sampleRate * 0.015).round();
      final fadeIn  = i < fadeLen ? i / fadeLen : 1.0;
      final fadeOut = i > numSamples - fadeLen
          ? (numSamples - i) / fadeLen
          : 1.0;
      final sample = 0.45 * fadeIn * fadeOut * sin(2 * pi * freq * t);
      pcm.setInt16(i * 2, (32767 * sample).round(), Endian.little);
    }

    final dataSize = numSamples * 2;
    final wav = ByteData(44 + dataSize);
    // RIFF chunk
    wav.setUint8(0,  0x52); wav.setUint8(1,  0x49);
    wav.setUint8(2,  0x46); wav.setUint8(3,  0x46); // "RIFF"
    wav.setUint32(4, 36 + dataSize, Endian.little);
    wav.setUint8(8,  0x57); wav.setUint8(9,  0x41);
    wav.setUint8(10, 0x56); wav.setUint8(11, 0x45); // "WAVE"
    // fmt chunk
    wav.setUint8(12, 0x66); wav.setUint8(13, 0x6D);
    wav.setUint8(14, 0x74); wav.setUint8(15, 0x20); // "fmt "
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);             // PCM
    wav.setUint16(22, 1, Endian.little);             // mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    // data chunk
    wav.setUint8(36, 0x64); wav.setUint8(37, 0x61);
    wav.setUint8(38, 0x74); wav.setUint8(39, 0x61); // "data"
    wav.setUint32(40, dataSize, Endian.little);
    wav.buffer.asUint8List().setRange(44, 44 + dataSize,
        pcm.buffer.asUint8List());

    return wav.buffer.asUint8List();
  }

  Future<void> _playStartTone() async {
    // 880 Hz (A5) — высокий, чистый старт
    await _player.play(BytesSource(_buildBeepWav(freq: 880, durationMs: 160)));
  }

  Future<void> _playStopTone() async {
    // 660 Hz (E5) — чуть ниже, означает "стоп"
    await _player.play(BytesSource(_buildBeepWav(freq: 660, durationMs: 120)));
  }

  // ── Кнопка на ESP32 ──────────────────────────────────────────

  void _onButtonEvent(bool isPressed) {
    if (isPressed) {
      // Ждём окончания тона (160мс), только потом стартуем запись —
      // иначе AudioPlayer забирает аудио-фокус и убивает рекордер.
      _playStartTone().then((_) => startVoiceCapture());
    } else {
      stopVoiceCapture();
      _playStopTone();
    }
  }

  // ── Режим по кнопке (короткое нажатие в UI) ──────────────────

  Future<bool> analyzeGalleryPhoto() async {
    try {
      final picker = ImagePicker();
      // maxWidth/maxHeight ограничивают размер до обработки — иначе 4K фото блокирует UI
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return false;
      final bytes = await picked.readAsBytes();
      _handleJpeg(bytes);
      return true;
    } catch (e) {
      debugPrint('❌ Gallery picker: $e');
      return false;
    }
  }

  void onCaptureButtonClick() {
    if (_isRealtimeMode) return;
    if (_phase == UiPhase.idle || _phase == UiPhase.error) {
      _aiResponse = null;
      _startBleAndCapture();
    } else if (_phase == UiPhase.connected || _phase == UiPhase.speaking) {
      _aiResponse = null;
      _tts.stop();
      _phase = UiPhase.connected;
      notifyListeners();
      _capturePhoto();
    }
  }

  void dismissAiResponse() {
    _aiResponse = null;
    _tts.stop();
    if (_phase == UiPhase.speaking) {
      _phase = UiPhase.connected;
    }
    notifyListeners();
  }

  void _startBleAndCapture() {
    _bleManager
        .scanAndConnect(_bleDeviceName,
            onJpeg: _handleJpeg,
            onButtonEvent: _onButtonEvent)
        .catchError((e) {
      _phase = UiPhase.error;
      _statusText = 'Ошибка BLE: $e';
      notifyListeners();
    });
  }

  void _capturePhoto() {
    _bleManager.capturePhoto();
  }

  // ── Голосовой промт (долгое нажатие в UI или физ. кнопка) ────

  Future<void> startVoiceCapture() async {
    if (_isRealtimeMode) return;
    if ({
      UiPhase.scanning, UiPhase.connecting,
      UiPhase.capturing, UiPhase.receiving,
      UiPhase.uploading, UiPhase.recording,
    }.contains(_phase)) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _statusText = 'Нет доступа к микрофону';
      notifyListeners();
      return;
    }

    final path = '${Directory.systemTemp.path}/voice_prompt.m4a';
    _recordingStarted = false;
    _recordingStartTime = null;
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
        path: path,
      );
      _recordingStarted = true;
      _recordingStartTime = DateTime.now();
    } catch (e) {
      _statusText = 'Ошибка микрофона: $e';
      notifyListeners();
      return;
    }

    _phase = UiPhase.recording;
    _statusText = 'Говорите...';
    notifyListeners();
  }

  Future<void> stopVoiceCapture() async {
    if (!_recordingStarted) return;
    _recordingStarted = false;

    // Ждём минимум 1.2 сек чтобы микрофон прогрелся и захватил аудио
    const minRecordMs = 1200;
    final startTime = _recordingStartTime;
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsed < minRecordMs) {
        await Future.delayed(Duration(milliseconds: minRecordMs - elapsed));
      }
    }

    // Сразу сбрасываем фазу, чтобы кнопка не зависала
    _phase = _isBleConnected ? UiPhase.connected : UiPhase.idle;
    _statusText = _isBleConnected ? 'Подключено' : 'Нажмите для съёмки';
    notifyListeners();

    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}

    if (path == null) return;
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1000) return;

    _pendingAudioPath = path;
    _statusText = 'Голосовой запрос...';
    notifyListeners();

    if (_isBleConnected) {
      _capturePhoto();
    } else {
      _bleManager
          .scanAndConnect(_bleDeviceName,
              onJpeg: _handleJpeg,
              onButtonEvent: _onButtonEvent)
          .catchError((e) {
        _pendingAudioPath = null;
        _phase = UiPhase.error;
        _statusText = 'Ошибка BLE: $e';
        notifyListeners();
      });
    }
  }

  // ── Режим реального времени (HTTP каждые ~3 сек) ─────────────

  void toggleRealtimeMode() {
    if (_isRealtimeMode) {
      _stopRealtimeMode();
    } else {
      _isRealtimeMode = true;
      notifyListeners();
      _startRealtimeMode();
    }
  }

  void _startRealtimeMode() {
    if (_isBleConnected) {
      _runRealtimeLoop();
    } else {
      _bleManager
          .scanAndConnect(_bleDeviceName,
              onJpeg: _handleJpeg,
              onButtonEvent: _onButtonEvent)
          .catchError((e) {
        _isRealtimeMode = false;
        _phase = UiPhase.error;
        _statusText = 'Ошибка BLE: $e';
        notifyListeners();
      });
    }
  }

  void _stopRealtimeMode() {
    _isRealtimeMode = false;
    _realtimeJpegCompleter?.completeError('stopped');
    _realtimeJpegCompleter = null;
    _tts.stop();
    _aiResponse = null;
    _phase = _isBleConnected ? UiPhase.connected : UiPhase.idle;
    _statusText = _isBleConnected ? 'Подключено' : 'Нажмите для съёмки';
    notifyListeners();
  }

  Future<void> _runRealtimeLoop() async {
    while (_isRealtimeMode && _isBleConnected) {
      _realtimeJpegCompleter = Completer<Uint8List>();
      _capturePhoto();

      Uint8List jpeg;
      try {
        jpeg = await _realtimeJpegCompleter!.future
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        _realtimeJpegCompleter = null;
        if (_isRealtimeMode) {
          _isRealtimeMode = false;
          _phase = UiPhase.error;
          _statusText = 'Ошибка: таймаут камеры';
          notifyListeners();
        }
        return;
      }
      _realtimeJpegCompleter = null;
      if (!_isRealtimeMode) return;

      _lastPhoto = jpeg;
      _phase = UiPhase.uploading;
      _statusText = 'Реальное время • Анализ...';
      notifyListeners();

      String responseText = '';
      try {
        final ioClient = IOClient(
          HttpClient()..badCertificateCallback = (cert, host, port) => true,
        );
        final request = http.MultipartRequest('POST', Uri.parse(_realtimeUrl));
        request.files.add(http.MultipartFile.fromBytes(
          'file', jpeg,
          filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ));
        final streamed = await ioClient
            .send(request)
            .timeout(const Duration(seconds: 30));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode == 200) {
          final json = jsonDecode(body) as Map<String, dynamic>;
          responseText = (json['text'] as String?)?.trim() ?? '';
        }
      } catch (_) {}

      if (!_isRealtimeMode) return;

      if (responseText.isNotEmpty) {
        _aiResponse = responseText;
        _tts.speak(responseText);
      }

      _phase = UiPhase.connected;
      _statusText = 'Реальное время';
      notifyListeners();

      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // ── Навигация ─────────────────────────────────────────────────

  void _startNavigation() {
    _isNavigating = true;
    notifyListeners();
    _navTimer?.cancel();
    _navTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sendNavUpdate(),
    );
  }

  void stopNavigation() {
    _navTimer?.cancel();
    _navTimer = null;
    _isNavigating = false;
    _pendingNavDest = null;
    notifyListeners();
  }

  Future<void> confirmNavigation() async {
    final dest = _pendingNavDest;
    if (dest == null) return;
    _pendingNavDest = null;
    notifyListeners();

    final pos = await _getPosition();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_navStartUrl));
      request.fields['destination'] = dest['destination'].toString();
      request.fields['session_id'] = _sessionId;
      if (pos != null) {
        request.fields['lat'] = pos.latitude.toString();
        request.fields['lon'] = pos.longitude.toString();
      }
      if (_compassHeading != null) {
        request.fields['heading'] = _compassHeading!.toStringAsFixed(1);
      }

      final streamed = await _buildHttpClient()
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) return;

      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final text = (json['text'] as String?)?.trim() ?? '';
      if (text.isNotEmpty) {
        _aiResponse = text;
        notifyListeners();
        await _tts.speak(text);
      }
      _startNavigation();
    } catch (e) {
      _phase = UiPhase.error;
      _statusText = 'Ошибка навигации: $e';
      notifyListeners();
    }
  }

  void cancelNavigation() {
    _pendingNavDest = null;
    notifyListeners();
  }

  Future<void> _sendNavUpdate() async {
    if (!_isNavigating) return;
    final pos = await _getPosition();
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_navUpdateUrl));
      if (pos != null) {
        request.fields['lat'] = pos.latitude.toString();
        request.fields['lon'] = pos.longitude.toString();
      }
      if (_compassHeading != null) {
        request.fields['heading'] = _compassHeading!.toStringAsFixed(1);
      }
      request.fields['session_id'] = _sessionId;

      final streamed = await _buildHttpClient()
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (streamed.statusCode != 200) return;

      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final action = json['action'] as String?;
      final text = (json['text'] as String?)?.trim() ?? '';

      if (text.isNotEmpty) {
        _aiResponse = text;
        notifyListeners();
        _tts.speak(text);
      }

      if (action == 'arrived' || action == 'no_route') {
        stopNavigation();
      }
    } catch (_) {}
  }

  // ── Единый обработчик JPEG ────────────────────────────────────

  void _handleJpeg(Uint8List jpeg) {
    final c = _realtimeJpegCompleter;
    if (_isRealtimeMode && c != null && !c.isCompleted) {
      c.complete(jpeg);
    } else {
      final audioPath = _pendingAudioPath;
      _pendingAudioPath = null;
      _uploadAndSpeak(jpeg, audioPath: audioPath);
    }
  }

  // ── BLE state ────────────────────────────────────────────────

  void _onBleState(BleState state) {
    switch (state.status) {
      case BleStatus.idle:
        _phase = UiPhase.idle;
        _statusText = 'Нажмите для съёмки';
        _isBleConnected = false;
      case BleStatus.scanning:
        _phase = UiPhase.scanning;
        _statusText = 'Поиск ${state.deviceName}...';
        _isBleConnected = false;
      case BleStatus.connecting:
        _phase = UiPhase.connecting;
        _statusText = 'Подключение...';
        _isBleConnected = false;
      case BleStatus.connected:
        _isBleConnected = true;
        if (_phase == UiPhase.connecting || _phase == UiPhase.scanning) {
          _phase = UiPhase.connected;
          if (_isRealtimeMode) {
            _statusText = 'Реальное время';
            _runRealtimeLoop();
          } else {
            _statusText = 'Подключено • Снимаем...';
            _capturePhoto();
          }
        } else {
          _phase = UiPhase.connected;
          _statusText = _isRealtimeMode ? 'Реальное время' : 'Подключено';
        }
      case BleStatus.capturing:
        _phase = UiPhase.capturing;
        _statusText = _isRealtimeMode
            ? 'Реальное время • Снимок...'
            : 'Снимаем фото...';
        _isBleConnected = true;
      case BleStatus.receiving:
        _phase = UiPhase.receiving;
        _receiveProgress = state.progress;
        _statusText = _isRealtimeMode
            ? 'Реальное время • ${state.progress}%'
            : 'Получаем фото: ${state.progress}%';
        _isBleConnected = true;
      case BleStatus.disconnected:
        _isBleConnected = false;
        if (_isRealtimeMode) {
          _isRealtimeMode = false;
          _realtimeJpegCompleter?.completeError('disconnected');
          _realtimeJpegCompleter = null;
        }
        _pendingAudioPath = null;
        _phase = UiPhase.idle;
        _statusText = state.message.isNotEmpty
            ? 'Отключено: ${state.message}'
            : 'Нажмите для съёмки';
      case BleStatus.error:
        _isBleConnected = false;
        if (_isRealtimeMode) {
          _isRealtimeMode = false;
          _realtimeJpegCompleter?.completeError('error');
          _realtimeJpegCompleter = null;
        }
        _pendingAudioPath = null;
        _phase = UiPhase.error;
        _statusText = 'Ошибка: ${state.message}';
    }
    notifyListeners();
  }

  // ── Загрузка на сервер и TTS ──────────────────────────────────

  Future<void> _uploadAndSpeak(
    Uint8List jpegBytes, {
    String? audioPath,
    double? lat,
    double? lon,
  }) async {
    _lastPhoto = jpegBytes;
    _photos.add(jpegBytes);
    _phase = UiPhase.uploading;
    _statusText = audioPath != null ? 'Голосовой запрос...' : 'Анализируем фото...';
    notifyListeners();

    // Пробуем сервер, если онлайн
    if (_isServerOnline) {
      final ok = await _tryUploadToServer(
        jpegBytes,
        audioPath: audioPath,
        lat: lat,
        lon: lon,
      );
      if (ok) return;
      // Сервер ответил с ошибкой — обновляем статус и пробуем локально
      _isServerOnline = false;
      notifyListeners();
    }

    // Fallback: локальная модель
    await _analyzeLocally(jpegBytes);
  }

  Future<bool> _tryUploadToServer(
    Uint8List jpegBytes, {
    String? audioPath,
    double? lat,
    double? lon,
  }) async {
    try {
      if (lat == null || lon == null) {
        final pos = await _getPosition();
        if (pos != null) {
          lat = pos.latitude;
          lon = pos.longitude;
        }
      }

      final request = http.MultipartRequest('POST', Uri.parse(_serverUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'file', jpegBytes,
        filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ));
      if (audioPath != null) {
        final audioBytes = await File(audioPath).readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'audio', audioBytes,
          filename: 'voice.m4a',
        ));
      }
      if (lat != null) request.fields['lat'] = lat.toString();
      if (lon != null) request.fields['lon'] = lon.toString();
      request.fields['session_id'] = _sessionId;

      final streamed = await _buildHttpClient()
          .send(request)
          .timeout(const Duration(seconds: 60));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) return false;

      final json = jsonDecode(body) as Map<String, dynamic>;
      final action = json['action'] as String?;
      final text = (json['text'] as String?)?.trim() ?? '';

      if (action == 'confirm_navigate') {
        if (text.isNotEmpty) await _tts.speak(text);
        _pendingNavDest = {
          'dest_lat': json['dest_lat'],
          'dest_lon': json['dest_lon'],
          'destination': json['destination'] ?? '',
        };
        _aiResponse = text;
        _phase = _isBleConnected ? UiPhase.connected : UiPhase.idle;
        _statusText = 'Подтвердите маршрут';
        notifyListeners();
        return true;
      }

      if (action == 'request_location') {
        if (text.isNotEmpty) _tts.speak(text);
        final pos = await _getPosition();
        if (pos != null) {
          return _tryUploadToServer(
            jpegBytes,
            audioPath: audioPath,
            lat: pos.latitude,
            lon: pos.longitude,
          );
        }
        _phase = UiPhase.error;
        _statusText = 'Нет доступа к геолокации';
        notifyListeners();
        return true;
      }

      if (text.isEmpty) return false;

      _aiResponse = text;
      _phase = UiPhase.speaking;
      _statusText = _isNavigating ? 'Навигация' : 'Подключено';
      notifyListeners();
      await _tts.speak(text);

      if (action == 'navigation_started') _startNavigation();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _analyzeLocally(Uint8List jpegBytes) async {
    // ── YOLO: быстрое локальное описание (~50мс) ──────────
    if (_yoloModel.isReady) {
      _phase = UiPhase.uploading;
      _statusText = 'Анализирую...';
      notifyListeners();

      // Уступаем event loop чтобы UI обновился до тяжёлой работы
      await Future.delayed(Duration.zero);

      try {
        final sw = Stopwatch()..start();
        final decoded = img.decodeImage(jpegBytes);
        if (decoded == null) throw Exception('Не удалось декодировать изображение');
        final detections = await _yoloModel.blindDetector.detect(decoded);
        sw.stop();
        debugPrint('🟢 YOLO: ${detections.length} объектов за ${sw.elapsedMilliseconds}мс');

        final text = SceneDescriber.describe(detections);
        _aiResponse = text;
        _phase = UiPhase.speaking;
        _statusText = 'Подключено • Офлайн';
        notifyListeners();
        await _tts.speak(text);
        return;
      } catch (e) {
        debugPrint('🔴 YOLO ошибка: $e');
        // Всегда ставим ответ — иначе ResultScreen зависнет на "Анализируем..."
        _aiResponse = 'Не удалось обработать изображение.';
        _phase = UiPhase.speaking;
        notifyListeners();
        await _tts.speak('Не удалось обработать изображение.');
        return;
      }
    }

    // ── Fallback: нет модели ──────────────────────────────
    _aiResponse = 'Офлайн-детектор не готов.';
    _phase = UiPhase.error;
    _statusText = 'Офлайн-детектор не готов';
    notifyListeners();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() {
      if (_isRealtimeMode) {
        _aiResponse = null;
        notifyListeners();
      } else if (_phase == UiPhase.speaking) {
        _phase = UiPhase.connected;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _navTimer?.cancel();
    _localModel.dispose();
    _yoloModel.removeListener(notifyListeners);
    _yoloModel.dispose();
    _tts.stop();
    _recorder.dispose();
    _player.dispose();
    _bleManager.dispose();
    super.dispose();
  }
}
