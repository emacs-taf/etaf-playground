# Changelog

## Unreleased

### Added

- Make Task Workbench available through the Playground catalog. Its title/state form keeps a draft, validates blank titles, supports save/cancel and asks before discarding edits on task/filter changes. Search uses TextInput; native prompts share Ebox input lifetime.

### Fixed

- Workbench task cells reserve enough room to display both control captions in
  compact and wide layouts. Its callbacks use committed props directly, and the
  Add button uses an instance-local Host reference for independent workbenches.

### Changed

- Workbench's local theme and help controls use UI ref bindings. Task mutations
  and page-size changes retain explicit callbacks for their Data operations.

- Research Shelf and Task Workbench declare stable Context, state and resource
  handles with Component `:bindings`. Views and callbacks use those names
  directly; update ETAF to a revision supporting instance bindings.

- ECSS companions contain one plain ordered rule list. Remove the `styles`
  wrapper and write `nil` for an empty file. Preview uses the shared ECSS reader
  for files and unsaved source; components validate declarations through Ebox.
  Blank files are rejected.
