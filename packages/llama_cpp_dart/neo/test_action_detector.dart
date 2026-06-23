// ignore_for_file: avoid_print

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'extract_video_frames.dart';
import 'test_action_models.dart';

class VideoSceneAnalyzer {
  final Llama llama;

  VideoSceneAnalyzer({required this.llama});

  /// Analyzes a video and describes what is seen in each frame/batch
  Future<String> analyzeVideoScenes({
    required String videoPath,
    double? targetFps,
    bool verbose = false,
  }) async {
    if (verbose) print("Extracting frames from video...");

    final frames = await extractVideoFramesWithTimestamps(
      videoPath: videoPath,
      targetFps: targetFps ?? 1.0, // Default to 1 fps for scene analysis
      minFps: 0.25,
      maxFps: 60.0,
    );

    if (frames.isEmpty) {
      throw StateError('No frames extracted from video');
    }

    if (verbose) {
      print("Analyzing ${frames.length} frames for scene descriptions...");
    }

    final sceneDescriptions = <String>[];

    // Analyze each frame individually to see what the model detects
    for (int i = 0; i < frames.length; i++) {
      final frame = frames[i];
      
      if (verbose) {
        final progress = ((i / frames.length) * 100).toStringAsFixed(1);
        print("Processing frame ${i + 1} of ${frames.length} ($progress%)");
      }

      final description = await _describeFrame(frame);
      
      final timestamp = frame.timestamp;
      final sceneInfo = """
[${timestamp.toStringAsFixed(1)}s] Frame ${i + 1}:
$description
""";
      
      sceneDescriptions.add(sceneInfo);
      
      // Print immediately so you can see what it detects as it processes
      print("\n$sceneInfo");
    }

    // Compile full report
    final fullReport = """
=== VIDEO SCENE ANALYSIS REPORT ===
Video: $videoPath
Total Frames Analyzed: ${frames.length}
Frame Rate: ${targetFps ?? 1.0} fps

SCENE DESCRIPTIONS:
${'-' * 50}
${sceneDescriptions.join('\n')}

=== END OF REPORT ===
""";

    return fullReport;
  }

  /// Describes what is visible in a single frame
  Future<String> _describeFrame(VideoFrame frame) async {
    final input = LlamaImage.fromBytes(frame.imageData);

    // Simple, open-ended prompt to see everything the model can detect
    final prompt = """
<|im_start|>System: You are a visual scene analyzer. Describe everything you see in detail.
Include:
- Objects and their positions
- People (if any) and what they're doing
- Environment/setting
- Any text visible
- Colors and lighting
- Any potential safety concerns (fire, water, falls, etc.)
Be thorough and specific.
<end_of_utterance>
User:<image>
Describe everything you see in this image.
<end_of_utterance>
Assistant:
""";

    try {
      final response = StringBuffer();
      final stream = llama.generateWithMedia(prompt, inputs: [input]);
      
      stdout.write("[ANALYZING] ");
      await for (final token in stream) {
        response.write(token);
        stdout.write(token);
      }
      await stdout.flush();
      stdout.writeln();
      
      return response.toString().trim();
    } catch (e) {
      print("Error analyzing frame: $e");
      return "Error: Could not analyze this frame";
    }
  }

  /// Alternative method for batch processing if you want to compare multiple frames
  Future<String> compareBatchFrames(List<VideoFrame> batch) async {
    final inputs = batch.map((f) => LlamaImage.fromBytes(f.imageData)).toList();
    final imageTags = List.filled(inputs.length, '<image>').join(' ');

    final prompt = """
<|im_start|>System: You are a visual scene analyzer. Compare these frames and describe:
1. What stays the same across frames
2. What changes between frames
3. Any movement or action detected
4. Any safety concerns (fire, smoke, water, people falling, etc.)
<end_of_utterance>
User:$imageTags
Compare and describe what you see across these frames.
<end_of_utterance>
Assistant:
""";

    try {
      final response = StringBuffer();
      final stream = llama.generateWithMedia(prompt, inputs: inputs);
      
      stdout.write("[COMPARING BATCH] ");
      await for (final token in stream) {
        response.write(token);
        stdout.write(token);
      }
      await stdout.flush();
      stdout.writeln();
      
      return response.toString().trim();
    } catch (e) {
      print("Error in batch analysis: $e");
      return "Error analyzing batch";
    }
  }
}

Future<void> main() async {
  // Your Llama initialization
  Llama.libraryPath = "bin/MAC_ARM64/libmtmd.dylib";

  final modelParams = ModelParams()..nGpuLayers = -1;
  final contextParams = ContextParams()
    ..nPredict = -1
    ..nThreads = -1
    ..nCtx = 8192 * 2
    ..nBatch = 8192 * 2;
  final samplerParams = SamplerParams()
    ..temp = 0.3  // Slightly higher temp for more descriptive output
    ..topK = 40
    ..topP = 0.9
    ..penaltyRepeat = 1;

  final llama = Llama(
    "/Users/adel/Workspace/gguf/smole/SmolVLM2-2.2B-Instruct-Q8_0.gguf",
    modelParams: modelParams,
    contextParams: contextParams,
    samplerParams: samplerParams,
    verbose: false,
    mmprojPath: "/Users/adel/Workspace/gguf/smole/mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf",
  );

  final analyzer = VideoSceneAnalyzer(llama: llama);

  try {
    print("Starting video scene analysis...\n");
    
    // Analyze with scene descriptions
    final sceneReport = await analyzer.analyzeVideoScenes(
      videoPath: "/Users/adel/Workspace/danone_cctv/WhatsApp Video 2025-09-11 at 22.14.49.mp4",
      targetFps: 0.5,  // Analyze every 2 seconds to start
      verbose: true,
    );

    // Save the full report
    final outputFile = File('video_scene_analysis.txt');
    await outputFile.writeAsString(sceneReport);
    print("\n\nFull analysis saved to: video_scene_analysis.txt");

    // Optional: Test batch comparison on a few frames
    print("\n\nTesting batch frame comparison...");
    final frames = await extractVideoFramesWithTimestamps(
      videoPath: "/Users/adel/Workspace/danone_cctv/WhatsApp Video 2025-09-11 at 22.14.49.mp4",
      targetFps: 2.0,
      minFps: 0.25,
      maxFps: 60.0,
    );
    
    if (frames.length >= 3) {
      final batchComparison = await analyzer.compareBatchFrames(
        frames.sublist(0, 3)  // Compare first 3 frames
      );
      print("\nBatch Comparison Result:\n$batchComparison");
    }

  } on LlamaException catch (e) {
    stderr.writeln("Llama error: $e");
  } finally {
    llama.dispose();
  }
}
