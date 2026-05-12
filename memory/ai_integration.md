---
name: AI Integration Architecture (BYOK)
description: AI features with Bring Your Own Key — response summarization, curl generation, prompt templates
type: project
---

## AI Integration (BYOK)

**Concept:** Users bring their own API key (OpenAI, Anthropic, etc.) — no server-side proxy, no shared quota, no usage tracking. Curel calls the AI provider directly from the device.

### Core Architecture

```
UI Layer
  ├── SummarizeButton (response viewer toolbar)
  ├── CurlGeneratorDialog (natural language input -> curl)
  ├── AIChatPanel (conversational panel alongside editor)
  └── PromptTemplateEditor (manage .prompt.md files)
        │
        v
AI Service Layer
  ├── AIProvider (abstract interface)
  │     ├── OpenAIProvider (GPT-4o, GPT-4o-mini, etc.)
  │     ├── AnthropicProvider (Claude Sonnet, Haiku, etc.)
  │     └── (extensible — user can add custom OpenAI-compatible endpoint)
  │
  ├── PromptService (load/render prompt templates with context)
  │     ├── Built-in templates (summarize, curl-generate, explain)
  │     └── User templates from filesystem (templates/*.prompt.md)
  │
  └── AIKeyService (FlutterSecureStorage — one key per provider)
```

### BYOK Provider Interface

```dart
abstract class AIProvider {
  String get id;           // 'openai', 'anthropic'
  String get displayName;  // 'OpenAI', 'Anthropic'
  Future<String> complete(String systemPrompt, String userMessage);
  Future<bool> validateKey(String apiKey);
}
```

- `validateKey()` called on save to verify the key works (cheapest/fastest model)
- Provider registry in `lib/data/services/ai/ai_provider_registry.dart`
- Each provider fetched via Dio (consistent with existing HTTP architecture)

### Key Storage

- FlutterSecureStorage, keyed by provider ID: `ai_key_openai`, `ai_key_anthropic`
- Never stored in filesystem or git — BYOK means user owns their key

### Prompt Template System

- Built-in templates compiled into the app (fallback)
- User templates stored in `{workspace}/templates/*.prompt.md`
- Template format with `{{variable}}` placeholders:
  ```
  You are an API assistant. Summarize the following JSON response from
  a `{{method}} {{path}}` request concisely in {{language}}.

  Response:
  ```json
  {{responseBody}}
  ```
  ```
- Variables filled by PromptService before sending to AI

### Use Cases

1. **Response Summarizer**
   - Button in response viewer toolbar (between copy and snippet)
   - Sends response body + request context (method, path, status) to AI
   - Returns plain-text summary shown in a bottom sheet / inline panel
   - Language follows app locale or user preference

2. **Curl Generator**
   - Dialog triggered from "+" menu or editor toolbar
   - User types: "POST /api/login with email and password, return token"
   - AI returns a curl command — auto-filled into editor
   - User can iterate: "add an Authorization header" -> refines the command

3. **AI Chat Panel**
   - Optional side panel / bottom sheet in the editor view
   - Conversational context includes current request + last response
   - User can ask: "why did this return 403?", "add pagination params", "convert to multipart form"

### Future Considerations

- Streaming support (SSE) for real-time chat experience
- Local AI via llama.cpp / Ollama for fully offline usage (BYOK extended to BYOM — Bring Your Own Model)
- Prompt versioning — store prompt hash alongside generated output for reproducibility
