# Searchable actions implementation plan

Status: Tasks 1–6 complete; Fable review consumed, parent fixes verified, and known limitations documented.
Last updated: 2026-09-11
Local branch: `feat/clipboard-discovery`
Contract: [spec.md](spec.md)

## Priority and boundaries

Implement this feature before resuming the unfinished
[discovery tasks](../clipboard-discovery/plan.md). Keep the completed discovery
behavior and all queued requirements. The user authorized Task 1, then continued
with the complete feature and requested a final Fable review through Herdr.
All six tasks are implemented. This plan does not itself authorize commits, deployment, push,
marketplace actions, version bumps, or a production shell restart.

The complete feature is Tasks 1–6, not just a searchable shell around placeholders.
Expose only working actions as each slice lands. All tasks share `Clipboard.qml`
and `ClipboardHistory.js`; implement them serially in the order below. Do not fan
out concurrent edits to those files. If implementation is delegated later, agents
skip formatters, linters, and builds/tests; the integration owner verifies each
completed slice after concurrent edits, if any, have settled.

## Existing code and shared contracts

- `Clipboard.qml`: selection, existing copy/paste/open/remove actions, expanded
  preview, text editor, bounded reader, and confirmed history writes. Extend these
  flows rather than adding a second mutation state machine.
- `ClipboardHistory.js`: entry validation, color details, file paths, link domains,
  prepared display rows, and text limits. Add pure action matching/transforms here;
  retain original source payloads and indices.
- `tests/clipboard-history.js`: keep only meaningful model regressions. Before
  changing exported model symbols, use LSP references when available and migrate
  affected callers/tests together.
- `README.md`: describe behavior only after it exists and is smoke-tested. These
  planning documents are not claims of implemented controls.

Use stable action IDs with labels, aliases, applicability, and grouped display
order in a small QML-owned catalog. Dispatch IDs through existing/root action
functions, never through command text stored in history. The model matcher filters
this supplied metadata; it does not introduce another content classifier.

QML owns independent actions query/selection/focus state and a source snapshot.
Invalidate source menus on history replacement or read/write start. Editor menus
operate on the current draft, not the original row. A shared generated-text
submission path must retain `finishEditing`'s validation, add-entry semantics, and
write confirmation; route both editor acceptance and derived Copy actions through
it without duplicating those guards or passing text in process arguments.

## Isolated verification setup

Reuse the [discovery harness contract](../clipboard-discovery/plan.md#verification-fixtures-and-safe-runtime-setup).
For every actual UI slice:

1. Create a fresh temporary directory with `home`, `fixtures`, and a Quickshell
   root containing the worktree's `Clipboard.qml` and `ClipboardHistory.js`.
   Import the installed shell's Commons/Ui; never launch its production root.
2. Write synthetic stock-format history at
   `$smoke/home/.local/state/omarchy/clipboard-history.json`; launch the harness
   with `HOME=$smoke/home` and set its history path before component completion.
   Keep Wayland/runtime variables and `OMARCHY_PATH` available.
3. Use text rows with the literal values below. Generate a small PNG containing
   colored blocks under `$smoke/fixtures`, and add both a native image record and
   a text `file://` URI pointing to a second copy. Include spaces and Unicode in
   the image filename. Create a separate missing-image row.
4. Preserve the real packaged history helpers. For copy/paste verification,
   replace only their terminal clipboard/key-injection effects with temporary
   recording commands via the harness PATH, as in the existing isolated tests.
   Record bytes rather than changing the personal clipboard. Record the browser
   launch boundary without opening personal URLs; report it as dispatch testing.
5. Launch the actual harness with `quickshell --path "$smoke/shell.qml"` through
   the process supervisor. Use real pointer/key events and capture the rendered
   surface. Keep normal computed dimensions for visible checks; perform constrained
   size/font probes while hidden. Do not edit the user's display configuration.

Fixtures (escapes below denote actual control characters):

| Purpose | Input / expected observation |
| --- | --- |
| Trim | `  alpha \t\r\n\tbeta  \r\n` becomes `alpha\r\nbeta\r\n` |
| Leading tabs | `\t\talpha\n \tbeta\n` becomes `alpha\n \tbeta\n` |
| Dedent | `  alpha\n    beta\n` becomes `alpha\n  beta\n` |
| Join | ` alpha \n\n\tbeta\r\n` becomes `alpha beta` |
| Sorting | `beta\nAlpha\nalpha\n10\n2\n` becomes `10\n2\nAlpha\nalpha\nbeta\n` ascending and `beta\nAlpha\nalpha\n2\n10\n` descending |
| Blank line sorting | `b\r\n\r\na\r\n` becomes `\r\na\r\nb\r\n` ascending and `b\r\na\r\n\r\n` descending |
| Deduplicate | `beta\nAlpha\nbeta\nalpha\n` becomes `beta\nAlpha\nalpha\n` |
| Unicode separators | `b\u2028a\u2028` sorts to `a\u2028b\u2028` |
| Markup | `<b>alpha</b>` remains literal in every menu/editor/preview surface |
| Color | `rgba(122, 162, 247, 0.5)`; HEX copy is `#7AA2F780` |
| Link | `https://example.com/docs?q=1` and `example.com/docs`; Open preserves the original payload, Copy domain yields `example.com` |

Also generate text longer than the 8,192-unit display prefix with distinguishing
last lines, an input of `ß` repeated just over half the 1 MiB limit (uppercase
expands past the cap), and existing oversized/write-race fixtures. Never read or
seed personal clipboard history for verification.

## Task 1: Searchable menu and existing entry actions

**Status:** completed 2026-09-10. **Context:** existing shortcuts already dispatch guarded
copy/paste/edit/open/remove actions; menu matching must not alter history search.

**Acceptance criteria**

- Add the in-card popover, visible Actions control, and Ctrl+. from list, expanded
  preview, and editor, with the focus/keyboard containment rules in the spec.
- Search applicable labels/aliases with case-insensitive multi-term subsequence
  matching; keep curated order, select the first enabled match, and make an empty
  result list inert. Never search payloads or reveal actions for another type.
- Wire existing common actions and Open in browser for links to current guarded
  dispatch. Separate Remove; do not introduce unsupported action rows yet.
- Source-menu invalidation prevents stale-index dispatch after history replacement,
  reload, or write start. Editor cancellation preserves the unsaved draft. Closing
  or reopening the overlay clears transient menu state.

**Verify**

Run the model suite for meaningful action-query/applicability cases. In the actual
isolated UI, open each context, type `open browser`, navigate with both key sets,
and execute against the recorded helper boundary. Check no matches, Escape with
a nonempty query, Ctrl+. toggling, pointer actions, and preserved history query.
Inject a history replacement while the menu is open and confirm no action uses
the old index. Exercise existing direct shortcuts after closing the menu and verify
unchanged card geometry. Run QML lint and plugin validation after integration.

**Completed verification**

- Model regressions, QML lint, and plugin validation pass. The actual isolated
  overlay verified fuzzy/multi-term search, empty results, keyboard containment,
  pointer opening/editing/dismissal, and all five current content contexts.
- Copy, paste, link opening, removal, and edited-draft copying exercised the
  packaged helpers against synthetic history. Clipboard/key/browser boundary
  commands recorded effects; personal clipboard contents and browser sessions
  were not touched. Browser delivery was verified as dispatch, not a real launch.
- Replaced history, scheduled reloads, pending writes, changed selection,
  refused/empty history, and overlay reentry cannot dispatch stale menu actions.
  Oversized entries expose only existing paste/copy/remove operations; removal
  was confirmed against the correct on-disk entry.
- Editor drafts survive valid history replacement. Reverse selection, cursor,
  and scroll survive menu open/close; the smoke test caught Qt's default
  focus-out deselection, fixed with persistent editor selection.
- Normal geometry stayed 940×620 with a 472-pixel history viewport. Fractional
  history scroll at 73.5 was retained. Hidden 940×200 and 500×300 card probes
  exposed and verified a popup height fix: its cap now accounts for the bottom
  anchor, so it stays inside the card. Expanded views, numeric filters, cycling,
  and clear confirmation retained their existing behavior.
- The installed plugin was not refreshed, no production shell restart occurred,
  and no commit, push, version bump, or marketplace action was taken.

## Task 2: Preview-first whitespace transformations

**Status:** completed 2026-09-11. **Context:** `startEditor` and `finishEditing` already provide
bounded draft editing and confirmed Copy/Paste. Reuse that pipeline.

**Acceptance criteria**

- Add Trim each line, Trim trailing whitespace, Remove leading tabs, and Remove
  common indentation with the exact line/space/tab semantics in the spec.
- Transform complete retained source text into an editor draft, never the display
  prefix. Reopen Actions to transform the current draft; do not reset it to source.
- Factor the existing validated text-submission flow for later derived copies,
  keeping guards, deduplication, write confirmation, and copy-only/paste semantics.
- Cancel/no-op actions do not create history entries. Empty drafts cannot be
  accepted; oversized output leaves the previous draft intact with an error.

**Verify**

Add behavioral regressions for CRLF/Unicode separators, mixed tabs/spaces, common
indentation, and full text beyond the preview prefix; run `node tests/clipboard-history.js`.
In the isolated UI, trim then dedent a draft, cancel, and compare synthetic history
bytes. Repeat and Copy/Paste to the recording transport, verifying the transformed
bytes and unchanged source entry. Inject a refused or stale history write and
confirm no clipboard command runs. Run QML lint and plugin validation.

## Task 3: Sorting, line-list operations, and case conversion

**Status:** completed 2026-09-11. **Context:** Task 2 supplies the preview/chaining/acceptance path.
Sorting is explicitly case-insensitive, stable on equal keys, and lexicographic.

**Acceptance criteria**

- Add Sort lines ascending and Sort lines descending. Preserve duplicates,
  original casing/whitespace, equal-key input order, and terminal-newline semantics.
- Add Join lines, Remove empty lines, Remove duplicate lines, Uppercase, and
  Lowercase with the specified exact behavior; no implicit trimming during sorting.
- All operations chain on the current draft. Add aliases such as `sort asc`,
  `sort desc`, `dedup`, and `unique` without changing history-search behavior.
- Unicode case expansion beyond the existing limit fails without replacing the
  draft; no output is silently truncated or committed by transformation alone.

**Verify**

Use the sorting/blank/deduplicate/join fixtures above as regression expectations.
Cover equal keys in descending order (a naive reverse must fail), duplicates,
terminal versus interior blank lines, CRLF/mixed separators, and complete data
beyond the preview limit. Run the model suite. In the isolated menu, search
`sort asc`, `descending`, and `dedup`, chain sort plus deduplicate, then copy the
preview to the recording transport. Exercise the expanding `ß` fixture and cancel
without modifying the synthetic source history. Run QML lint and validation.

## Task 4: Color conversions, screen picking, and domain copies

**Status:** completed 2026-09-11. **Context:** `colorDetails`, row host metadata, and Task 2's
confirmed generated-text submission already provide the reusable behavior.

**Acceptance criteria**

- Add the three color Copy as actions and Edit color expression. Reuse existing
  normalized values, including alpha, without rewriting the original expression.
- Add Copy domain for links using derived host metadata; retain the original URL
  for normal copy/paste and Task 1's Open in browser action.
- Pick from screen invokes installed hyprpicker without autocopy, releases the
  overlay keyboard grab, validates returned color text, and opens an editable
  draft. Cancellation restores the previous view without clipboard/history changes.
- Derived copies obey existing unavailable/oversized-history/write-confirmation
  guards. Tool failure or delayed completion after cancellation cannot dispatch
  a copy or reopen a closed/replaced context unexpectedly.

**Verify**

Run the existing model suite plus any new consumer-boundary regressions. In the
isolated UI, search `rgba` and `hsl`, copy opaque/translucent colors and a domain to
the recording transport, and verify original expressions/URLs remain intact.
Exercise write refusal. Run actual hyprpicker against a synthetic swatch without
`--autocopy`, accept into the draft, then cancel a second pick. Check missing-tool
and closed-context completions. Run QML lint and plugin validation.

## Task 5: Image paths, containing folders, and saved copies

**Status:** completed 2026-09-11. **Context:** prepared rows already distinguish captures and
single local image-file URIs. QtQuick.Dialogs is installed; use its save dialog.

**Acceptance criteria**

- Add Copy image path and Open containing folder for both image sources, using
  validated decoded absolute paths and argv-based dispatch. Do not route file URIs
  through the stock plain-text opener or treat them as URLs.
- Add Save a copy as with a source-format filename, byte-for-byte copying, and
  existing-destination refusal. Cancel writes nothing; unreadable/missing sources
  and failed copies produce errors, not fallback clipboard operations.
- Release the layer-shell keyboard grab for the file dialog, restore context on
  cancellation/failure, and keep delayed dialog/process completion tied to the
  original action snapshot rather than current history selection.

**Verify**

Use both real synthetic image files, including spaces/Unicode in their names.
In the actual UI, verify path-copy bytes, folder dispatch arguments, and the real
save dialog's focus/cancellation. Save to a fresh temporary destination and compare
checksums with the source. Choose an existing destination and prove neither file
changes. Remove a fixture before execution and verify a visible failure. Reorder
synthetic history during the dialog and confirm it cannot act on a different row.
Run the model suite, QML lint, and plugin validation.

## Task 6: Non-destructive editing in Tensaku

**Status:** completed 2026-09-11. **Context:** the stock `tensaku-edit` wrapper saves to its input
path; blindly reusing it would overwrite the source. Task 5 provides validated
image paths and external-window focus/lifecycle handling.

**Acceptance criteria**

- Add Edit a copy in Tensaku for both image sources. Make a private temporary
  duplicate with restrictive permissions before launching the installed editor.
- Invoke Tensaku directly on the duplicate with a unique valid application ID,
  its duplicate output path, and the existing copy-on-Enter behavior. The input
  must never be the original. A distinct instance must remain trackable until its
  window exits; do not infer lifetime merely from a launcher returning.
- Retain action-owned files while the editor is alive, even after the clipboard
  overlay closes. Delete only those temporary files after verified exit or failed
  launch; no broad cleanup of stock image directories or user-selected files.
- Use the editor's existing clipboard export and stock capture pipeline for edited
  images. Do not add a capture service, custom image-history writer, or dependency.
  Cancellation/failure leaves the original untouched and reports real failures.

**Verify**

Launch actual Tensaku on the synthetic duplicate, annotate it, and export through
a temporary recording copy command rather than the personal clipboard. Compare
original checksums before/after both saving and canceling. Close the clipboard
overlay while the editor stays open and confirm the duplicate is still available.
Verify a second editor action cannot collide with the first, and cleanup occurs
only after each tracked editor exits. Exercise missing executable/copy failure.
Run the model suite, QML lint, and plugin validation after integration.

## Feature completion gate

After all six slices work together, run once from the repository root:

```sh
node tests/clipboard-history.js
bash tests/clipboard-files.sh
qmllint -I "$OMARCHY_PATH/shell" Clipboard.qml
omarchy plugin validate .
```

Smoke the complete actions palette on every supported type and in the editor,
including searching, both sort directions, chaining, cancellations, external focus,
and stale/read/write failures. Recheck unchanged filters, direct shortcuts,
expanded previews, adaptive height, smooth scrolling, removal, and clear confirmation.
Record visual versus dispatch-only verification precisely; tests alone do not
prove UI behavior or real browser/clipboard delivery.

**Completed verification — 2026-09-11**

- Model regressions, image-file safety/lifecycle regressions, QML lint, and local
  plugin validation pass. File regressions cover literal path arguments, existing
  destinations and symlinks, partial-copy failures, missing executables, independent
  editor sessions, interruption, and cleanup after tracked child exit.
- The actual isolated overlay exercised full-payload transformations beyond the
  preview bound, both sort directions, chaining, real text editing, empty-draft and
  expansion refusals, and exact confirmed Copy/Paste output. Canonical drafts
  preserve CRLF despite TextEdit's normalized display. An actual filesystem write
  refusal preserved the draft and delivered neither clipboard data nor paste keys.
- Color formats, link domains, and both native/file-URI image paths were copied
  through the guarded history pipeline. A real hyprpicker selection opened an
  editable color draft without autocopy. Controlled cancellation, invalid output,
  missing executable, and a late canceled picker could not mutate a reopened view.
- The real native save dialog canceled cleanly and saved the original captured
  image even after history reordered. Existing destinations stayed unchanged;
  missing sources failed visibly. Folder and browser opening were verified as
  argument dispatch, not real file-manager/browser delivery.
- Real Tensaku annotated and exported a synthetic image through a recording copy
  boundary. The original stayed unchanged. Two simultaneous editor instances used
  distinct private copies; closing Clipboard Plus kept both copies alive, and
  closing either editor removed only its own copy and directory.
- Rechecked numeric filters/cycling, expanded-view dismissal, fractional history
  scrolling, removal, and clear confirmation. The 19-action popup measured
  430×398 inside the unchanged 940×620 card. The overflow indicator was visually
  confirmed, moved with scrolling, and hid for fitting/empty results. A hidden
  constrained-height probe stayed inside the card. Deferred layout now retains
  selection; immediate wraparound keeps the final action visible.
- All runtime checks used synthetic history and recording clipboard/key/browser
  boundaries. No personal history or clipboard, installed plugin, production
  shell, marketplace, or release state was changed.

**Independent review — completed 2026-09-11:** Claude Code, effective
**Fable 5.1 with max effort**, through `herdr-delegate`. No high-severity findings.
The parent resolved the review as follows:

- Fixed hover passing through the Actions scrim. The bug was reproduced with
  native pointer motion and locally targeted QtTest events; the same QtTest
  reproduction now preserves selection and keeps the menu open. Escape preserves
  the source selection, and an action still executes through the palette.
- Fixed empty hyprpicker exit status 2 being reported as a failure. An isolated
  picker process reproduced the old error and now restores the view without
  changing history or clipboard; status 1 still reports failure. The attempted
  native Escape check was interrupted, so final cancellation verification is an
  exit-status regression, not a claimed native-keypress verification.
- Documented private-copy retention if plugin/shell teardown kills the worker
  before its cleanup trap can run. Normal overlay closure and tracked editor
  exit remain verified. No detached service or premature file deletion was added.
- Retained atomic hard-link publication and documented unsupported filesystems.
  The error now names filesystem support, permissions, and destination conflicts.
  Injected publication failure left the source unchanged, published no destination,
  and removed staging data; no replacing fallback was added.

All four integration commands passed again after the source fixes. The reviewer
exited and its dedicated pane was closed; review findings were not treated as
permission to deploy, commit, or change release state.

The user subsequently authorized local activation of that feature checkpoint.
Those runtime files were copied into the local installation, validated, and
loaded with a warned shell restart. Live calls to a newly added method confirmed
the updated component was running.

Release presentation is prepared: README highlights the completed actions,
documents the bundled picker/editor and all four development checks, and includes
fresh overview and Actions screenshots. Both were captured from the unchanged
installed UI on an empty workspace with isolated sample history.

**Image-save correction — verified 2026-09-11**

- Replaced named staging with an anonymous file held open through publication.
  Source bytes and the selected destination directory remain bound to their
  opened files; an existing destination is still refused atomically.
- `ClipboardCopy.py` uses only the system Python standard library. Saving now
  requires both `O_TMPFILE` and hard-link support; unsupported destinations fail
  visibly without a named or replacing fallback.
- An independent design review supported this approach and found no required QML
  change. The parent inspected the implementation, isolated Python startup, and
  added a regression for a destination directory being moved during a copy.
- Model regressions, file/descriptor and editor-lifetime regressions, QML lint,
  and plugin validation pass. Real worker commands saved a byte-identical
  screenshot with mode `0600` on tmpfs and btrfs, and refused an existing file
  without changing it. Fixtures contained no personal clipboard/history data.
- The two screenshots and QML remain unchanged by this correction. The helper
  correction has not been copied into the previously activated local installation.

After successful behavioral smoke tests, update README controls/action semantics
and these documents' actual statuses, synchronize ignored memory, and remove
throwaway harness artifacts. Do not add tests that merely assert menu wording,
source wiring, or implementation structure. Refresh the separately authorized
local installation only under its existing workflow and warn before any supported
shell restart. No completion step implies permission to commit, push, publish,
change main, or bump the manifest version.
