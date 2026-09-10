# Clipboard discovery implementation plan

Status: in progress; Task 1, the Links slice of Task 2, the filter-control slice of Task 3, and current-type/link presentation from Task 5 are complete. Remaining categories, result counts, search, and richer previews remain pending.
Last updated: 2026-09-10
Local branch: `feat/clipboard-discovery`
Contract: [spec.md](spec.md)

## Delivery boundary

This plan implements the discovery/presentation improvements from the comparison,
including broader color formats. It does not replace Omarchy's capture backend.

- Work stays local on this feature branch. No push, merge to `main`, marketplace
  request/workflow, or version bump without separate explicit authorization.
  Local development installation and refresh are now explicitly authorized.
- Preserve the stock history file/schema and packaged history-index helpers.
- Add no runtime dependencies, watcher, persistent service, or automatic network
  access. Keep all current history, image, and text-rendering safety boundaries.
- Existing inline editing, expanded previews, and keyboard actions must survive.
- Preserve original payloads even when classification or preview formatting changes.

## Baseline and implementation ownership

- `ClipboardHistory.js`: validation, color detection, file URI recognition,
  bounded search, display rows, serialization, and stable history indices.
- `Clipboard.qml`: type filters, keyboard actions, result rows, split previews,
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
Stop only that temporary process afterward. Refresh the authorized local test
installation only after verification; do not seed personal history with upstream
screenshot scripts. If plugin rescanning leaves cached QML active, refresh the
authorized development installation with a supported shell restart after warning
about the brief bar/overlay interruption. Verify new behavior in the loaded shell.
For action verification, use only synthetic content and a disposable target;
never paste, delete, or clear personal history. Any actual clipboard replacement
must be confined to an explicitly authorized smoke session.

Fixture corpus:

- Plain text: `alpha beta`, `beta alpha`, `plain prose { with punctuation }`.
- Markup-like text: `<b>alpha</b>` (must display literally, including during search).
- Link: `https://example.com/docs/clipboard`; bare domain: `example.com/docs`.
- JSON: `{"project":"clipboard","values":[1,2]}`; invalid JSON: `{"project":}`.
- Code: `function pasteEntry(id) {\n  return id;\n}`.
- Colors: `#7aa2f7`, `7aa2f7`, `#abc`, `#abcd`, `#7aa2f780`, `7aa2f780`,
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
  and the specified hue units. Accept unprefixed six- and eight-digit hex.
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

**Context:** File URIs were already recognized. Stored types must remain
stock-compatible; dedicated Files/Code/JSON filters remain pending.

Links completed 2026-09-10, including host subtitles and link icons. Model tests
cover whole-value recognition/rejection, classification bounds, image/file/color
precedence, original payloads, and stable history indices. The isolated UI verified
link filtering and cycling in both directions. Direct shortcuts now follow the
five visible pills: `Ctrl+1`/`2`/`3`/`4`/`5` select All/Text/Links/Images/Colors.

**Acceptance criteria**

- Add derived Links, Files, Code, and JSON categories using the spec's precedence
  and bounds. Valid JSON beats code heuristics; punctuation alone is not Code.
- Make every category reachable through existing filter cycling. Map `Ctrl+1`
  through `Ctrl+5` to All/Text/Links/Images/Colors in visible pill order, and
  preserve single-image-file membership in Images.
- Classification does not change history order, action indices, stored types,
  original text, or the oversized placeholder behavior.

**Verify**

- Run `node tests/clipboard-history.js` with classification/precedence and stable
  index cases drawn from the corpus, including invalid and oversized text.
- In the isolated harness, cycle categories in both directions and verify all
  five direct filter shortcuts select the matching visible pill.

## Task 3: Expose filter pills and truthful result counts

**Context:** Compact All/Text/Links/Images/Colors pills are implemented below
search. The result model still stops after 60 matches, so its length cannot be
used as the full match count. Full result counts and remaining categories stay pending.

Filter controls completed 2026-09-10. The user requested smaller pills: 24-pixel
target height, reduced padding, unchanged text size. Actual pointer clicks verified
every category, selection state, query retention, and keyboard focus/navigation.
Overflow selection was checked with the strip constrained while the overlay was
hidden; the visible card stayed 940×640 with equal-width content panes.

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

**Context:** Current-type two-line rows are implemented. No captured application
or authoritative text timestamp is available.

Pulled forward at the user's request and verified 2026-09-10: rounded icon/swatch
frames, current-type subtitles, and a centered 50/50 split. Link-domain labels
were added in the Links/filter-controls slice.
The current thumbnail direction supersedes rounded image clipping: images sit
inside the same frame as other items with a 3-pixel theme-scaled inset.
Other new-category labels still depend on Task 2; highlighting depends on Task 4.

Whole-row height adaptation completed 2026-09-10. The card preserves its width
and fits the largest whole-row capacity under the existing height ceiling and
available logical screen height, using actual row/gap and control/inset sizes.
The user rejected stepped touchpad scrolling: scrolling remains smooth, with no
new snapping or input handlers. Search/filter/result count changes do not resize it.

The actual default surface measured 940×620 with seven complete rows. Hidden
probes covered logical screen heights from 320 to 1296, spacing/font scale changes,
exact fit boundaries, fractional insets/gaps, and the screen-capped one-row fallback.
Wheel input, fractional offsets, and inertial flicking remained unsnapped; filtering,
all five numeric shortcuts, the editor, and expanded preview retained stable height.

The isolated UI smoke covered literal markup, full counts beyond preview limits,
missing-image fallback icons, selection/filtering, compact/expanded alpha previews,
oversized edit refusal, removal, and metadata refresh after an edited copy. The
packaged copy helper preserved the original hashless expression and whitespace
through a temporary file transport, without replacing the system clipboard.
Square, wide, and tall image fixtures visually verified padded shared frames,
original image corners, preserved aspect ratios, and unchanged card/pane dimensions;
missing images retained the existing fallback icon.

**Acceptance criteria**

- Use shared rounded frames for type icons, smaller color swatches, and padded
  image thumbnails without rounding the images themselves. Add a muted metadata
  line without losing selection contrast, title highlighting, mouse activation,
  or keyboard behavior. Failed images keep a type icon.
- Show exact word/line counts for retained text, type/domain for links, directory/
  count information for files, and available image MIME. Omit unknown fields.
- Reuse metadata computed when history changes; do not rescan full text for every
  search keystroke or falsely report bounded-preview counts as full-entry counts.
- Preserve bounded placeholders and long/unbroken/Unicode text behavior; row
  metadata must not turn unknown app/time/size into misleading values.
- Center the divider for equal-width list and preview panes; preserve card width.
  Fit height to complete rows where one row and the controls fit within the screen
  cap. Keep smooth scrolling unchanged and sizing independent of results/scroll position.

**Verify**

- Run `node tests/clipboard-history.js` for meaningful metadata boundaries and
  cache invalidation after history replacement/edit/removal where needed.
- Inspect corpus rows and selection transitions in the isolated harness, including
  long text, markup-like text, files, images, and translucent colors. Keep the
  visible test widget at its normal computed size; run constrained-size/font probes
  while hidden without changing the user's display configuration.

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
permit pushing or publishing. Leave `main`, `origin/main`, and the manifest version
unchanged. Refresh only the separately authorized local development installation.

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
