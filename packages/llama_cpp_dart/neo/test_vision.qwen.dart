// ignore_for_file: avoid_print

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

Future<void> main() async {
  Llama.libraryPath = "bin/MAC_ARM64/libmtmd.dylib";

  final modelParams = ModelParams()..nGpuLayers = 99;

  final contextParams = ContextParams()
    ..nPredict = -1
    ..nCtx = 4096
    ..nBatch = 4096;

  final samplerParams = SamplerParams()
    ..seed = 42
    ..penaltyRepeat = 1.0
    ..temp = 0.15
    ..topP = 0.9;

  final llama = Llama(
    "/Users/adel/Workspace/gguf/gemma-3-4b-it-q4_0.gguf",
    modelParams: modelParams,
    contextParams: contextParams,
    samplerParams: samplerParams,
    verbose: false,
    mmprojPath: "/Users/adel/Workspace/gguf/mmproj-model-f16-4B.gguf",
  );

  final image = LlamaImage.fromFile(File("/Users/adel/Downloads/446254025-8b0d7e60-538c-4744-865f-8a10ea7923c1.png"));
  var prompt = """
Please first output bbox coordinates and colors of every rectangle in this image in JSON format, and then answer how many rectangles are there in the image.
""";
  prompt = """
<|im_start|>System: You are a helpful vision assistant.<end_of_utterance>
<|im_start|>User: <image> $prompt<end_of_utterance>
Assistant:
""";
  print(prompt);
  
  try {
    print("First generation:");
    final stream = llama.generateWithMedia(prompt, inputs: [image]);

    await for (final token in stream) {
      stdout.write(token);
    }
    await stdout.flush();
    stdout.writeln();
  } on LlamaException catch (e) {
    stderr.writeln("An error occurred: $e");
  }

  llama.dispose();
}
