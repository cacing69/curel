---
name: Dialog UI pattern
description: Correct styling for all AlertDialog and input fields across the app
type: feedback
---

## AlertDialog background

All `AlertDialog` must use `TColors.background`, NOT `TColors.surface`.

**Why:** Dialog contains text field containers with `TColors.surface`. If dialog bg is also `TColors.surface`, the text field blends in with no visual contrast — same as settings page where page bg is `TColors.background` and input containers are `TColors.surface`.

```dart
AlertDialog(
  backgroundColor: TColors.background, // NOT TColors.surface
  ...
)
```

## Text field in dialogs and pages

All text fields use container wrapping pattern:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  color: TColors.surface,
  child: TextField(
    decoration: InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.zero,
    ),
  ),
)
```

**Never use:** `filled: true`, `fillColor: TColors.background`, or manual `contentPadding` on TextField itself.

## Label styling

```dart
Text(label,
  style: const TextStyle(
    color: TColors.cyan,
    fontFamily: 'monospace',
    fontSize: 12,
    fontWeight: FontWeight.bold,
  ),
)
```

## How to apply

Every new dialog, popup, or page with text fields must follow this exact pattern. The visual hierarchy is always: `TColors.background` (base) → `TColors.surface` (input container) → `TColors.foreground` (text).
