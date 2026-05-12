---
name: Lowercase text rule
description: All UI text and communication must use lowercase, except where convention requires uppercase. Applies to both code UI text and conversation responses.
type: feedback
originSessionId: 1b5cb8ab-d205-4b8b-a086-f9ee9f864815
---
## Rule
All user-facing text in the app AND all conversation/communication must use lowercase. Only use uppercase where it is a technical convention.

**Why:** Consistent with the terminal aesthetic — real terminals use lowercase. The user strongly prefers this style across the board.

**How to apply:**
- UI labels, descriptions, button text, dialog text, hints → all lowercase
- Conversation responses, explanations, summaries → all lowercase
- Exceptions: `Curel` (app name/proper noun), `User-Agent` (HTTP header convention), `GET`/`POST` (HTTP methods), `JSON`/`XML` (format names), `URL`/`ID` (abbreviations), `Flutter`/`Dart` (proper nouns)
- Headers/titles like `settings`, `about`, `environments` → lowercase
- `TColors`, `Icons`, class names in code → unaffected, this is for display text only
