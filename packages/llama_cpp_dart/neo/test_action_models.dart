// ignore_for_file: avoid_print

import 'dart:typed_data';

// No changes to VideoFrame class
class VideoFrame {
  final Uint8List imageData;
  final double timestamp;
  final int frameNumber;

  VideoFrame({
    required this.imageData,
    required this.timestamp,
    required this.frameNumber,
  });
}

enum ActionType {
  tap,
  longPress,
  swipe,
  inputText,
  scroll,
  wait,
  verify,
}

class TestAction {
  final ActionType type;
  final Map<String, dynamic>? coordinates;
  final Map<String, dynamic>? swipeStart;
  final Map<String, dynamic>? swipeEnd;
  final String? text;
  final String? direction;
  final String elementDescription;
  final double confidence;
  final double timestamp;
  final int frameNumber;

  TestAction({
    required this.type,
    this.coordinates,
    this.swipeStart,
    this.swipeEnd,
    this.text,
    this.direction,
    required this.elementDescription,
    required this.confidence,
    required this.timestamp,
    required this.frameNumber,
  });

  // **IMPROVED: Safer JSON parsing**
  factory TestAction.fromJson(Map<String, dynamic> json) {
    return TestAction(
      type: _parseActionType(json['type']?.toString() ?? 'tap'),
      coordinates: json['coordinates'] as Map<String, dynamic>?,
      swipeStart: json['swipe_start'] as Map<String, dynamic>?,
      swipeEnd: json['swipe_end'] as Map<String, dynamic>?,
      text: json['text'] as String?,
      direction: json['direction'] as String?,
      elementDescription: json['element_description']?.toString() ?? 'Unknown element',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      frameNumber: (json['frame_number'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.toString().split('.').last,
        if (coordinates != null) 'coordinates': coordinates,
        if (swipeStart != null) 'swipe_start': swipeStart,
        if (swipeEnd != null) 'swipe_end': swipeEnd,
        if (text != null) 'text': text,
        if (direction != null) 'direction': direction,
        'element_description': elementDescription,
        'confidence': confidence,
        'timestamp': timestamp,
        'frame_number': frameNumber,
      };

  // **IMPROVED: More robust parsing for action types**
  static ActionType _parseActionType(String type) {
    switch (type.toLowerCase()) {
      case 'tap':
        return ActionType.tap;
      case 'long_press':
      case 'longpress':
        return ActionType.longPress;
      case 'swipe':
        return ActionType.swipe;
      case 'input_text':
      case 'inputtext':
      case 'type':
      case 'enter_text':
        return ActionType.inputText;
      case 'scroll':
        return ActionType.scroll;
      case 'wait':
      case 'delay':
        return ActionType.wait;
      case 'assert':
      case 'verify':
      case 'check':
        return ActionType.verify;
      default:
        print("Warning: Unknown action type '$type', defaulting to 'tap'.");
        return ActionType.tap;
    }
  }

  String toScriptLine() {
    final x = coordinates?['x'] ?? 0;
    final y = coordinates?['y'] ?? 0;
    switch (type) {
      case ActionType.tap:
        return 'await tester.tapAt($x, $y); // $elementDescription';
      case ActionType.longPress:
        return 'await tester.longPressAt($x, $y); // $elementDescription';
      case ActionType.swipe:
        return 'await tester.swipe(from: (${swipeStart?['x']}, ${swipeStart?['y']}), to: (${swipeEnd?['x']}, ${swipeEnd?['y']})); // $elementDescription';
      case ActionType.inputText:
        return 'await tester.enterText("$text"); // $elementDescription';
      case ActionType.scroll:
        return 'await tester.scroll(direction: "$direction"); // $elementDescription';
      case ActionType.wait:
        // Use a more realistic wait time if available, otherwise default
        final waitSeconds = (timestamp > 1.0) ? timestamp.round() : 2;
        return 'await tester.wait(Duration(seconds: $waitSeconds)); // $elementDescription';
      case ActionType.verify:
        return 'await tester.verifyVisible("$elementDescription");';
    }
  }
}

class TestSequence {
  final String appName;
  final String platform;
  final List<TestAction> actions;
  final double totalDuration;
  final int frameCount;

  TestSequence({
    required this.appName,
    required this.platform,
    required this.actions,
    required this.totalDuration,
    required this.frameCount,
  });

  Map<String, dynamic> toJson() => {
        'app_name': appName,
        'platform': platform,
        'total_duration_seconds': totalDuration,
        'frame_count': frameCount,
        'action_count': actions.length,
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  String toTestScript() {
    final buffer = StringBuffer();
    buffer.writeln('// Auto-generated test for $appName on $platform');
    buffer.writeln('// Duration: ${totalDuration.toStringAsFixed(1)}s');
    buffer.writeln('// Frames analyzed: $frameCount');
    buffer.writeln('// Actions detected: ${actions.length}\n');
    buffer.writeln('Future<void> testScenario() async {');

    double lastTimestamp = 0.0;
    for (final action in actions) {
      // Add a delay based on the actual time between actions
      final timeDiff = action.timestamp - lastTimestamp;
      if (timeDiff > 0.5) { // Only add delay if it's significant
        buffer.writeln(
            '  await Future.delayed(Duration(milliseconds: ${(timeDiff * 1000).round()}));');
      }
      buffer.writeln('  ${action.toScriptLine()}');
      lastTimestamp = action.timestamp;
    }

    buffer.writeln('}');
    return buffer.toString();
  }
}