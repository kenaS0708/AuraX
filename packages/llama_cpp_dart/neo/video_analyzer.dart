// ignore_for_file: avoid_print

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'extract_video_frames.dart';
import 'test_action_models.dart';

/// Configuration class for CCTV analysis settings
class CCTVAnalysisConfig {
  final double targetFps;
  final int comparisonWindow;  // How many frames apart to compare
  final int framesToCompare;   // How many frames to compare at once (2, 3, 4, etc.)
  final bool detectFalls;
  final bool detectFire;
  final bool detectWater;
  final bool detectIntrusion;
  final bool verboseOutput;
  final double motionSensitivity; // 0.0 = report everything, 1.0 = only major changes
  
  CCTVAnalysisConfig({
    this.targetFps = 1.0,
    this.comparisonWindow = 1,
    this.framesToCompare = 2,  // Default to comparing 2 frames
    this.detectFalls = true,
    this.detectFire = true,
    this.detectWater = true,
    this.detectIntrusion = true,
    this.verboseOutput = false,
    this.motionSensitivity = 0.5,
  });
}

class CCTVAnalyzer {
  final Llama llama;
  final CCTVAnalysisConfig config;

  CCTVAnalyzer({
    required this.llama,
    required this.config,
  });

  /// Analyzes CCTV footage with configurable settings
  Future<void> analyzeCCTVFootage({
    required String videoPath,
  }) async {
    if (config.verboseOutput) {
      print("Extracting frames from CCTV footage...");
      print("Settings:");
      print("  - FPS: ${config.targetFps}");
      print("  - Comparison window: ${config.comparisonWindow} frames apart");
      print("  - Frames to compare: ${config.framesToCompare} frames at once");
      print("  - Fall detection: ${config.detectFalls}");
      print("  - Fire detection: ${config.detectFire}");
      print("  - Water/leak detection: ${config.detectWater}");
      print("  - Intrusion detection: ${config.detectIntrusion}");
      print("  - Motion sensitivity: ${config.motionSensitivity}");
    }
    
    final frames = await extractVideoFramesWithTimestamps(
      videoPath: videoPath,
      targetFps: config.targetFps,
      minFps: 0.25,
      maxFps: 60.0,
    );

    if (frames.isEmpty) {
      throw StateError('No frames extracted from video');
    }

    print("\nExtracted ${frames.length} frames at ${config.targetFps} fps");
    print("=== CCTV MOTION DETECTION ANALYSIS ===\n");
    
    // First, establish the baseline (static background)
    print("Establishing baseline scene...");
    final baselineStopwatch = Stopwatch()..start();
    final baselineDescription = await _describeBaseline(frames.first);
    baselineStopwatch.stop();
    
    print("Baseline (${baselineStopwatch.elapsedMilliseconds}ms):");
    print(baselineDescription);
    print("=" * 60);
    
    // Now analyze changes
    final events = <String>[];
    final timings = <int>[];
    int totalTime = 0;
    int significantEvents = 0;
    
    // Calculate step size for frame comparison
    final totalSpan = config.comparisonWindow * (config.framesToCompare - 1);
    
    // Make sure we have enough frames
    for (int i = totalSpan; i < frames.length; i += config.comparisonWindow) {
      // Collect the frames to compare
      final framesToAnalyze = <VideoFrame>[];
      for (int j = 0; j < config.framesToCompare; j++) {
        final frameIndex = i - (config.comparisonWindow * (config.framesToCompare - 1 - j));
        if (frameIndex >= 0 && frameIndex < frames.length) {
          framesToAnalyze.add(frames[frameIndex]);
        }
      }
      
      if (framesToAnalyze.length != config.framesToCompare) continue;
      
      final currentTimestamp = framesToAnalyze.last.timestamp;
      final startTimestamp = framesToAnalyze.first.timestamp;
      
      if (config.verboseOutput) {
        final progress = ((i + 1) / frames.length * 100).toStringAsFixed(1);
        print("\nComparing ${config.framesToCompare} frames from ${startTimestamp.toStringAsFixed(1)}s to ${currentTimestamp.toStringAsFixed(1)}s ($progress%)");
      }

      // Start timing
      final stopwatch = Stopwatch()..start();
      
      // Detect changes between frames
      final changes = await _detectChangesMultiFrame(
        frames: framesToAnalyze,
        startFrameNumber: i - totalSpan + 1,
      );
      
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      timings.add(elapsedMs);
      totalTime += elapsedMs;
      
      // Check if this is a significant event based on sensitivity
      final isSignificant = _evaluateSignificance(changes);
      
      if (!isSignificant) {
        if (config.verboseOutput) {
          print("[${currentTimestamp.toStringAsFixed(1)}s] No significant changes (${elapsedMs}ms)");
        }
      } else {
        significantEvents++;
        final eventLog = "[${startTimestamp.toStringAsFixed(1)}s - ${currentTimestamp.toStringAsFixed(1)}s]: $changes";
        
        // Determine event type and use appropriate emoji
        final eventEmoji = _getEventEmoji(changes);
        print("\n$eventEmoji EVENT at ${currentTimestamp.toStringAsFixed(1)}s (${elapsedMs}ms):");
        print(changes);
        print("-" * 60);
        
        events.add(eventLog);
      }
    }

    // Generate summary report
    await _generateCCTVReport(
      videoPath: videoPath,
      baselineDescription: baselineDescription,
      events: events,
      totalFrames: frames.length,
      significantEvents: significantEvents,
      timings: timings,
      totalTime: totalTime,
    );
  }

  /// Determine event emoji based on detected content
  String _getEventEmoji(String changes) {
    final lowerChanges = changes.toLowerCase();
    if (lowerChanges.contains('fall') || lowerChanges.contains('fell')) return '🚨';
    if (lowerChanges.contains('fire') || lowerChanges.contains('smoke')) return '🔥';
    if (lowerChanges.contains('water') || lowerChanges.contains('leak')) return '💧';
    if (lowerChanges.contains('intru') || lowerChanges.contains('enter')) return '👤';
    return '🔴';
  }

  /// Evaluate if changes are significant based on sensitivity
  bool _evaluateSignificance(String changes) {
    final lowerChanges = changes.toLowerCase();
    
    // Always insignificant
    if (lowerChanges.contains("no_change") || 
        lowerChanges.contains("no significant") || 
        lowerChanges.contains("static")) {
      return false;
    }
    
    // Always significant (safety concerns)
    if (config.detectFalls && (lowerChanges.contains('fall') || lowerChanges.contains('fell'))) return true;
    if (config.detectFire && (lowerChanges.contains('fire') || lowerChanges.contains('smoke'))) return true;
    if (config.detectWater && (lowerChanges.contains('water') || lowerChanges.contains('leak') || lowerChanges.contains('flood'))) return true;
    
    // Check based on sensitivity
    if (config.motionSensitivity < 0.3) {
      // Low sensitivity - report almost everything
      return !lowerChanges.contains("minor");
    } else if (config.motionSensitivity < 0.7) {
      // Medium sensitivity - report clear movements
      return lowerChanges.contains('person') || 
             lowerChanges.contains('walk') || 
             lowerChanges.contains('run') ||
             lowerChanges.contains('move') ||
             lowerChanges.contains('enter') ||
             lowerChanges.contains('exit');
    } else {
      // High sensitivity - only major events
      return lowerChanges.contains('suspicious') ||
             lowerChanges.contains('unusual') ||
             lowerChanges.contains('emergency');
    }
  }

  /// Describe the baseline static scene
  Future<String> _describeBaseline(VideoFrame frame) async {
    final input = LlamaImage.fromBytes(frame.imageData);

    final prompt = """
<|im_start|>System: You are a CCTV scene analyzer. Describe the static background environment.
Focus on:
- Location type (warehouse, office, street, etc.)
- Fixed objects and their positions
- Lighting conditions
- Camera angle and coverage area
Do NOT describe any people or moving objects.
<end_of_utterance>
User:<image>
Describe the static scene/background.
<end_of_utterance>
Assistant:
""";

    try {
      final response = StringBuffer();
      final stream = llama.generateWithMedia(prompt, inputs: [input]);
      
      await for (final token in stream) {
        response.write(token);
      }
      
      return response.toString().trim();
    } catch (e) {
      print("Error analyzing baseline: $e");
      return "Error: Could not establish baseline";
    }
  }

  /// Detect changes across multiple frames
  Future<String> _detectChangesMultiFrame({
    required List<VideoFrame> frames,
    required int startFrameNumber,
  }) async {
    final inputs = frames.map((f) => LlamaImage.fromBytes(f.imageData)).toList();
    
    // Generate correct number of <image> tags
    final imageTags = List.filled(inputs.length, '<image>').join('');
    
    // Calculate time span
    final timeSpan = (frames.last.timestamp - frames.first.timestamp);

    // Build detection focus based on config
    final detectionFocus = <String>[];
    if (config.detectIntrusion) {
      detectionFocus.add("- People entering, leaving, or moving in the scene");
    }
    if (config.detectFalls) {
      detectionFocus.add("- Person falling, lying on ground, or unusual body positions");
    }
    if (config.detectFire) {
      detectionFocus.add("- Fire, smoke, or signs of burning");
    }
    if (config.detectWater) {
      detectionFocus.add("- Water leaks, flooding, or liquid spills");
    }
    detectionFocus.add("- Objects being moved, added, or removed");
    detectionFocus.add("- Any suspicious or unusual behavior");

    final prompt = """
<|im_start|>System: You are a CCTV motion detector. Compare these ${inputs.length} frames taken over ${timeSpan.toStringAsFixed(1)} seconds.
ONLY report changes in:
${detectionFocus.join('\n')}

If nothing significant changed, respond with "NO_CHANGE".
Focus ONLY on what changed between the frames, not the static background.
Be specific about any safety concerns.
<end_of_utterance>
User:$imageTags
What changed between frame 1 and frame ${inputs.length}?
<end_of_utterance>
Assistant:
""";

    try {
      final response = StringBuffer();
      final stream = llama.generateWithMedia(prompt, inputs: inputs);
      
      await for (final token in stream) {
        response.write(token);
      }
      
      return response.toString().trim();
    } catch (e) {
      print("Error detecting changes: $e");
      return "Error analyzing changes";
    }
  }

  /// Generate CCTV-specific report
  Future<void> _generateCCTVReport({
    required String videoPath,
    required String baselineDescription,
    required List<String> events,
    required int totalFrames,
    required int significantEvents,
    required List<int> timings,
    required int totalTime,
  }) async {
    // Calculate statistics
    final avgTime = timings.isEmpty ? 0 : totalTime / timings.length;
    final minTime = timings.isEmpty ? 0 : timings.reduce((a, b) => a < b ? a : b);
    final maxTime = timings.isEmpty ? 0 : timings.reduce((a, b) => a > b ? a : b);
    
    print("\n=== ANALYSIS COMPLETE ===");
    print("Total frames analyzed: $totalFrames");
    print("Significant events detected: $significantEvents");
    print("Processing time: ${(totalTime/1000).toStringAsFixed(2)}s");
    print("Average time per comparison: ${avgTime.toStringAsFixed(0)}ms");
    print("========================\n");

    final report = """
=== CCTV FOOTAGE ANALYSIS REPORT ===
Video: $videoPath
Analysis Time: ${DateTime.now()}

CONFIGURATION:
- Frame Rate: ${config.targetFps} fps
- Comparison Window: ${config.comparisonWindow} frames apart
- Frames Compared at Once: ${config.framesToCompare} frames
- Fall Detection: ${config.detectFalls}
- Fire Detection: ${config.detectFire}
- Water/Leak Detection: ${config.detectWater}
- Intrusion Detection: ${config.detectIntrusion}
- Motion Sensitivity: ${config.motionSensitivity}

RESULTS:
Total Frames Analyzed: $totalFrames
Motion Events Detected: $significantEvents
Detection Rate: ${timings.isEmpty ? 0 : ((significantEvents/timings.length)*100).toStringAsFixed(1)}%

PERFORMANCE METRICS:
Total Processing Time: ${(totalTime/1000).toStringAsFixed(2)}s
Average Time per Comparison: ${avgTime.toStringAsFixed(0)}ms
Min/Max Comparison Time: ${minTime}ms / ${maxTime}ms

BASELINE SCENE:
$baselineDescription

DETECTED EVENTS:
${events.isEmpty ? 'No significant motion or changes detected.' : events.join('\n')}

=== END OF REPORT ===
""";

    final file = File('cctv_analysis_report.txt');
    await file.writeAsString(report);
    print("CCTV analysis report saved to: cctv_analysis_report.txt");
    
    // Save just the events to a separate file for quick review
    if (events.isNotEmpty) {
      final eventsFile = File('cctv_events_log.txt');
      await eventsFile.writeAsString(events.join('\n'));
      print("Events log saved to: cctv_events_log.txt");
    }
  }
}

Future<void> main() async {
  final totalStopwatch = Stopwatch()..start();
  
  // Initialize Llama
  Llama.libraryPath = "bin/MAC_ARM64/libmtmd.dylib";

  final modelParams = ModelParams()..nGpuLayers = -1;
  final contextParams = ContextParams()
    ..nPredict = 256
    ..nThreads = -1
    ..nCtx = 8192 * 2
    ..nBatch = 8192 * 2;
  final samplerParams = SamplerParams()
    ..temp = 0.2
    ..topK = 40
    ..topP = 0.9
    ..penaltyRepeat = 1;

  print("Initializing vision model...");
  final initStopwatch = Stopwatch()..start();
  
  final llama = Llama(
    "/Users/adel/Workspace/gguf/smole/SmolVLM2-256M-Video-Instruct-f16.gguf",
    modelParams: modelParams,
    contextParams: contextParams,
    samplerParams: samplerParams,
    verbose: false,
    mmprojPath: "/Users/adel/Workspace/gguf/smole/mmproj-SmolVLM2-256M-Video-Instruct-f16.gguf",
  );
  
  initStopwatch.stop();
  print("Model initialized in ${initStopwatch.elapsedMilliseconds}ms\n");

  // Configure analysis settings - Example configurations below:
  
  // Example 1: Standard 2-frame comparison for general monitoring
  final config = CCTVAnalysisConfig(
    targetFps: 1.0,              // 2 frames per second
    comparisonWindow: 1,         // Compare frames 2 apart
    framesToCompare: 2,          // Compare 2 frames at a time
    detectFalls: true,
    detectFire: true,
    detectWater: true,
    detectIntrusion: true,
    verboseOutput: true,
    motionSensitivity: 0.3,
  );
  
  // Example 2: 3-frame comparison for better motion tracking
  // final config = CCTVAnalysisConfig(
  //   targetFps: 3.0,
  //   comparisonWindow: 1,       // Consecutive frames
  //   framesToCompare: 3,         // Compare 3 frames at once
  //   detectFalls: true,
  //   verboseOutput: true,
  //   motionSensitivity: 0.2,
  // );
  
  // Example 3: Wide-span comparison for slow changes
  // final config = CCTVAnalysisConfig(
  //   targetFps: 1.0,
  //   comparisonWindow: 5,       // Compare frames 5 apart
  //   framesToCompare: 2,         // Just compare start and end
  //   detectFire: true,
  //   detectWater: true,
  //   verboseOutput: true,
  //   motionSensitivity: 0.5,
  // );

  final analyzer = CCTVAnalyzer(llama: llama, config: config);

  try {
    await analyzer.analyzeCCTVFootage(
      videoPath: "/Users/adel/Workspace/danone_cctv/WhatsApp Video 2025-09-11 at 22.14.49.mp4",
    );

  } on LlamaException catch (e) {
    stderr.writeln("Llama error: $e");
  } finally {
    llama.dispose();
    totalStopwatch.stop();
    print("\nTotal execution time: ${(totalStopwatch.elapsedMilliseconds/1000).toStringAsFixed(2)}s");
  }
}
