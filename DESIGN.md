# Design

## Source of truth

- Status: Active
- Last refreshed: 2026-08-23
- Primary product surface: generic `etaf-playground.el` workspace plus the
  `examples/research-shelf.etaf` / `.el` / `.ecss` consumer triplet
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
  current active latency lane uses 5 unmeasured warmups and 30 measured samples
  at fixed 1413×62 geometry; every scenario must satisfy p95 and max at or below
  50ms. The accepted 105ms p50 wording is historical design context, not the
  current evaluator gate; `DOC-PERF-001` keeps its formal disposition in M0b1.
- Compatibility: any same-basename `.etaf`/`.el` example is discoverable;
  `.ecss` is optional, and the bundled Research Shelf remains only one
  consumer.
- Verification: inert reader tests, source-tab/session tests, unsaved source
  refresh tests, SQLite temp-file integration tests, mount/remount tests,
  repeated selection/mutation tests, and clean GUI screenshots.

## Performance evidence lanes

The latency lane, trace lane, and GUI lane share one
repository/environment/scenario/fixture/build identity but remain separate
measurements. The latency lane owns the uninstrumented 5/30 p95/max 50ms gate.
The trace lane owns a representative instrumented invocation with cost class,
work counters, turns, allocation, and GC. The GUI lane owns the real Emacs
action sequence, screenshots, recording, and temporal-review verdict. Batch
verifier duration is not GUI first paint; action-start through forced redisplay
completion remains an explicitly separate future first-paint gate and an M0a
observed gap. No one lane may be used to claim another lane passed.

## Open questions

- [ ] User may rename the product after reviewing the first HTML/ETAF render;
  architecture and interaction contracts remain unchanged.
