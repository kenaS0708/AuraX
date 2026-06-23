// ignore_for_file: avoid_print

// import 'package:ffi/ffi.dart';
// import 'package:ffi/ffi.dart' as ffi;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() async {

  // Library path setup
  Llama.libraryPath =
      "/Users/adel/Workspace/llama_cpp_dart/bin/MAC_ARM64/libmtmd.dylib";

  ContextParams contextParams = ContextParams();
    contextParams.embeddings = true;

  final llama = Llama(
    "/Users/adel/Downloads/bge-m3-q4_k_m.gguf",
    modelParams: ModelParams(),
    contextParams: contextParams,
    samplerParams: SamplerParams(),
    verbose: false,
  );

  const text =
      """一旦您通過了筆試和路試，考官將拿走你的暫准駕駛執照 (P牌) (綠色)。你的正式駕駛執照 (粉紅色) 將通過郵寄寄到你的家中。They say it can take up to three weeks, but the full licence normally comes within a week.""";

  final tokens = llama.tokenize(
    text,
    true,
  );

  print("token count (Dart): ${tokens.length}");
  print(tokens);
}
