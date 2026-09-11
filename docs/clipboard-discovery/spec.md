# Clipboard discovery and presentation

Status: expanded colors, Links, compact filter pills, and current-type two-line rows are implemented. Remaining discovery work stays queued; the prioritized actions feature is implemented, verified, and reviewed.
Last updated: 2026-09-11
Branch: `feat/clipboard-discovery`

## What

Improve Clipboard Plus with the visible filter pills, informative result rows,
structured/fuzzy search, and richer previews explored in
[alanfortlink/clipboard-history](https://github.com/alanfortlink/clipboard-history).
Keep our inline editor, keyboard workflow, and lightweight stock-history integration.
The implementation sequence is in [plan.md](plan.md).

The user prioritized [searchable contextual actions](../clipboard-actions/spec.md)
on 2026-09-10. That feature is now implemented, verified, and reviewed.
The requirements below remain the contract for later discovery work,
not prerequisites for the actions menu.

## Requirements

### Isolation and compatibility

- Develop on the local feature branch only. Do not push, merge into `main`, open
  marketplace requests, trigger marketplace workflows, bump `manifest.json`'s
  version, or update the installed plugin without separate explicit authorization.
- Continue using stock `omarchy.clipboard`, its history format, and packaged action
  helpers. Add no capture watcher, persistent service, runtime package, or network
  request for this feature.
- Preserve original clipboard payloads and disk indices. Classification and display
  formatting must never rewrite what paste/copy/open receives.
- Preserve bounded history loading, oversized placeholders, write confirmation,
  local-image validation, and plain-text treatment of untrusted clipboard content.

### Filters, rows, and search

- Show clickable All, Text, Links, Images, Files, Code, JSON, and Colors pills.
  Map `Ctrl+1` through `Ctrl+5` to the current All/Text/Links/Images/Colors order.
  Retain filter cycling and all existing navigation/editor shortcuts.
- Current filter slice: add Links and show working All, Text, Links, Images, and
  Colors pills below search. Use a compact 24-pixel target height with readable
  text and theme scaling. Do not expose placeholder categories. Preserve the
  query when changing pills, keep keyboard focus, and reveal the active pill when
  the strip overflows. Dedicated Files/Code/JSON filters and result counts follow.
- Links are complete trimmed `http://`/`https://` values or bare-domain values
  supported by the packaged opener, limited to 8,192 code units. Embedded URLs,
  multiple values, unsafe delimiters, and incomplete values remain Text. Classify
  without network access; show the actual host in the subtitle, omitting userinfo
  and port. Retain original text for every action. Links are excluded from Text.
- Show the full matching-entry count independently of the 60-row display limit;
  show `60 shown / 85 matches` when capped. Per-category counts are not required
  for this initial implementation.
- Add type icons and a muted subtitle. Use only available/derived information:
  words and lines for text, type, link domain, file basename/directory/count,
  and validated image MIME. Do not fabricate app names, copy ages, or image sizes.
- Use a consistent icon column: shared rounded frames around type icons, inset
  smaller color swatches, and image thumbnails. List color swatches have no separate
  inner border. Images keep their original corners with a 3-pixel theme-scaled
  inset; preserve aspect ratio without rounded clipping.
  Missing images retain a framed type icon. Center the divider so results and
  previews have equal width; preserve the card's original width.
  Derive height from the largest complete row count below the existing theme-scaled
  640-pixel ceiling and available logical screen height. Include actual border/padding,
  search, pills, footer, and spacing measurements; do not hard-code a monitor height.
  Height must not depend on result count, query, selection, or scroll position.
  Keep smooth scrolling unchanged: no row stepping, snapping, or new input handlers.
  Partial rows can still occur at intermediate scroll offsets. If even one row and
  the controls cannot fit, retain the screen-fitting height instead of overflowing it.
- Count whitespace-delimited words and logical lines over complete retained text.
  CRLF counts as one line break; CR, LF, and Unicode line/paragraph separators also
  break lines. A trailing break leaves an empty final line. Oversized placeholders
  have no known word/line counts.
- Classify standalone links, file URI entries, bounded valid JSON, conservative
  code-like text, images, and colors. Text is the fallback category, not a union
  of all text-derived categories. A single copied image file belongs to Images;
  other file URI entries belong to Files.
- Support case-insensitive fuzzy subsequence matching with whitespace-separated
  AND terms and `type:` tokens. Preserve history order rather than relevance-sort.
- Pills and recognized type tokens represent one effective category. Clicking a
  pill replaces recognized type tokens while preserving ordinary search terms;
  All removes them. The last recognized type token wins. Typing/removing tokens
  updates the active pill. Accept the singular/plural forms of visible categories;
  an unknown token remains ordinary searchable text.
- Highlight every matched ordinary term in the visible title where applicable.
  Metadata-only matches need not highlight the title. Clipboard markup must remain
  inert; do not enable unescaped QML rich/styled text to implement highlighting.
- Retain the existing 8,192-code-unit search prefix and oversized-entry behavior.
  Compute reusable classification/count metadata when history changes, not by
  repeatedly parsing/counting the complete payload on every keystroke.

### Color formats and preview

Recognize an entire trimmed color value, case-insensitively; preserve its original
text, whitespace, and spelling when copying, pasting, or editing:

- Six- and eight-digit hex, with or without `#`; alpha is the last CSS component.
- CSS `#RGB` and `#RGBA`; short hex requires `#` to avoid classifying ordinary words.
- `rgb()` and `rgba()`: numeric or percentage channels, legacy comma notation,
  and modern space notation with optional slash alpha.
- `hsl()` and `hsla()`: percentage saturation/lightness, legacy comma notation,
  and modern space/slash notation. Hue accepts unitless degrees, `deg`, `rad`,
  `grad`, and `turn`; normalize hue modulo one turn.
- Alpha as a number in `[0,1]` or percentage in `[0,100]`. Reject malformed,
  non-finite, mixed-separator, and out-of-range components rather than coercing
  them to a plausible color. RGB channels are `[0,255]` or `[0,100]%`;
  saturation/lightness are `[0,100]%`.

Show the swatch over a checkerboard when transparency matters, plus normalized
CSS hex, RGB(A), and HSL(A) values. Normalize to numeric RGBA for rendering: CSS
`#RRGGBBAA` must not be mistaken for Qt's `#AARRGGBB` string convention. Invalid
values and color-looking fragments inside prose remain ordinary text.

### Other previews

- Pretty-print complete valid JSON only within the existing 65,536-code-unit
  expanded-preview budget; larger JSON-looking entries remain plain text.
- Show the domain and an explicit Open link action for standalone HTTP(S) URLs
  and bare domains supported by the packaged opener. Never fetch link metadata
  automatically; opening remains an explicit existing history-index action.
- Retain existing image and expanded text previews, text editing, and file paths.
  Preview formatting must not alter the stored/pasted text.

## Design

Extend `ClipboardHistory.js` and the existing `Clipboard.qml` row/preview surfaces,
not a parallel history model. Keep stock persisted types (`text` and `image`)
separate from derived display categories. Classifier precedence is image/oversized,
file URI, whole-value color, standalone link, valid bounded JSON, conservative
code, then text. Preserve the current image-file filtering behavior.

Code detection is intentionally heuristic: require a shebang, or at least two
independent code signals (language keywords/declarations and structural syntax).
A lone brace or punctuation in prose is insufficient. No syntax highlighting,
language server, or parser dependency is introduced.

Use existing Omarchy theme singletons and current bounds for layout. Hide absent
metadata instead of guessing it. Unsupported or oversized data keeps the existing
safe text/placeholder/error path, never a silent empty result or unsafe preview.

## Testing strategy

Extend the existing model tests only for behavioral boundaries: color alpha and
syntax, classifier precedence, multi-term/type-query behavior, exact counts beyond
the display cap, and unchanged action indices/payloads. Use synthetic fixtures,
never personal clipboard contents. Run the existing validation commands and use
an isolated temporary Quickshell harness for actual UI verification; see the plan.

## Out of scope and preserved exploration

These remain recorded follow-ups, not silently promised features of this UI change:

- Source-app tracking, authoritative timestamps, `app:`, age/date tokens, pins,
  paste counts, pause, and configurable retention require a separate persistent
  metadata/capture design. Stock normalization drops unsupported fields; old
  application identities and full timestamps cannot be reconstructed reliably.
- QR/OCR and richer PDF/video/audio/file inspection can be explored as optional,
  bounded enrichment of existing entries, but would introduce helpers/dependencies.
- Email/HTML/number-specific categories, per-category pill counts, quoted/boolean
  query syntax, relevance sorting, named CSS colors, CSS variables, and advanced
  color spaces such as `lab()`, `oklch()`, or `color(display-p3 ...)` are deferred.
- Do not copy upstream's pause semantics as a privacy guarantee: its capture work
  continues even while QML discards the resulting history additions.
