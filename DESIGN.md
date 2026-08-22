# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-22
- Primary product surface: `examples/research-shelf.etaf` + `examples/research-shelf.el`
- Visual reference: `design/research-shelf.html`
- Evidence reviewed: ETAF public View/Component/Data/Resource APIs, `etaf-ui`
  Button/Checkbox/Panel/DataGrid/Pagination, and `etaf-sqlite`'s typed source
  contract.

## Brand

- Personality: editorial, focused, warm, quietly intelligent.
- Trust signals: durable SQLite data, visible save state, selected-item detail,
  explicit progress/status, and recoverable storage errors.
- Avoid: generic admin dashboards, KPI walls, fake charts, rainbow gradients,
  and a showcase that exists only to exercise APIs.

## Product goals

- Build a useful personal reading/research shelf backed by a real SQLite file.
- Make triage, selection, progress updates, filtering, pagination, and
  recovery feel like one coherent product rather than isolated demos.
- Exercise existing ETAF components through composition before adding any new
  component type.
- Keep the static `.etaf` file responsible for shell/section composition while
  the `.el` companion owns storage, state, callbacks, and lifecycle.

## Personas and jobs

- Primary persona: an Emacs user collecting papers, books, essays, and notes.
- Jobs: find what to read next, filter by state/priority, inspect one item,
  update progress, mark an item finished, and recover after a storage error.
- Contexts: compact desktop window, fullscreen review, keyboard-first use, and
  a local SQLite database that survives unmount/remount.

## Information architecture

- Shell: compact brand bar -> filter rail -> reading list -> detail inspector.
- Filter rail: All, In progress, Unread, Finished, and Starred; each is a real
  action and the list summary exposes the matching count.
- Reading list: title/author/status/progress rows, single selection, paging,
  empty/loading/error states.
- Detail inspector: title, author, type, status, progress, priority, note,
  last updated, and actions (`+10%`, `Finish`, `Star`, `Archive`).
- Footer: database path/status, visible result count, and current page.

## Design principles

1. One useful workflow: every visible control helps decide or update what to
   read next.
2. Editorial hierarchy over dashboard chrome: one strong title, restrained
   metadata, and generous whitespace around the selected record.
3. State is durable and observable: SQLite is the source of truth; UI status
   tells the user when a mutation is loading, saved, or failed.
4. Composition first: reuse public UI Components and keep storage/state in the
   companion, not in `.etaf` or a parallel widget layer.
5. Fail closed: a SQLite failure keeps the last usable list and exposes a
   retry action instead of replacing the whole surface with a stack trace.

## Visual language

- Color: ink `#172033`, paper `#F7F3EA`, cobalt `#3657D6`, mint `#3E9B8F`,
  coral `#D86B5D`, amber `#C58A3A`, muted slate `#6D7482`.
- Typography: readable proportional labels with compact monospace metadata;
  title and selected record use bold weight, not oversized headings.
- Spacing/layout rhythm: 1-cell outer rhythm, 2-cell panel padding, 1-cell
  grid gaps, and stable intrinsic control widths.
- Shape/elevation: thin borders, small radius-like grouped rows where Ebox
  permits, no floating overlays or decorative shadows.
- Motion: immediate state changes; no timer-driven animation; reduced-motion
  safe by construction.
- Imagery/iconography: Unicode marks with semantic meaning: `⌕`, `★`, `✓`,
  `◷`, `↗`, `⚠`, and `·`.

## Components

- Existing components to reuse: public `button`, `checkbox`, `label`, `panel`,
  `data-grid`, and `pagination` from `etaf-ui`.
- Companion composition: `research-shelf-shell`, `filter-rail`,
  `reading-list`, and `detail-inspector`; these are ordinary ETAF Components,
  not a second UI kit.
- Variants/states: light/dark Theme, selected/unselected row, starred, empty,
  loading, error, saved, disabled-at-boundary, and archived.
- Token ownership: palette and spacing tokens live in the companion; `.etaf`
  contains only validated structural facts and labels.

## Playground framework boundary

- `etaf-playground.el` is a reusable framework, not an application module.
- The framework owns pair registration semantics, safe inert `.etaf` parsing,
  companion loading, mount/reset/close, and test/GUI entry points. Replaceable
  deployment metadata lives in `etaf-playground-catalog.el`, outside the
  loader implementation.
- A pair companion owns its Components, storage adapters, state, resources,
  events, and root factory. The framework must not reference a business
  component, database package, table schema, palette, or application-specific
  ref.
- Reuse is expressed through the generic manifest/loader contract and the
  existing public ETAF/etaf-ui components. New business behavior belongs in a
  same-basename pair, never in the framework.
- Any future Playground example must add a catalog entry and its own `.etaf`/
  `.el` files without changing framework semantics.

## Accessibility

- Target: keyboard-complete and high-contrast desktop UI.
- Keyboard/focus: Tab order follows filters -> rows -> detail actions -> pager;
  RET dispatches the focused public ref; selected row is announced in text.
- Color is never the only state signal; status uses text and Unicode marks.
- Disabled actions remain visible with disabled semantics and explanatory help.

## Responsive behavior

- Wide/fullscreen: three-column grid (rail / list / detail).
- Compact: rail becomes a top filter row, detail follows the list, and all
  controls remain intrinsic single-line widths.
- Use `grid` for the product skeleton, `flex` for toolbars and action groups,
  and `row` only for compact intrinsic controls.

## Interaction states

- Loading: list keeps its frame and shows `◷ Loading library…`.
- Empty: selected filter explains why there are no matches and offers `All`.
- Error: storage card shows `⚠ Could not save` with `Retry`; last committed
  data remains visible.
- Success: mutation shows `✓ Saved locally` and updates `updated` metadata.
- Disabled: `Finish` is disabled for finished records; `+10%` is disabled at
  100%; archive is disabled while loading.

## Content voice

- Tone: concise, observant, and useful; never framework-centric in primary UI.
- Terminology: Reading, In progress, Finished, Starred, Saved locally,
  Storage issue.
- Microcopy: action + result (`Mark finished`, `Saved locally`) instead of
  generic `Done`.

## Implementation constraints

- Framework/styling: public ETAF View DSL and `etaf-ui`; SQLite through the
  sibling `etaf-sqlite` package; no HTML/CSS runtime dependency.
- Data schema: one typed `reading_items` SQLite table with id/title/author/
  kind/status/progress/priority/starred/note/updated columns.
- Performance: one Data mutation -> one Runtime generation/publication; normal
  warm actions remain under the existing 100ms p50 target.
- Compatibility: one same-basename `research-shelf` pair only; old console
  examples are removed from the active manifest and compile surface.
- Verification: SQLite temp-file integration tests, pair mount/remount tests,
  repeated selection/mutation tests, and clean fullscreen GUI screenshots.

## Open questions

- [ ] User may rename the product after reviewing the first HTML/ETAF render;
  architecture and interaction contracts remain unchanged.
