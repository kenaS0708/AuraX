import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:image/image.dart' as img;

enum BleStatus { idle, scanning, connecting, connected, capturing, receiving, disconnected, error }

class BleState {
  final BleStatus status;
  final String deviceName;
  final int progress;
  final String message;

  const BleState({
    this.status = BleStatus.idle,
    this.deviceName = '',
    this.progress = 0,
    this.message = '',
  });
}

class BleManager {
  static const _serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const _commandUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const _dataUuid   = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const _eventUuid  = 'beb5483e-36e1-4688-b7f5-ea07361b26aa'; // кнопка ESP32

  final void Function(BleState) onStateChanged;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandChar;
  StreamSubscription? _scanSub;
  StreamSubscription? _notifySub;
  StreamSubscription? _eventSub;
  StreamSubscription? _connectionSub;
  void Function(bool isPressed)? _onButtonEvent;
  Timer? _scanTimer;
  Timer? _dataTimer;

  final List<Uint8List> _jpegBuffer = [];
  int _totalExpectedChunks = 0;
  void Function(Uint8List)? _onJpeg;

  BleManager({required this.onStateChanged});

  Future<void> scanAndConnect(String deviceName, {
    required void Function(Uint8List) onJpeg,
    void Function(bool isPressed)? onButtonEvent,
  }) async {
    _onJpeg = onJpeg;
    _onButtonEvent = onButtonEvent;
    _device = null;
    onStateChanged(BleState(status: BleStatus.scanning, deviceName: deviceName));

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      onStateChanged(BleState(status: BleStatus.error, message: 'Ошибка BLE: $e'));
      return;
    }

    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name.toLowerCase() == deviceName.toLowerCase()) {
          _stopScan();
          _connect(r.device);
          break;
        }
      }
    });

    _scanTimer = Timer(const Duration(seconds: 16), () {
      if (_device == null) {
        _stopScan();
        onStateChanged(BleState(
          status: BleStatus.error,
          message: "Устройство '$deviceName' не найдено",
        ));
      }
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    onStateChanged(const BleState(status: BleStatus.connecting));

    try {
      await device.connect(autoConnect: false);

      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          onStateChanged(const BleState(
            status: BleStatus.disconnected,
            message: 'Устройство отключилось',
          ));
        }
      });

      // Запрашиваем большой MTU чтобы получать чанки целиком (512 байт данных + заголовок)
      await device.requestMtu(512);
      await Future.delayed(const Duration(milliseconds: 300));

      final services = await device.discoverServices();

      final service = services.firstWhere(
        (s) => s.serviceUuid == Guid(_serviceUuid),
        orElse: () => throw Exception('Сервис BLE не найден'),
      );

      _commandChar = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == Guid(_commandUuid),
        orElse: () => throw Exception('COMMAND характеристика не найдена'),
      );

      final dataChar = service.characteristics.firstWhere(
        (c) => c.characteristicUuid == Guid(_dataUuid),
        orElse: () => throw Exception('DATA характеристика не найдена'),
      );

      await dataChar.setNotifyValue(true);
      _notifySub = dataChar.onValueReceived.listen(_handleChunk);

      // Подписываемся на события кнопки (необязательно — не падаем если нет)
      try {
        final eventChar = service.characteristics.firstWhere(
          (c) => c.characteristicUuid == Guid(_eventUuid),
        );
        await eventChar.setNotifyValue(true);
        _eventSub = eventChar.onValueReceived.listen((data) {
          if (data.isEmpty) return;
          if (data[0] == 0x02) _onButtonEvent?.call(true);
          if (data[0] == 0x03) _onButtonEvent?.call(false);
        });
      } catch (_) {
        // EVENT-характеристика не найдена — продолжаем без неё
      }

      onStateChanged(const BleState(status: BleStatus.connected));
    } catch (e) {
      onStateChanged(BleState(status: BleStatus.error, message: e.toString()));
    }
  }

  Future<void> capturePhoto() async {
    final cmd = _commandChar;
    if (cmd == null) {
      onStateChanged(const BleState(status: BleStatus.error, message: 'Нет BLE-соединения'));
      return;
    }

    _jpegBuffer.clear();
    _totalExpectedChunks = 0;

    try {
      await cmd.write([0x01], withoutResponse: false);
      onStateChanged(const BleState(status: BleStatus.capturing));
      _startDataTimer();
    } catch (e) {
      onStateChanged(BleState(status: BleStatus.error, message: 'Ошибка команды: $e'));
    }
  }

  void _handleChunk(List<int> data) {
    if (data.length < 3) return;

    final seqNum = ((data[0] & 0xFF) << 8) | (data[1] & 0xFF);
    final flags = data[2] & 0xFF;
    final payload = Uint8List.fromList(data.sublist(3));

    _dataTimer?.cancel();

    while (_jpegBuffer.length <= seqNum) {
      _jpegBuffer.add(Uint8List(0));
    }
    _jpegBuffer[seqNum] = payload;

    if (flags == 0xFF) {
      _totalExpectedChunks = seqNum + 1;
    }

    final filled = _jpegBuffer.where((c) => c.isNotEmpty).length;
    final total = _totalExpectedChunks > 0 ? _totalExpectedChunks : seqNum + 10;
    final progress = (filled * 100 ~/ total).clamp(0, 99);

    onStateChanged(BleState(status: BleStatus.receiving, progress: progress));

    if (flags == 0xFF) {
      _assembleJpeg();
    } else {
      _startDataTimer();
    }
  }

  void _assembleJpeg() {
    final totalSize = _jpegBuffer.fold<int>(0, (sum, c) => sum + c.length);
    if (totalSize == 0) {
      onStateChanged(const BleState(
        status: BleStatus.error,
        message: 'Пустые данные от камеры',
      ));
      return;
    }

    final jpeg = Uint8List(totalSize);
    var offset = 0;
    for (final chunk in _jpegBuffer) {
      jpeg.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _jpegBuffer.clear();

    // Проверка JPEG сигнатуры
    if (jpeg.length < 2 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
      onStateChanged(const BleState(
        status: BleStatus.error,
        message: 'Повреждённые данные JPEG',
      ));
      return;
    }

    // Декодируем
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) {
      onStateChanged(const BleState(
        status: BleStatus.error,
        message: 'Ошибка декодирования JPEG',
      ));
      return;
    }

    // Поворот на 90° вправо
    final rotated = img.copyRotate(decoded, angle: 90);

    // Кодируем обратно
    final rotatedJpeg = Uint8List.fromList(
      img.encodeJpg(rotated, quality: 90),
    );

    onStateChanged(const BleState(status: BleStatus.connected));
    _onJpeg?.call(rotatedJpeg);
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _scanSub = null;
    FlutterBluePlus.stopScan();
  }

  void _startDataTimer() {
    _dataTimer?.cancel();
    _dataTimer = Timer(const Duration(seconds: 30), () {
      onStateChanged(const BleState(
        status: BleStatus.error,
        message: 'Таймаут: ESP32 не отвечает',
      ));
    });
  }

  void dispose() {
    _scanTimer?.cancel();
    _dataTimer?.cancel();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _eventSub?.cancel();
    _connectionSub?.cancel();
    _device?.disconnect();
  }
}
