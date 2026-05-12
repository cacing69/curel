---
name: Always update NOTES.txt
description: Every prompt that results in code changes must be recorded in NOTES.txt as a plain text list
type: feedback
originSessionId: d406a8f4-33aa-4070-b12a-0252d4e2c1ba
---

Always update NOTES.txt after every change made during the session. After each prompt that results in code changes, append the change as a plain text list item (`- description`) to NOTES.txt.

**Why:** The user uses NOTES.txt as a changelog tracker for the session to keep track of what was done.
**How to apply:** After any edit/write action that changes functionality or fixes something, immediately update NOTES.txt with the new entry. Do not wait until the end of the conversation.

## Memory sync rule

Every time Claude memory is updated, ALWAYS also sync to project `memory/` folder. Both locations must stay identical.

**Why:** The user checks project `memory/` folder to verify memory is up to date.
**How to apply:** After writing to `~/.claude/projects/.../memory/`, also write the same file to `/Users/ibnulmutaki/Development/github/curel/memory/`.
