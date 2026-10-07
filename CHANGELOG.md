# Changelog

## Unreleased

### Changed

- Retained publication is now owned by Ebox. Update Ebox and ETAF together;
  the integration uses SPI v3 and `ebox-publication/v1`. Publication reports
  use `:publication-*` fields and the `ebox-publication` provider.


### Added

### Fixed

- A preview reuses an already loaded source or compiled example companion.
  Preloading Research Shelf before mounting no longer registers its Actions
  twice, while unrelated libraries with the same feature name remain distinct.

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

### Changed

- Research Shelf keeps its light/dark colors in one semantic palette plist and
  resolves it through ETAF. Theme toggles retain their colors without a global
  palette registry or renderer-specific channels.

- Research Shelf loads its SQLite backend through the `etaf-db` package entry.
  Install `etaf-db` in place of the former `etaf-sqlite` package dependency;
  the example continues to use the same SQLite Data Source API.

- Research Shelf declares stable Context, state and resource handles with
  Component `:bindings`. Views and callbacks use those names directly; update
  ETAF to a revision supporting instance bindings.

- ECSS companions contain one plain ordered rule list. Remove the `styles`
  wrapper and write `nil` for an empty file. Preview uses the shared ECSS reader
  for files and unsaved source; components validate declarations through Ebox.
  Blank files are rejected.

### Removed

- Task Workbench and its benchmark, GUI adapter, acceptance cases and
  performance targets are gone; the reference-application position awaits a
  replacement. The former sources remain in Git history.
