// ignore_for_file: avoid_print

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'extract_video_frames.dart';
import 'test_action_models.dart';

class CCTVAnalyzer {
  final Llama llama;

  CCTVAnalyzer({required this.llama});

  /// Analyzes CCTV footage focusing on changes and movement
  Future<void> analyzeCCTVFootage({
    required String videoPath,
    double targetFps = 0.5,
    int comparisonWindowSize = 3,
    bool verbose = false,
  }) async {
    if (verbose) print("Extracting frames from CCTV footage...");
    
    final frames = await extractVideoFramesWithTimestamps(
      videoPath: videoPath,
      targetFps: targetFps,
      minFps: 0.25,
      maxFps: 60.0,
    );

    if (frames.isEmpty) {
      throw StateError('No frames extracted from video');
    }

    print("Extracted ${frames.length} frames at $targetFps fps\n");
    print("=== CCTV MOTION DETECTION ANALYSIS ===\n");
    
    // First, establish the baseline (static background)
    print("Establishing baseline scene...");
    final baselineStopwatch = Stopwatch()..start();
    final baselineDescription = await _describeBaseline(frames.first);
    baselineStopwatch.stop();
    
    print("Baseline (${baselineStopwatch.elapsedMilliseconds}ms):");
    print(baselineDescription);
    print("=" * 60);
    
    // Now analyze changes from the baseline
    final events = <String>[];
    final timings = <int>[];
    int totalTime = 0;
    int significantEvents = 0;
    
    for (int i = 1; i < frames.length; i++) {
      final currentFrame = frames[i];
      final previousFrame = frames[i - 1];
      final timestamp = currentFrame.timestamp;
      
      if (verbose) {
        final progress = ((i + 1) / frames.length * 100).toStringAsFixed(1);
        print("\nAnalyzing frame ${i + 1}/${frames.length} at ${timestamp.toStringAsFixed(1)}s ($progress%)");
      }

      // Start timing
      final stopwatch = Stopwatch()..start();
      
      // Detect changes between frames
      final changes = await _detectChanges(
        previousFrame: previousFrame,
        currentFrame: currentFrame,
        frameNumber: i + 1,
      );
      
      stopwatch.stop();
      final elapsedMs = stopwatch.elapsedMilliseconds;
      timings.add(elapsedMs);
      totalTime += elapsedMs;
      
      // Only report if there are significant changes
      if (changes.contains("NO_CHANGE") || changes.contains("no significant") || changes.contains("static")) {
        if (verbose) {
          print("[${timestamp.toStringAsFixed(1)}s] No significant changes (${elapsedMs}ms)");
        }
      } else {
        significantEvents++;
        final eventLog = "[${timestamp.toStringAsFixed(1)}s] Frame ${i + 1}: $changes";
        
        print("\n🔴 MOTION DETECTED at ${timestamp.toStringAsFixed(1)}s (${elapsedMs}ms):");
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

  /// Describe the baseline static scene (Gemma format)
  Future<String> _describeBaseline(VideoFrame frame) async {
    final input = LlamaImage.fromBytes(frame.imageData);

    final prompt = """<start_of_turn>user
<image>
You are a CCTV scene analyzer. Describe the static background environment.
Focus on:
- Location type (warehouse, office, street, etc.)
- Fixed objects and their positions
- Lighting conditions
- Camera angle and coverage area
Do NOT describe any people or moving objects.
<start_of_turn>model
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

  /// Detect changes between two frames (Gemma format)
  Future<String> _detectChanges({
    required VideoFrame previousFrame,
    required VideoFrame currentFrame,
    required int frameNumber,
  }) async {
    final inputs = [
      LlamaImage.fromBytes(previousFrame.imageData),
      LlamaImage.fromBytes(currentFrame.imageData),
    ];

    final prompt = """<start_of_turn>user
<image>
<image>
You are a CCTV motion detector. Compare these two consecutive frames.
ONLY report:
- New people entering or leaving the scene
- Movement of people (walking, running, falling)
- Objects being moved, added, or removed
- Safety concerns (fire, smoke, water, accidents)
- Suspicious behavior

If nothing significant changed, respond with "NO_CHANGE".
Focus ONLY on what changed, not the static background.
What changed between frame 1 and frame 2?
<start_of_turn>model
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

  /// Alternative: Analyze multiple frames for activity patterns (Gemma format)
  // ignore: unused_element
  Future<String> _analyzeActivityPattern(List<VideoFrame> frames) async {
    final inputs = frames.map((f) => LlamaImage.fromBytes(f.imageData)).toList();
    final imageTags = List.filled(inputs.length, '<image>').join('\n');

    final prompt = """<start_of_turn>user
$imageTags
You are a CCTV activity analyzer. These frames show a sequence over time.
Describe:
1. Overall activity pattern (busy/quiet/suspicious)
2. Number of people and their movements
3. Any concerning patterns or safety issues
4. Time periods of high/low activity
Focus on movement and changes, not static elements.
Analyze the activity pattern across these frames.
<start_of_turn>model
""";

    try {
      final response = StringBuffer();
      final stream = llama.generateWithMedia(prompt, inputs: inputs);
      
      await for (final token in stream) {
        response.write(token);
      }
      
      return response.toString().trim();
    } catch (e) {
      return "Error analyzing activity pattern";
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
    print("Average time per frame: ${avgTime.toStringAsFixed(0)}ms");
    print("========================\n");

    final report = """
=== CCTV FOOTAGE ANALYSIS REPORT ===
Video: $videoPath
Analysis Time: ${DateTime.now()}
Total Frames Analyzed: $totalFrames
Motion Events Detected: $significantEvents
Detection Rate: ${((significantEvents/totalFrames)*100).toStringAsFixed(1)}%

PERFORMANCE METRICS:
Total Processing Time: ${(totalTime/1000).toStringAsFixed(2)}s
Average Time per Frame: ${avgTime.toStringAsFixed(0)}ms
Min/Max Frame Time: ${minTime}ms / ${maxTime}ms

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
  
  // Initialize Llama with Gemma model
  Llama.libraryPath = "bin/MAC_ARM64/libmtmd.dylib";

  final modelParams = ModelParams()..nGpuLayers = 99;  // Use GPU layers like in your example
  
  final contextParams = ContextParams()
    ..nPredict = -1
    ..nThreads = -1
    ..nCtx = 8192
    ..nBatch = 8192;
    
  final samplerParams = SamplerParams()
    ..temp = 0.2  // Lower for more consistent detection
    ..topK = 64
    ..topP = 0.95
    ..penaltyRepeat = 1.1;

  print("Initializing Gemma vision model...");
  final initStopwatch = Stopwatch()..start();
  
  final llama = Llama(
    "/Users/adel/Workspace/gguf/gemma-3-4b-it-q4_0.gguf",
    modelParams: modelParams,
    contextParams: contextParams,
    samplerParams: samplerParams,
    verbose: false,
    mmprojPath: "/Users/adel/Workspace/gguf/mmproj-model-f16-4B.gguf",
  );
  
  initStopwatch.stop();
  print("Model initialized in ${initStopwatch.elapsedMilliseconds}ms\n");

  final analyzer = CCTVAnalyzer(llama: llama);

  try {
    await analyzer.analyzeCCTVFootage(
      videoPath: "/Users/adel/Workspace/danone_cctv/WhatsApp Video 2025-09-11 at 22.14.49.mp4",
      targetFps: 1.0,  // Check once per second
      comparisonWindowSize: 2,  // Compare consecutive frames
      verbose: true,
    );

  } on LlamaException catch (e) {
    stderr.writeln("Llama error: $e");
  } finally {
    llama.dispose();
    totalStopwatch.stop();
    print("\nTotal execution time: ${(totalStopwatch.elapsedMilliseconds/1000).toStringAsFixed(2)}s");
  }
}
