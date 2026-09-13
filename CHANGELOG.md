# Changelog

## Unreleased

### Changed

- ECSS companions contain one plain ordered rule list. Remove the `styles`
  wrapper and write `nil` for an empty file. Preview uses the shared ECSS reader
  for files and unsaved source; components validate declarations through Ebox.
  Blank files are rejected.
