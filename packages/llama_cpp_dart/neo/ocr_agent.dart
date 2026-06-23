import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

Future<void> main() async {
  Llama.libraryPath = "bin/MAC_ARM64/libmtmd.dylib";

  final modelParams = ModelParams()..nGpuLayers = 99;

  final contextParams = ContextParams()
    ..nPredict = -1
    ..nCtx = 8192
    ..nBatch = 8192;

  final samplerParams = SamplerParams()
    ..temp = 0.7
    ..topK = 64
    ..topP = 0.95
    ..penaltyRepeat = 1.1;

  final llama = Llama(
    "/Users/adel/Workspace/gguf/cipher-Q8_0.gguf",
    modelParams: modelParams,
    contextParams: contextParams,
    samplerParams: samplerParams,
    verbose: false,
    mmprojPath: "/Users/adel/Workspace/gguf/cipher-mmproj.gguf",
  );

  final image = LlamaImage.fromFile(File(
      "/Users/adel/Downloads/DASA-Statement-1.png"));
  final history = ChatHistory();
  history.addMessage(role: Role.user, content: "<image> ما هي العملة المتسعملى في هدا كشق حساب?");
  final prompt = history.exportFormat(ChatFormat.gemma, leaveLastAssistantOpen: true);

  try {
    final stream = llama.generateWithMedia(prompt, inputs: [image]);

    await for (final token in stream) {
      stdout.write(token);
    }
    await stdout.flush();
    stdout.writeln();
  } on LlamaException catch (e) {
    stderr.writeln("An error occurred: $e");
  } finally {
    llama.dispose();
  }
}
