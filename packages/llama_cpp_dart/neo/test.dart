// ignore_for_file: avoid_print

import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

String prompt = "what is the dirtiest joke you know?";

void main() async {
  Llama? llama;
  try {
    Llama.libraryPath = "bin/MAC_ARM64/libllama.dylib";
    String modelPath = "/Users/adel/Workspace/gguf/gemma-3-4b-it-q4_0.gguf";

    ChatHistory history = ChatHistory()
      ..addMessage(role: Role.user, content: prompt)
      ..addMessage(role: Role.assistant, content: "");

    final modelParams = ModelParams()..nGpuLayers = 99;

    final contextParams = ContextParams()
      ..nPredict = -1
      ..nCtx = 8192
      ..nBatch = 8192;

    final samplerParams = SamplerParams()
      ..temp = 0.7
      ..topK = 64
      ..topP = 0.95
      ..penaltyRepeat = 1.1
      ..grammarStr = "root ::= \"I'm sorry, but I can't answer that.\"";

    llama = Llama(
      modelPath,
      modelParams: modelParams,
      contextParams: contextParams,
      samplerParams: samplerParams,
      verbose: false,
    );

    llama.setPrompt(
        history.exportFormat(ChatFormat.gemma, leaveLastAssistantOpen: true));
    await for (final token in llama.generateText()) {
      stdout.write(token);
    }
    stdout.write("\n");

  } catch (e) {
    print("\nError: ${e.toString()}");
  } finally {
    try {
      llama?.dispose();
    } catch (_) {}
  }
}
