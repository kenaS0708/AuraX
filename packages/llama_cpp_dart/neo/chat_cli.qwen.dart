// ignore_for_file: avoid_print

import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() async {
  Llama? llama;
  try {
    print("Starting LLM CLI Chat App...");

    // Initialize model parameters
    ContextParams contextParams = ContextParams();
    contextParams.nPredict = -1;
    contextParams.nCtx = 1024 * 6;
    contextParams.nBatch = 1024 * 6;

    final samplerParams = SamplerParams();
    samplerParams.temp = 0.7;
    samplerParams.topK = 64;
    samplerParams.topP = 0.95;
    samplerParams.penaltyRepeat = 1.1;

    // Load the LLM model
    print("Loading model, please wait...");
    Llama.libraryPath = "bin/MAC_ARM64/libllama.dylib";
    String modelPath = "/Users/adel/Workspace/gguf/Qwen3-30B-A3B-Thinking-2507-Q4_K_S.gguf";
    llama = Llama(
      modelPath,
      modelParams: ModelParams(),
      contextParams: contextParams,
      samplerParams: samplerParams,
      verbose: true,
    );
    print("Model loaded successfully! ${llama.status}");

    // Initialize chat history with system prompt
    ChatHistory chatHistory = ChatHistory();
    chatHistory.addMessage(role: Role.system, content: """
You are a helpful, concise assistant. Keep your answers informative but brief.""");

    print("\n=== Chat started (type 'exit' to quit) ===\n");

    // Chat loop
    bool chatActive = true;
    while (chatActive) {
      // Get user input
      stdout.write("\nYou: ");
      String? userInput = stdin.readLineSync();

      // Check for exit command
      if (userInput == null || userInput.toLowerCase() == 'exit') {
        chatActive = false;
        print("\nExiting chat. Goodbye!");
        break;
      }

      // Add user message to history
      chatHistory.addMessage(role: Role.user, content: userInput);

      // Add empty assistant message that will be filled by the model
      chatHistory.addMessage(role: Role.assistant, content: "");

      // Prepare prompt for the model
      // String prompt = chatHistory.exportFormat(ChatFormat.gemini,
      //    leaveLastAssistantOpen: true);
      // String prompt = chatHistory.exportFormat(ChatFormat.alpaca);
      String prompt = chatHistory.exportFormat(ChatFormat.chatml);

      // Send to model
      llama.setPrompt(prompt);

      // Collect the response
      stdout.write("\nAssistant: ");
      StringBuffer responseBuffer = StringBuffer();

      await for (final token in llama.generateText()) {
        final incoming = responseBuffer.toString() + token;

        if (incoming.contains("<end_of_turn>")) {
          final clean = incoming.split("<end_of_turn>").first;
          final newSegment = clean.substring(responseBuffer.length);
          if (newSegment.isNotEmpty) {
            stdout.write(newSegment);
          }
          responseBuffer
            ..clear()
            ..write(clean);
          break;
        }

        stdout.write(token);
        responseBuffer.write(token);
      }

      // Update the last assistant message with the generated content
      String assistantResponse = responseBuffer.toString();
      chatHistory.messages.last =
          Message(role: Role.assistant, content: assistantResponse);

      print(""); // Add a newline after the response
    }

    // Clean up
  } catch (e) {
    print("\nError: ${e.toString()}");
  } finally {
    try {
      llama?.dispose();
    } catch (_) {}
  }
}
