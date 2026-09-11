# Searchable contextual clipboard actions

Status: Tasks 1–6 complete; Fable review consumed, parent fixes verified, and known limitations documented.
Last updated: 2026-09-11
Branch: `feat/clipboard-discovery`
Implementation sequence: [plan.md](plan.md)

## What

Add a keyboard-first, searchable actions menu for the selected clipboard entry.
The user prioritized this feature ahead of the remaining
[clipboard discovery work](../clipboard-discovery/plan.md), approved `Ctrl+.`,
and requested both ascending and descending line sorting. Existing discovery
work remains queued, not removed or made a prerequisite.

The menu combines the content-specific actions below with common Copy/Paste,
Edit text where supported, and Remove entry actions. Editor menus act on the
current draft.

## Requirements

### Menu and search

- `Ctrl+.` toggles Actions from the history list, expanded preview, or text editor.
  Add a visible `Actions · Ctrl+.` control without changing the card's width,
  equal-width panes, adaptive whole-row height, or smooth scrolling.
- Show a popover inside the existing card, with a focused `Search actions…` input
  and a scrollable list. Show at most eight actions at once and cap the popover
  within the available height of the unchanged clipboard card. Show a persistent
  vertical scroll indicator only while the list overflows. Keep keyboard selection
  visible, including wrapping immediately after opening or changing the query.
  Do not open a second shell or replace history search.
- Search only applicable action labels and explicit aliases, not clipboard
  contents. Match case-insensitively: every whitespace-separated query term must
  match a substring or fuzzy subsequence within a label or alias. Retain curated
  action order; do not add usage tracking, dynamic ranking, or search highlighting.
  Examples: `sort asc`, `descending`, `dedup`, `rgba`, and `open browser`.
- Keep the actions query separate from the history query. Each opening starts
  with an empty actions query. Query changes select the first matching enabled
  action; no matches shows an inert empty state, and Enter does nothing.
- Up/Down and Ctrl+J/Ctrl+K navigate actions; Enter or a pointer click executes
  exactly one action. Escape or Ctrl+. closes only Actions, even with a nonempty
  query, and restores the previous view/focus without changing history selection.
- While Actions is open, editing/navigation keys cannot reach the history list,
  editor, or existing action shortcuts behind it. Preserve ordinary search-input
  editing. Ctrl+K remains history navigation outside Actions.
- Type-specific actions precede common actions. Common actions are Paste, Copy,
  Edit text where supported, and Remove entry in a separated final group. Preserve
  existing direct shortcuts and confirmation behavior; do not add Clear history
  to this selected-entry menu. Hide inapplicable actions, not inert placeholders.
- In the text editor, Actions operates on the current complete draft: offer text
  transformations and Copy/Paste edited text. Do not expose source-entry removal
  or external image/link actions over an unsaved draft. Restoring focus must retain
  the draft, editor cursor, and scroll position when no action changes its text.

### Actions by content

| Content | Actions in this feature |
| --- | --- |
| Color | Copy as HEX; Copy as RGB(A); Copy as HSL(A); Edit color expression; Pick a color from screen |
| Image capture or a single copied image file | Edit a copy in Tensaku; Copy image path; Open containing folder; Save a copy as |
| Standalone link | Open in browser; Copy domain |
| Text | The transformations below, plus existing edit/copy/paste actions |

Text transformations are available for retained editable text, including textual
color/link expressions and editor drafts. Do not treat file-URI lists or image
paths as prose; their entry menus expose file/image actions instead. A normal
explicit Edit text operation may still open a stock text payload as today.
Oversized placeholders never gain transformation, derived-copy, or preview access.

### Text transformation semantics

These are explicit implementation defaults; no automatic cleanup is applied.
All operations act on the complete retained text/draft, not the preview prefix.

| Action | Contract |
| --- | --- |
| Trim each line | Remove leading and trailing ASCII spaces/tabs from every line; preserve every original line separator |
| Trim trailing whitespace | Remove trailing ASCII spaces/tabs only; preserve indentation and line separators |
| Join lines | Trim spaces/tabs at line boundaries, omit empty lines, and join the remaining lines with one ASCII space; emit no terminal newline |
| Remove leading tabs | Remove the initial run of tabs from each line; preserve leading spaces, internal tabs, and line separators |
| Remove common indentation | Remove the longest identical space/tab prefix shared by nonblank lines; preserve relative indentation, blank lines, and separators; never guess tab width |
| Remove empty lines | Remove lines containing only spaces/tabs or no characters |
| Remove duplicate lines | Exact, case-sensitive whole-line equality; retain the first occurrence and original order |
| Sort lines ascending | Case-insensitive lexicographic order of Unicode-lowercased whole lines; retain original text, duplicates, and input order among equal keys |
| Sort lines descending | Reverse the comparison, not the ascending result array; retain input order among equal keys |
| Uppercase / Lowercase | JavaScript Unicode case conversion without trimming or Unicode normalization |

Recognize CRLF as one separator, plus LF, CR, U+2028, and U+2029. For line-sequence
operations (sort, deduplicate, remove empty lines), use the first encountered
separator when joining; mixed separators are consequently normalized. Preserve
one terminal separator if present originally and the result contains any lines.
The final terminator is not a sortable extra empty line; interior empty lines are.
Sort keys include original whitespace. Empty lines sort first ascending and last
descending. Sorting is locale-independent and not numeric/natural sorting: `10`
precedes `2` ascending. Sorting never removes duplicates or trims lines.

Choosing a transformation opens/updates the existing editor with its result;
it never immediately writes history or copies/pastes. Reopening Actions can chain
transformations on that draft. Existing editor Copy/Paste controls accept the
result through the existing history write-confirmation path, without changing the
source entry in place. Cancel changes neither history nor the system clipboard.
An unchanged result remains a draft, not a new entry. Empty previews are allowed,
but existing blank-text validation prevents copying/pasting them. If case expansion
or another operation exceeds the 1 MiB text limit, retain the previous draft and
show an error; never silently truncate.

### Color, link, and external-tool behavior

- Reuse `ClipboardHistory.colorDetails` for all three color copies. HEX uses CSS
  alpha-last order and includes alpha when translucent; RGB/HSL use their alpha
  forms when needed. Preserve existing precision/8-bit HEX quantization rather
  than introducing a second converter or silently dropping transparency.
- Generated text copies (color formats, domain, image path) reuse the guarded
  add-entry/write-confirmation/copy-only flow used by the editor. Only an explicit
  copy action performs this write; opening/searching the menu does not.
- Omarchy's inspected color tool is `hyprpicker`, not an editor of existing colors.
  Edit color expression uses the current text editor. Pick from screen runs
  `hyprpicker --format hex --no-fancy` without autocopy, validates its result, and
  opens an editable color draft. Release the overlay's keyboard grab during the
  picker. Cancellation restores the prior view without changing the clipboard.
  Empty successful output or hyprpicker's empty exit-status-2 cancellation is
  non-mutating; a genuine exit-status-1 failure remains an error.
- Open in browser reuses the existing guarded history-index opener for classified
  HTTP(S)/bare-domain links. Copy domain uses existing derived host metadata,
  without user information or port. No fetching, metadata scraping, or URL cleanup.
- Images include native image records and validated single local image-file URIs;
  do not pass an image-file URI through the stock plain-text opener. Copy image
  path produces a decoded absolute filesystem path, not a URI or shell-quoted text.
- Open containing folder passes the validated parent directory to `xdg-open`.
  Save a copy as uses the installed QtQuick.Dialogs save dialog and copies the
  original bytes, with the source format/extension; no transcoding. Cancellation
  writes nothing. Refuse an existing destination rather than overwriting it.
  Atomic no-replacement publication requires anonymous temporary files
  (`O_TMPFILE`) and filesystem hard links. Unsupported filesystems fail visibly;
  do not add a potentially replacing fallback.
- The inspected `tensaku-edit` wrapper saves back to its input path. Edit a copy
  must first duplicate the image into a private, process-owned temporary directory
  and launch Tensaku on that duplicate, never the original. Use a distinct editor
  application ID so the tracked child owns this editing session. Copying an edited
  image goes through the editor/stock capture workflow, not custom history insertion.
  Keep the duplicate until the editor exits, then remove only that action's files.
  Releasing the clipboard overlay must not delete an image still used by the editor.
  Plugin disable/reload or shell teardown can kill the worker without running its
  cleanup trap and leave a private copy behind. Document this limit; do not delete
  files still in use or add a detached cleanup service.
- File dialogs and external applications must receive keyboard focus. Restore the
  overlay on cancellation or failure; report missing/unreadable files, unavailable
  tools, failed copies, or failed launches. Never silently fall back to copying
  the original payload when the user requested another action.

### Safety and compatibility

Keep the stock capture service, history schema, packaged clipboard helpers, plain
text rendering, validation limits, local-image checks, and write confirmation.
Do not add packages, services, a second watcher/shell, automatic network access,
or a competing history store. Use argv-based processes; clipboard text is never
shell code and derived clipboard text never becomes a command-line argument.

Bind Actions to a selected source snapshot, not a mutable display index. Close a
source-entry menu if history is replaced or a reload/write starts, and revalidate
before dispatch; it must never act on an entry that moved into an old index.
An editor draft remains independent of later history changes, while saving still
obeys existing history guards. Close transient menus on overlay close/reopen and
ensure delayed process completions cannot dispatch a canceled clipboard action.

Work stays local on the current feature branch. No push, merge to main, version
bump, marketplace action, package installation, or shell restart is authorized by
this planning approval. Preserve the separately authorized local development
installation workflow; warn before a later supported shell restart.

## Design

Extend `Clipboard.qml` and `ClipboardHistory.js`; do not create another classifier,
history model, or plugin. QML owns the small action catalog, menu/query/focus state,
context snapshot, dialogs, and process lifecycle. The existing JS module owns pure
query matching and text transformations for reuse by the UI and model tests.
Reuse the editor's accepted-text and confirmed-write behavior for derived copies
rather than duplicating its state machine. QtQuick.Dialogs is an additional QML
import from the already installed Qt stack, not a new runtime package.
`ClipboardFiles.sh` owns checked file operations and private Tensaku duplicate
lifetimes. It delegates saved copies to `ClipboardCopy.py`, using the system
Python standard library to hold the source, destination directory, and anonymous
staging file open through atomic no-overwrite publication. QML invokes fixed
worker operations with argument arrays; clipboard contents are never interpolated
into shell commands.

## Testing strategy

Use synthetic fixtures and the isolated Quickshell setup in [plan.md](plan.md).
Verify the actual searchable menu, keyboard containment, draft chaining, source
preservation, external-tool cancellation, image file lifetime, and failed/stale
writes. Keep regression tests only for behavioral boundaries such as sorting ties,
line endings, search applicability, size expansion, and action/history races.
Completed verification and the final independent review status are recorded in the plan.

## Out of scope

Remaining discovery filters/counts/search/previews; a visual color-slider editor;
HEX without `#`; tracking-parameter removal; JSON formatting/minification;
paragraph-preserving joins; numeric/natural or locale-specific sorting; OCR/QR;
image conversion; action usage analytics or custom/user-supplied commands.
These require another scope decision, not hidden additions to this feature.
