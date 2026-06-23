// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'test_action_models.dart';

/// Extracts frames from video at specified FPS or auto-calculated rate
/// [targetFps] - desired frames per second (null = auto-detect based on motion)
/// [minFps] - minimum fps to extract (default 0.5)
/// [maxFps] - maximum fps to extract (default 5.0 for processing efficiency)
Future<List<VideoFrame>> extractVideoFramesWithTimestamps({
  required String videoPath,
  double? targetFps,
  double minFps = 0.5,
  double maxFps = 5.0,
}) async {
  // Check ffmpeg availability
  Future<bool> exists(String exe) async =>
      (await Process.run('which', [exe])).exitCode == 0;

  final hasFfmpeg = await exists('ffmpeg');
  if (!hasFfmpeg) {
    throw StateError('ffmpeg not found on PATH. Install it first (e.g., brew install ffmpeg).');
  }

  // Get video metadata
  double? durationSec;
  double? originalFps;
  // int? totalFrames;
  
  if (await exists('ffprobe')) {
    // Get video stream info
    final probe = await Process.run('ffprobe', [
      '-v', 'error',
      '-select_streams', 'v:0',
      '-show_entries', 'stream=duration,r_frame_rate,nb_frames:format=duration',
      '-of', 'json',
      videoPath,
    ]);
    
    if (probe.exitCode == 0) {
      final probeData = json.decode(probe.stdout as String);
      final stream = probeData['streams']?[0];
      final format = probeData['format'];
      
      // Try to get duration from stream or format
      durationSec = double.tryParse(stream?['duration']?.toString() ?? '') ??
                   double.tryParse(format?['duration']?.toString() ?? '');
      
      // Parse frame rate
      final fpsStr = stream?['r_frame_rate']?.toString();
      if (fpsStr != null && fpsStr.contains('/')) {
        final parts = fpsStr.split('/');
        originalFps = double.parse(parts[0]) / double.parse(parts[1]);
      }
      
      // totalFrames = int.tryParse(stream?['nb_frames']?.toString() ?? '');
    }
  }

  // Determine extraction FPS
  double fps;
  if (targetFps != null) {
    fps = targetFps.clamp(minFps, maxFps);
  } else {
    // Auto-calculate based on video length
    if (durationSec != null && durationSec > 0) {
      if (durationSec <= 10) {
        fps = 2.0; // Short video: 2 fps
      } else if (durationSec <= 30) {
        fps = 1.0; // Medium video: 1 fps
      } else if (durationSec <= 60) {
        fps = 0.5; // Long video: 0.5 fps
      } else {
        fps = 0.25; // Very long video: 0.25 fps
      }
      fps = fps.clamp(minFps, maxFps);
    } else {
      fps = 1.0; // Default fallback
    }
  }

  print('Video info: duration=${durationSec?.toStringAsFixed(1)}s, '
        'original_fps=${originalFps?.toStringAsFixed(1)}, '
        'extraction_fps=${fps.toStringAsFixed(2)}');

  final tmpDir = await Directory.systemTemp.createTemp('test_frames_');
  print('Extracting frames to ${tmpDir.path}');
  final outPattern = '${tmpDir.path}/frame_%05d.png';

  // Extract frames without frame limit
  final ffArgs = [
    '-hide_banner',
    '-loglevel', 'error',
    '-i', videoPath,
    '-vf', 'fps=$fps,scale=1280:-1',  // Scale to max width 1280
    '-vsync', 'vfr',
    '-pix_fmt', 'rgb24',
    outPattern,
  ];

  final ff = await Process.run('ffmpeg', ffArgs);

  if (ff.exitCode != 0) {
    await tmpDir.delete(recursive: true);
    throw StateError('ffmpeg failed: ${ff.stderr}');
  }

  // Read all extracted frames
  final frames = <VideoFrame>[];
  final entries = await tmpDir.list().toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  
  int frameNum = 0;
  for (final e in entries.whereType<File>()) {
    final timestamp = frameNum / fps;
    frames.add(VideoFrame(
      imageData: await e.readAsBytes(),
      timestamp: timestamp,
      frameNumber: frameNum,
    ));
    frameNum++;
  }

  await tmpDir.delete(recursive: true);
  
  print('Extracted ${frames.length} frames');
  return frames;
}