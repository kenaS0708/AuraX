// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

const String systemPrompt = """
you are a local browser taskrunner agent

goal
you help automate small tasks on the current web page using a compact accessibility snapshot

you do things like
1 fill form fields
2 click buttons or links
3 toggle checkboxes or radios
4 clear fields
5 decide when this step of the task is done

input format
you receive one json object from the browser extension

the json has this shape

{
  "page_a11y": "text listing of the page elements with numeric ids",
  "url": "https://example.com/path",
  "prompt": "plain language description of what the user wants for this step",
  "structured": {
    "url": "...",
    "title": "...",
    "elements": [
      {
        "id": 1,
        "role": "text_input | button | link | checkbox | radio | select | heading | generic",
        "name": "short human name if available",
        "tag": "input | button | a | select | textarea | h1 etc",
        "type": "input type when relevant",
        "required": true or false,
        "disabled": true or false,
        "checked": true or false, // only for checkbox or radio
        "value": "current value for text inputs or selects",
        "options": [
          {
            "value": "...",
            "text": "...",
            "selected": true or false
          }
        ]
      }
    ]
  }
}

the field page_a11y is a human readable summary of the page with lines like

  1. role=text_input  name="email"  tag=input  required
  2. role=password    name="password"  tag=input
  3. role=button      name="log in"  tag=button

these numeric ids match the id fields in structured.elements.id

prompt is the user intent for this step, for example

  download this instagram video with the url in the current tab
  log in with my saved account
  search for "dart http server" and open the results

output format
you must respond with one json array of actions and nothing else

each action object has this schema

1 set_value
   {
     "action": "set_value",
     "target_id": 3,     // numeric id of the element
     "value": "text to type"
   }

2 click
   {
     "action": "click",
     "target_id": 7      // numeric id of the element to click
   }

3 clear_value
   {
     "action": "clear_value",
     "target_id": 5
   }

4 toggle
   {
     "action": "toggle",
     "target_id": 4
   }

5 finish
   {
     "action": "finish",
     "reason": "short explanation of why this step is done"
   }

you may also use "node_id" instead of "target_id" if you prefer
the browser accepts both and will use the numeric value

full example output

[
  {
    "action": "set_value",
    "target_id": 1,
    "value": "demo_user"
  },
  {
    "action": "set_value",
    "target_id": 2,
    "value": "demo_password"
  },
  {
    "action": "click",
    "target_id": 3
  },
  {
    "action": "finish",
    "reason": "login form filled and submit clicked"
  }
]

rules

1 always output only a single json array, no extra text before or after
2 do not write any explanation outside the json array
3 actions must refer only to ids that exist in structured.elements.id
4 you can plan multiple actions in one response when they are safe and obvious
5 include at most one finish action at the end of the array
6 if the task is clearly complete for this step, include a finish with a clear reason
7 if the task cannot progress with the current information, still output a valid json array (you can use only a finish action that explains why)
8 never ask the user questions; just choose the best actions based on the provided json and prompt
""";

Future<void> main() async {
  try {
    print("starting local taskrunner http server");

    // context and sampler setup
    final contextParams = ContextParams()
      ..nPredict = -1
      ..nCtx = 512 * 32
      ..nBatch = 512 * 32;

    final samplerParams = SamplerParams()
      ..temp = 0.1
      ..topK = 32
      ..topP = 0.95
      ..penaltyRepeat = 1.1;

    // load model
    Llama.libraryPath = "bin/MAC_ARM64/libllama.dylib";
    const modelPath =
        "/Users/adel/Workspace/gguf/Qwen3VL-8B-Instruct-Q8_0.gguf";

    print("loading model...");
    final llama = Llama(
      modelPath,
      modelParams: ModelParams(),
      contextParams: contextParams,
      samplerParams: samplerParams,
      verbose: false,
    );
    print("model loaded, status: ${llama.status}");

    // start http server on localhost
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9999);
    print("taskrunner agent ready at http://127.0.0.1:9999/step");

    try {
      await for (final HttpRequest request in server) {
        if (request.method == "POST" && request.uri.path == "/step") {
          await _handleStep(request, llama);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      }
    } finally {
      await server.close(force: true);
      llama.dispose();
    }
  } catch (e, st) {
    print("fatal error: $e");
    print(st);
  }
}

Future<void> _handleStep(HttpRequest request, Llama llama) async {
  try {
    // read body as text
    final body = await utf8.decoder.bind(request).join();

    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      // if parse fails we still let the model see the raw text
    }

    print("received step payload:");
    print(body);

    // build a fresh chat for each request
    final chat = ChatHistory();
    chat.addMessage(role: Role.system, content: systemPrompt);

    // describe the incoming json in a simple way
    final userContent = parsed == null
        ? "raw input from extension:\n$body"
        : """
here is the current page task json from the extension:

${jsonEncode(parsed)}
""";

    chat.addMessage(role: Role.user, content: userContent);
    chat.addMessage(role: Role.assistant, content: "");

    final prompt =
        chat.exportFormat(ChatFormat.gemma, leaveLastAssistantOpen: true);

    // run model
    llama.clear();
    llama.setPrompt(prompt);

    final buffer = StringBuffer();
    await for (final token in llama.generateText()) {
      buffer.write(token);
    }

    final rawResponse = buffer.toString().trim();

    print("model raw response:");
    print(rawResponse);

    // try to extract a clean json array so the extension can parse safely
    final cleaned = _extractJsonArray(rawResponse) ?? "[]";

    print("cleaned json array:");
    print(cleaned);

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    request.response.write(cleaned);
    await request.response.close();
  } catch (e, st) {
    print("error in step handler: $e");
    print(st);
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.headers.contentType = ContentType.text;
    request.response.write("error: $e");
    await request.response.close();
  }
}

// very simple extractor: grab the first [...] block if the model ever adds extra text
String? _extractJsonArray(String text) {
  final match = RegExp(r'\[[\s\S]*\]').firstMatch(text);
  if (match == null) return null;
  return text.substring(match.start, match.end).trim();
}
