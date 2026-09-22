# Changelog

## Unreleased

### Changed

- Retained publication is now owned by Ebox. Update Ebox and ETAF together;
  the integration uses SPI v3 and `ebox-publication/v1`. Publication reports
  use `:publication-*` fields and the `ebox-publication` provider.


### Added

- Task rows compose the UI Menu with a confirmation dialog. Edit opens the
  existing form, incomplete tasks cannot be deleted, and declining confirmation
  preserves both data and focus. Draft-discard prompts use the same dialog.

- Make Task Workbench available through the Playground catalog. Its title/state form keeps a draft, validates blank titles, supports save/cancel and asks before discarding edits on task/filter changes. Search uses TextInput; native prompts share Ebox input lifetime.

### Fixed

- The preview mounts against its own window: a viewport-sized consumer (the
  desktop canvas) now fills the preview window instead of measuring whichever
  window was selected.

- The desktop GUI adapter addresses launcher entries, resize cells and window
  controls by their own references and bounds, so repeated labels in the shell
  cannot send an action to another window.  Taskbar restore also asserts the
  restored presentation a minimized maximized window actually keeps.

- Playground companions are now tracked by the source file the framework
  evaluated. A package feature that happens to share a companion's name (for
  example the `etaf-desktop` provider) no longer suppresses the companion's
  registration, so `C-c C-c` on the desktop example renders instead of
  reporting a missing `etaf-desktop-root`. `etaf-playground-register-example`
  no longer accepts `:feature`/`:companion-feature`; registration only
  overrides the root factory.

- Research Shelf detail notes use the UI Label's constrained text layout, so
  long notes wrap inside the inspector after selection and window resizing.
  Update UI together with the example for Label's Box layout support.

- Workbench actions and component updates no longer print lifecycle messages
  into the minibuffer, keeping ordinary interaction and viewport geometry stable.

- Workbench task cells reserve enough room to display both control captions in
  compact and wide layouts. Its callbacks use committed props directly, and the
  Add button uses an instance-local Host reference for independent workbenches.

### Changed

- Research Shelf keeps its light/dark colors in one semantic palette plist and
  resolves it through ETAF. Theme toggles retain their colors without a global
  palette registry or renderer-specific channels.

- Research Shelf loads its SQLite backend through the `etaf-db` package entry.
  Install `etaf-db` in place of the former `etaf-sqlite` package dependency;
  the example continues to use the same SQLite Data Source API.

- Task Workbench now loads and saves asynchronously, retains drafts and accepted rows on failure, and offers read-only recovery after committed writes or a lost receipt. Native controls expose cancellation, timeout and out-of-order search scenarios; service health uses the same asynchronous protocol.
- Workbench GUI acceptance waits for task publication between actions. Batch diagnostics include delayed completion; wall samples include provider waiting and use a new timing boundary, so previous synchronous reports are not comparable. Separate local processing latency certification remains pending.

- Workbench's local theme and help controls use UI ref bindings. Task mutations
  and page-size changes retain explicit callbacks for their Data operations.

- Research Shelf and Task Workbench declare stable Context, state and resource
  handles with Component `:bindings`. Views and callbacks use those names
  directly; update ETAF to a revision supporting instance bindings.

- ECSS companions contain one plain ordered rule list. Remove the `styles`
  wrapper and write `nil` for an empty file. Preview uses the shared ECSS reader
  for files and unsaved source; components validate declarations through Ebox.
  Blank files are rejected.
