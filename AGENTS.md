# AGENTS.md — Project Rules & Conventions

## Dialog Action Buttons
- All dialog control bars must use `TermButton` from `lib/presentation/widgets/term_button.dart`.
- For outlined/bordered style (dialog footer actions), use `TermButton(bordered: true, color: ..., ...)`.
- Do NOT create local button widgets (`_ActionButton`, `_footerButton`, `_btn`, etc.) in dialog files.

## `TermButton` API
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `label` | `String?` | — | Button text |
| `icon` | `IconData?` | — | Optional leading icon |
| `onTap` | `VoidCallback?` | — | Callback; `null` = disabled state |
| `accent` | `bool` | `false` | Green tinted background (filled) / green color (bordered) |
| `fullWidth` | `bool` | `false` | Stretch to parent width |
| `bordered` | `bool` | `false` | Outlined style (border, transparent bg) |
| `color` | `Color?` | — | Override text/icon/border color |

## Dialog Control Bar Pattern
```dart
Container(
  padding: EdgeInsets.all(12),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      TermButton(
        label: 'cancel',
        onTap: () => Navigator.pop(context),
        color: TColors.comment,
        bordered: true,
      ),
      SizedBox(width: 12),
      TermButton(
        label: 'action',
        onTap: _doSomething,
        color: TColors.green,
        icon: Icons.check,
        bordered: true,
      ),
    ],
  ),
)
```

## Dialog Footer Rules
- Footer always has `cancel` on the left and the primary action on the right.
- `Row(mainAxisAlignment: MainAxisAlignment.end, ...)` — right-align both buttons.
- Disabled primary action: `onTap: null` (TermButton auto-dims).
- Bulk/contextual actions (e.g. "use local for all") go in sidebar header or toolbar, NOT in the footer.

## Dialog Preview Layout
- Conflict resolution preview: vertical stacked (local top, remote bottom) — each takes 50% via `Expanded` in `Column`.
- **Never** wrap a dialog footer `Row` containing `Spacer()` or `Expanded` in `SingleChildScrollView(scrollDirection: Axis.horizontal)` — unbounded width causes layout assertion crash.

## Code Style
- Avoid adding comments unless asked.
- Use `TColors.*` theme colors consistently — never hardcode colors.
- Font: `'monospace'`, sizes typically 10–13.
- Lowercase labels for dialog buttons.
- Prefer editing existing files over creating new ones.
- Check `PLAN.md` before implementing new features.
