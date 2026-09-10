# Clipboard discovery implementation plan

Status: in progress; Task 1 is complete, Tasks 2–6 are pending.
Last updated: 2026-09-10
Local branch: `feat/clipboard-discovery`
Contract: [spec.md](spec.md)

## Delivery boundary

This plan implements the discovery/presentation improvements from the comparison,
including broader color formats. It does not replace Omarchy's capture backend.

- Work stays local on this feature branch. No push, merge to `main`, marketplace
  request/workflow, version bump, or installed-plugin update without separate
  explicit authorization. A local planning commit is not a release.
- Preserve the stock history file/schema and packaged history-index helpers.
- Add no runtime dependencies, watcher, persistent service, or automatic network
  access. Keep all current history, image, and text-rendering safety boundaries.
- Existing inline editing, expanded previews, and keyboard actions must survive.
- Preserve original payloads even when classification or preview formatting changes.

## Baseline and implementation ownership

- `ClipboardHistory.js`: validation, color detection, file URI recognition,
  bounded search, display rows, serialization, and stable history indices.
- `Clipboard.qml`: type filters, keyboard actions, single-line rows, split previews,
  expanded view/editor, bounded reader, and confirmed writes.
- `tests/clipboard-history.js`: existing model regression suite.
- `README.md`: user-facing controls, capabilities, safety limits, verification.

Reuse these modules and conventions. Before changing exported model APIs, use LSP
references when available and migrate every caller/test in the same slice. Do not
add a second classifier/search model beside the existing one. The tasks below
share QML/model files and are ordered for serial implementation; parallel work
requires explicit non-overlapping ownership, not concurrent edits to those files.

## Verification fixtures and safe runtime setup

For each UI slice, exercise the actual changed `Clipboard.qml` in a temporary
Quickshell harness, not screenshots of the upstream plugin. Construct the harness
under a fresh temporary directory with:

1. The worktree's `Clipboard.qml` and `ClipboardHistory.js`, with access to the
   installed shell's `Commons`/`Ui` imports; do not start the production shell root.
2. A synthetic history at `$smoke/home/.local/state/omarchy/clipboard-history.json`.
   Start the harness with `HOME=$smoke/home` and point its `historyPath` at that file
   before component completion. This isolates both the reader and packaged helpers.
3. A root that instantiates Clipboard and calls `open("{}")` after initialization.
   Leave `OMARCHY_PATH`, the Wayland display, and runtime directory available for
   shell imports and rendering; use a separate Quickshell configuration path.
4. The entries below, serialized as ordinary `{ "type": "text", "text": value }`
   records unless otherwise stated. Create any image/file fixture in `$smoke`,
   never under the real clipboard state directory.

Launch the resulting harness with `quickshell --path "$smoke/shell.qml"` through
the harness process supervisor. Interact with it and capture visual evidence.
Stop only that temporary process afterward. Do not deploy to the live plugin,
restart the production shell, or run upstream screenshot scripts that seed history.
For action verification, use only synthetic content and a disposable target;
never paste, delete, or clear personal history. Any actual clipboard replacement
must be confined to an explicitly authorized smoke session.

Fixture corpus:

- Plain text: `alpha beta`, `beta alpha`, `plain prose { with punctuation }`.
- Markup-like text: `<b>alpha</b>` (must display literally, including during search).
- Link: `https://example.com/docs/clipboard`; bare domain: `example.com/docs`.
- JSON: `{"project":"clipboard","values":[1,2]}`; invalid JSON: `{"project":}`.
- Code: `function pasteEntry(id) {\n  return id;\n}`.
- Colors: `#7aa2f7`, `7aa2f7`, `#abc`, `#abcd`, `#7aa2f780`,
  `rgb(122, 162, 247)`, `rgba(122, 162, 247, 0.5)`,
  `rgb(100% 0% 0% / 50%)`, `hsl(120, 100%, 50%)`,
  `hsla(0.5turn 100% 50% / 25%)`, and `rgba(0, 0, 0, 0)`.
- Invalid/non-color text: `rgb(999, 0, 0)`, `rgba(0,0,0,2)`,
  `rgb(1, 2 3)`, `#12`, `color: #abc`, and `use rgb(1,2,3) here`.
- A generated 16-by-16 PNG with an image record pointing to it; a text record
  containing its `file://` URI; and a two-file URI-list text record.
- Eighty-five distinct `count-fixture-N` text records, `N = 0..84`, to distinguish
  true matches from the 60-row display cap.
- Existing regression-suite fixtures for oversized entries, long text, invalid
  history, and write races; reuse their setup rather than personal state.

## Task 1: Extend color detection and alpha-safe previews

Completed 2026-09-10. Model tests, QML lint, and local manifest validation pass.
An independent 1,200-case HSL conversion probe passed. An isolated Quickshell
harness visually verified compact/expanded previews and 0/50/100% alpha.
The editor-to-packaged-copy-helper path preserved a synthetic expression
byte-for-byte with `wl-copy` redirected to a temporary file transport; the system
clipboard and installed plugin were not changed.

**Context:** The existing Colors filter and swatch already provide a complete
surface for this change. At planning time, `detectColor` accepted only six-digit hex.

**Acceptance criteria**

- Implement every format/range in the spec: short/long CSS hex with optional alpha,
  RGB/RGBA and HSL/HSLA, comma and space/slash notation, percentage channels/alpha,
  and the specified hue units. Retain unprefixed six-digit hex compatibility.
- Valid values enter the existing Colors filter; malformed, out-of-range, mixed
  syntax, and color fragments embedded in prose remain Text.
- Compact and expanded previews render the same RGBA color and show transparency
  over a checkerboard. CSS alpha-last hex is never interpreted as Qt alpha-first.
- Show normalized hex/RGB(A)/HSL(A) details without changing stored/pasted text.

**Verify**

- Extend and run `node tests/clipboard-history.js` for format equivalence, hue
  wrapping, transparent/opaque boundaries, syntax rejection, and payload preservation.
- Run `qmllint -I "$OMARCHY_PATH/shell" Clipboard.qml`.
- In the isolated harness, compare hex/RGBA/HSL equivalents, inspect 0/50/100%
  alpha, and edit/copy a synthetic color without losing the original expression.

## Task 2: Add derived content categories

**Context:** File URIs are already recognized, but Links/Files/Code/JSON are not
available as dedicated filters. Stored types must remain stock-compatible.

**Acceptance criteria**

- Add derived Links, Files, Code, and JSON categories using the spec's precedence
  and bounds. Valid JSON beats code heuristics; punctuation alone is not Code.
- Make every category reachable through existing filter cycling. Preserve
  `Ctrl+1`/`2`/`3`/`4` and single-image-file membership in Images.
- Classification does not change history order, action indices, stored types,
  original text, or the oversized placeholder behavior.

**Verify**

- Run `node tests/clipboard-history.js` with classification/precedence and stable
  index cases drawn from the corpus, including invalid and oversized text.
- In the isolated harness, cycle categories in both directions and verify the
  four existing direct filter shortcuts still select their original categories.

## Task 3: Expose filter pills and truthful result counts

**Context:** The current header shows only the active filter label. The result
model stops after 60 matches, so its length cannot be used as the full match count.

**Acceptance criteria**

- Add the eight specified clickable pills with a clearly active state and retain
  keyboard focus/navigation after a click. Use existing theme fonts/colors/spacing.
- Show matching-entry totals across the bounded loaded history, not just rendered
  rows. Distinguish capped display (`60 shown / 85 matches`) from total matches.
- At constrained widths, horizontally scroll the pill row; keep the active pill
  visible without clipping the search field or losing result/preview space.
- Keep zero-match, empty-history, and refused-history states distinct. Hide a
  misleading numeric result counter when history could not be loaded.

**Verify**

- Run `node tests/clipboard-history.js` for matching totals beyond the display cap
  and for rejected/oversized history behavior where the model contract changes.
- In the isolated harness, search `count-fixture`, verify 85 matches/60 shown,
  click through empty/nonempty categories, and exercise keyboard selection.
- Inspect the actual surface at normal and narrow available widths; do not change
  the user's monitor configuration for this check.

## Task 4: Add structured fuzzy search and safe highlighting

**Context:** Search currently applies one case-insensitive substring to a bounded
prefix. Reuse the same categories/counts for typed queries and pills.

**Acceptance criteria**

- Support fuzzy subsequence AND terms over bounded text and displayed searchable
  metadata (type, file names/paths, link domain, and available image MIME).
  Retain history order and all existing processing caps.
- Implement the spec's `type:` aliases, last-recognized-token precedence, unknown
  token fallback, and synchronized pill behavior. Do not add unsupported app/date/
  pinned operators without their data model.
- Highlight all applicable ordinary terms in visible titles, with no execution or
  interpretation of clipboard markup. Metadata-only matches remain valid.
- Counts reflect the complete effective query; query/filter edits leave selection
  valid and preserve the existing clear-search/close behavior of Escape.

**Verify**

- Run `node tests/clipboard-history.js` for `alpha beta`, reordered terms, a fuzzy
  `clpb` match against `clipboard`, `type:json project`, unknown tokens, conflicting
  type tokens, preserved ordering/indices, and no matches beyond the search cap.
- In the isolated harness, type `type:json project`, switch to All, and verify only
  the recognized type constraint is removed. Search `alpha` in the markup fixture
  and confirm literal brackets/tags remain visible and inert.

## Task 5: Add contextual two-line result rows

**Context:** Rows currently contain one elided title plus an optional swatch/image.
No captured application or authoritative text timestamp is available.

**Acceptance criteria**

- Add type icons and a muted metadata line without losing color/image thumbnails,
  selection contrast, title highlighting, mouse activation, or keyboard behavior.
- Show exact word/line counts for retained text, type/domain for links, directory/
  count information for files, and available image MIME. Omit unknown fields.
- Reuse metadata computed when history changes; do not rescan full text for every
  search keystroke or falsely report bounded-preview counts as full-entry counts.
- Preserve bounded placeholders and long/unbroken/Unicode text behavior; row
  metadata must not turn unknown app/time/size into misleading values.

**Verify**

- Run `node tests/clipboard-history.js` for meaningful metadata boundaries and
  cache invalidation after history replacement/edit/removal where needed.
- Inspect corpus rows and selection transitions in the isolated harness, including
  narrow width, long text, markup-like text, files, images, and translucent colors.

## Task 6: Enrich JSON and link previews

**Context:** The split pane already supports plain text, images, and hex colors;
Task 1 completes color enrichment. Preserve the existing expanded view and editor.

**Acceptance criteria**

- Pretty-print complete valid JSON within the declared limit in the preview only.
  Invalid/oversized JSON-looking content retains the safe plain-text path.
- Show link domain/full URL and an explicit Open link control using the existing
  packaged opener by history index; never fetch or embed remote content.
- Editing/copying/pasting uses the original text, not formatted JSON or a rewritten
  URL. Existing action/write guards apply to the new preview control too.

**Verify**

- Run `node tests/clipboard-history.js` for bounded JSON formatting and unchanged
  source text/action index after searching/filtering.
- In the isolated harness, inspect valid/invalid JSON, a long JSON-looking payload,
  HTTP(S)/bare-domain links, and editor transitions. Verify link opening only in
  an authorized synthetic action smoke session; do not contact arbitrary clipboard URLs.

## Completion gate

After the slices are integrated, run once from the repository root:

```sh
node tests/clipboard-history.js
qmllint -I "$OMARCHY_PATH/shell" Clipboard.qml
omarchy plugin validate .
```

Complete the isolated UI scenarios above and exercise unchanged open/close,
selection, expanded preview, edit cancellation, copy/paste, removal, clear
confirmation, and read/write error handling with synthetic history. Record what
was actually exercised; model tests are not evidence of visual correctness.
After behavioral verification, update the existing README for implemented filters,
query semantics, metadata limits, color syntax, and controls. Remove temporary
verification artifacts; do not add permanent tests that merely pin wording/wiring.

Completion means the specified UI and color behavior work end to end. It does not
permit pushing or publishing. Check that `main`, `origin/main`, the manifest
version, and the installed plugin remain unchanged before reporting the result.

## Follow-ups requiring a separate scope decision

Preserve the wider exploration without mixing backend changes into this plan:

- Persistent pins and `is:pinned`; source application and full timestamps;
  `app:`/age/date filters; paste counts; pause and configurable retention.
- Optional bounded QR/OCR enrichment and richer PDF/video/audio/file inspection.
- Optional per-category counts and Email/HTML/Number categories.

A later design must choose stock-compatible companion metadata versus owning a
replacement history/capture backend. Do not guess historical app/timestamp data,
let stock retention silently destroy promised permanent pins, or call a history-
insertion gate a privacy-safe pause while capture/OCR continues running.
