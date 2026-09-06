# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-09-05
- Primary product surface: generic `etaf-playground.el` workspace plus the
  `examples/research-shelf.etaf` / `.el` / `.ecss` consumer triplet
- Additional product surface: `examples/task-workbench.el`, a complete
  composable task app. Its initial layout, interactions, and visual states are
  checked in real GUI Emacs; current user direction is modern, spacious,
  consistently aligned controls and a 100-task dataset.
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
- Ship a deterministic 256-record fixture by default so pagination and warm
  incremental updates are exercised on a realistic surface; fixture size and
  page size remain configurable for focused tests.
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
  workspace gaps, and stable intrinsic control widths.
- Shape/elevation: thin borders, small radius-like grouped rows where Ebox
  permits, no floating overlays or decorative shadows.
- Motion: immediate state changes; no timer-driven animation; reduced-motion
  safe by construction.
- Imagery/iconography: Unicode marks with semantic meaning: `⌕`, `★`, `✓`,
  `◷`, `↗`, `⚠`, and `·`.

## Components

- Existing components to reuse: `etaf-button`, `etaf-checkbox`, `etaf-label`,
  `etaf-panel`, `etaf-data-grid`, and `etaf-pagination` from `etaf-ui`.
- Companion composition: `research-shelf-shell`, `filter-rail`,
  `reading-list`, and `detail-inspector`; these are ordinary ETAF Components,
  not a second UI kit.
- Variants/states: light/dark Theme, selected/unselected row, starred, empty,
  loading, error, saved, disabled-at-boundary, and archived.
- Token ownership: palette and spacing tokens live in the companion; `.etaf`
  contains only validated structural facts and labels.

## Playground framework boundary

- `etaf-playground.el` is a reusable source/preview workspace, not an
  application module. It discovers same-basename `.etaf`/`.el` files and an
  optional `.ecss` file, creates the left source session, and mounts the right
  preview.
- The framework owns inert source readers, companion registration overrides,
  source tabs, window layout, refresh/reset/close, and ETAF Runtime lifecycle.
  It does not require a catalog or name a business application.
- A companion owns its Components, storage adapters, state, resources, events,
  style consumers, and root factory. The framework must not reference a
  business component, database package, table schema, palette, or
  application-specific ref.
- `.etaf` and `.ecss` are read as data. `.el` is evaluated only when a preview
  is first loaded or the companion source is explicitly dirty; normal ETAF
  duplicate-definition errors remain intact outside that deliberate reload
  boundary.
- New examples add a same-basename `.etaf`/`.el` pair and may add `.ecss`; the
  generic framework and its build file do not change.

## Research Shelf companion boundary

Research Shelf is intentionally compact: the executable companion is one file,
with comments making the small app's boundaries visible:

```text
examples/research-shelf.etaf                inert structure source
examples/research-shelf.ecss                inert style source
examples/research-shelf.el                  DATA / THEME / STATE / VIEW / ROOT
```

The `.el` file is the only Playground registration point and palette owner:
its THEME section may use the optional `etaf-theme-tp` adapter to turn
TP light/dark pairs into an ETAF semantic Theme plist. The rest of the app
never calls TP or embeds renderer palette names. The VIEW section creates a
Data Controller inside the shell Component, so ETAF owns its effect Scope and
disposes the SQLite source with the Component. Detail and filter Components
consume Context and dispatch named Actions; they do not reach into SQLite or
duplicate selection matching. The `.etaf` structure and `.ecss` tokens are
applied at the root. If the product grows beyond this size, these commented
sections can later move into modules without changing the public Playground
triplet.

## Accessibility

- Target: keyboard-complete and high-contrast desktop UI.
- Keyboard/focus: Tab order follows filters -> rows -> detail actions -> pager;
  RET dispatches the focused public ref; selected row is announced in text.
- Color is never the only state signal; status uses text and Unicode marks.
- Disabled actions remain visible with disabled semantics and explanatory help.

## Responsive behavior

- Wide/fullscreen: one Flex line presents rail / list / detail as three columns.
- Medium: rail and list remain together while detail wraps to the next line.
- Narrow: the same three Components wrap in document order into a vertical flow.
- The shell uses one wrapping Flex composition with semantic basis/grow weights;
  it does not read window size or maintain breakpoint state. Use `row` only for
  compact intrinsic controls and Flex whenever free space must be distributed.

## Interaction states

- Loading: list keeps its frame and shows `◷ Loading library…`.
- Empty: selected filter explains why there are no matches and offers `All`.
- Error: storage card shows `⚠ Could not save` with `Retry`; last committed
  data remains visible.
- Success: mutation shows `✓ Saved locally` and updates `updated` metadata.
- Disabled: `Finish` is disabled for finished records; `+10%` is disabled at
  100%; archive is disabled while loading.
- Page density: activating `Rows N ✎` uses Emacs's native minibuffer to accept
  any integer from 1 through 100, then reloads page one.

## Content voice

- Tone: concise, observant, and useful; never framework-centric in primary UI.
- Terminology: Reading, In progress, Finished, Starred, Saved locally,
  Storage issue.
- Microcopy: action + result (`Mark finished`, `Saved locally`) instead of
  generic `Done`.

## Implementation constraints

- Framework/styling: source/preview orchestration is public ETAF API only;
  concrete examples may use `etaf-ui` and `etaf-sqlite`; no HTML/CSS runtime
  dependency.
- Public authoring boundary: intentional hot reload goes through
  `etaf-component-redefine-run`; application code does not bind ETAF private
  registry variables. Controllers created in Component setup use automatic
  Scope ownership, and selected rows use `etaf-data-selected-item` with an
  explicit `:item-key`.
- Data schema: one typed `reading_items` SQLite table with id/title/author/
  kind/status/progress/priority/starred/note/updated columns.
- Pressure fixture: `etaf-research-shelf-fixture-size` defaults to 256 and
  `etaf-research-shelf-page-size` defaults to 12; existing local rows are
  preserved and missing fixture rows are topped up with fresh IDs.
- Performance: one Data mutation -> one Runtime generation/publication. The
  retained Research Shelf batch evaluator uses 5 unmeasured warmups and 30
  measured samples at fixed 1413×62 geometry, with p95 and max at most 50ms.
  Current GUI acceptance has the additional requirements below. The accepted
  105ms p50 wording is historical design context, not the current evaluator
  gate; `DOC-PERF-001` keeps its formal disposition in M0b1.
- Compatibility: any same-basename `.etaf`/`.el` example is discoverable;
  `.ecss` is optional, and the bundled Research Shelf remains only one
  consumer.
- Verification: inert reader tests, source-tab/session tests, unsaved source
  refresh tests, SQLite temp-file integration tests, mount/remount tests,
  repeated selection/mutation tests, and clean GUI screenshots.

## Performance evidence lanes

The batch latency lane, trace lane, and GUI lane share one
repository/environment/scenario/fixture/build identity but remain separate
measurements. The retained Research Shelf 1413×62 batch evaluator owns its
uninstrumented 5/30 p95/max 50ms regression checks. Batch verifier duration
measures batch Lisp work, not GUI first paint.
The trace lane owns a representative instrumented invocation with cost class,
work counters, turns, allocation, and GC. The GUI lane owns the real Emacs
action sequence and reviewed visual evidence. Current GUI acceptance additionally
requires three independent foreground sample sets with each operation's p95 and
max at most 50ms from action callback through forced redisplay. This gate remains
outstanding. Preserve all warmups, GC observations and samples through the
measurement entry in `../etaf/scripts/README.md`; returning from redisplay does
not certify compositor presentation. No one lane may be used to claim another
lane passed.

## Open questions

- [ ] User may rename the product after reviewing the first HTML/ETAF render;
  architecture and interaction contracts remain unchanged.

## Task Workbench visual contract

- Source: user review of the actual Workbench GUI on 2026-09-05, especially
  adjacent buttons, cramped rows and excessive detail-panel width. Reuse the
  existing restrained cobalt emphasis; no separate design-system layer.
- Hierarchy: a title and quiet workspace subtitle, a grouped toolbar, then
  filter rail / primary task list / compact detail and service cards. Footer
  counts and storage scope use muted text. The task list receives extra width.
- Color: cool gray canvas, white cards, soft slate borders, cobalt primary
  action; dark mode has a charcoal canvas and lighter slate cards. All official
  control states use the existing semantic Theme tokens, including disabled,
  selected, checkbox and pagination colors.
- Actions: New task is primary. Search and retry are secondary; location,
  deletion and error simulation are quiet controls. The current filter is
  derived from the Data query and visibly distinct. Disabled controls retain
  their official semantics and palette.
- Rhythm: 10px within a horizontal control group, 16px between workspace
  columns, one text line between vertical groups, and `(1 2)` card padding.
  Ebox Row `:item-gap` is pixels; Column `:item-gap` is lines. Flex uses
  `:gap '(1 (16))` for one line vertically and 16px horizontally. Keep buttons
  compact with horizontal padding, rather than making every table row tall.
- Data: 100 deterministic tasks, mixed completion states, 10 rows per page.
  Test all pages, search, filtering, selection, CRUD, two independent Apps and
  resource recovery. Do not replace the real dataset with a smaller acceptance
  fixture. Initial seed titles remain stable for reproducible input checks.
- Responsive: retain declarative Flex wrapping in source order. Side columns
  have stable basis sizes; the task list grows. Root padding and viewport scroll
  are legitimate composition and must work together without example workarounds.
- Panel alignment: each workspace Flex line stretches its columns to a shared
  height, keeping the filter panel's bottom aligned with the main content. A
  wrapped row sizes independently; no viewport-specific height constants.
- Width distribution: filter/list/inspector grow with weights `1/4/1`, keeping
  emphasis on the task list while a side column fills its line when wrapped.
  Filter buttons wrap into a horizontal group when their panel has room.
  Detail and service cards share a wrapping Flex: stacked in the desktop side
  column, side by side with equal heights on a wider wrapped row, then stacked
  again when each card's usable minimum width no longer fits.
- Table sizing: the task title receives the remaining column width through the
  existing `(fr 1)` Grid track convention; the action column keeps its compact
  character width. Header and body consume the same tracks. Resizing changes
  geometry without replacing custom cell state or semantic identity.
- Pagination: full previous/next buttons with readable labels and horizontal
  padding, a quiet centered page/range summary, and clear disabled states.
  Workbench uses Chinese labels; the shared component retains configurable text.
- Acceptance: inspect light/dark, selected/disabled, wide/compact and scrolled
  GUI states after functional checks. Preserve the goal's three real GUI
  performance sample sets with per-operation p95 and max at most 50ms.
- Assumption: no new brand was requested; the repository's existing cobalt,
  neutral surfaces and typography are the design basis.
