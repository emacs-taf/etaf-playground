# Design

## Source of truth
- Status: Active
- Last refreshed: 2026-08-05
- Primary product surfaces: `etaf-playground-open`, `etaf-playground-open-ui`, and the interactive `etaf-playground-open-showcase` application.
- Evidence reviewed: `etaf-playground.el`, `tests/etaf-playground-tests.el`, `README.md`, `README.zh-CN.md`, the rendered current Showcase, and `../emacs-box/examples/playground/flex-reference.ebox` rendered fullscreen in GUI Emacs.

## Brand
- Personality: Precise, calm, modern, technical, and intentionally crafted rather than framework-generic.
- Trust signals: Exact alignment, readable contrast, stable geometry during updates, consistent semantic colors, and examples that visibly exercise the public ETAF model.
- Avoid: Default-Emacs-looking unstyled text, saturated dashboard colors, pastel text on tinted backgrounds, decorative noise, huge empty regions, and controls that look indistinguishable from ordinary copy.

## Product goals
- Goals: Make ETAF feel capable through a polished runnable application; teach View, Component, Context, Data, Grid, retained state, and events through visible structure; keep every example usable through public APIs only.
- Non-goals: Browser imitation, bitmap artwork, a separate styling framework, hidden example-only rendering paths, or pretending the small current `etaf-ui` catalog is feature-complete.
- Success signals: The first frame reads as a deliberate application; navigation, data changes, and theme changes preserve hierarchy and geometry; screenshots show no clipping, continuation indicators, unintended wrapping, or low-contrast text.

## Personas and jobs
- Primary personas: ETAF application authors, Ebox/ETAF maintainers, and evaluators deciding whether the new architecture is usable.
- User jobs: Understand the framework quickly, copy public patterns, inspect a realistic interactive flow, and verify that updates remain visually stable.
- Key contexts of use: GUI Emacs in a single application buffer, fullscreen demonstrations, and batch/ERT verification.

## Information architecture
- Primary navigation: A persistent horizontal command strip with Overview, Work items, and Theme destinations.
- Core routes/screens: Overview dashboard, interactive Work items table, Theme and semantics gallery, compact core counter example, and optional `etaf-ui` catalog example.
- Content hierarchy: Branded application header, persistent navigation, page title and supporting copy, primary cards/table, contextual action strip, and a quiet status bar.

## Design principles
- Principle 1: Teach through visible grouping; every capability receives a labeled, bounded surface instead of becoming an undifferentiated text stream.
- Principle 2: Use the Flex reference's warm restrained palette and one-pixel borders to create hierarchy without relying on shadows or browser-only effects.
- Principle 3: Geometry is part of correctness; viewport-sized owners contain their borders, children fit the owner's content box, and updates must not introduce wrapping or truncation markers.
- Tradeoffs: Prefer a dense desktop Emacs composition over excessive whitespace; prefer fixed readable card widths inside a responsive outer shell over fragile full-viewport arithmetic on every child.

## Visual language
- Color: Warm canvas `#F8F5EE`; paper `#FFFDF8`; ink `#252A2E`; muted ink `#66706A`; active terracotta `#B84F35`; tinted terracotta `#F1D4C9`; sage `#DCEBDD`; blue `#D9EAF2`; violet `#E7E2F1`; dark mode uses deep neutral surfaces with lighter versions of the same semantic accents.
- Typography: Emacs' configured monospace face; bold is reserved for titles, labels, key values, and active controls.
- Spacing/layout rhythm: One-line vertical section rhythm, 12–16 px horizontal gaps, 16–24 px section padding, and aligned card/table edges.
- Shape/radius/elevation: Square text-native surfaces, one-pixel borders, no fake radius or shadow.
- Motion: State changes publish directly and remain stable after redisplay; no decorative animation.
- Imagery/iconography: Text and restrained semantic glyphs only; no logos, emoji decoration, or bitmap chrome.

## Components
- Existing components to reuse: ETAF core Hosts, retained Components, Grid, Context theme values, Data Controller, and public event dispatch.
- New/changed components: Showcase section headers, metric cards, navigation items, task rows, action buttons, color swatches, compact status bar, and polished wrappers for the core/UI examples.
- Variants and states: Active navigation, selected task, enabled/disabled action, light/dark theme, success/review/open status, loading, empty, and error.
- Token/component ownership: Palette tokens live in `etaf-playground--showcase-palette`; each helper owns the surfaces it renders; ETAF/Ebox remain the layout and rendering owners.

## Accessibility
- Target standard: High-contrast keyboard-operable Emacs UI with explicit semantic roles and refs.
- Keyboard/focus behavior: Every actionable surface keeps `:role 'button`, `:tab-index 0`, stable refs, and visible active/selected styling.
- Contrast/readability: Every tinted surface has an explicit foreground; muted text remains readable on both canvas and paper; active controls use both color and border/background changes.
- Screen-reader semantics: Preserve labels, roles, refs, and `aria-label` where the framework exposes them.
- Reduced motion and sensory considerations: No animation is required; updates must remain usable with ordinary redisplay.

## Responsive behavior
- Supported breakpoints/devices: GUI Emacs windows from approximately 900 px wide through fullscreen desktop widths.
- Layout adaptations: The host measures the window body and reserves one character cell at the right edge; the outer shell owns viewport width; direct header/main/status surfaces stretch inside it; nested responsive containers omit width and let Ebox Flex allocate or wrap content.
- Touch/hover differences: None; keyboard and mouse press paths share the public event model.

## Interaction states
- Loading: Labeled bounded surface with visible status.
- Empty: Quiet explanatory surface with the next useful action when available.
- Error: High-contrast danger surface; errors remain visible instead of falling back silently.
- Success: Sage accent and explicit feedback text.
- Disabled: Muted foreground plus missing callback/tab stop.
- Offline/slow network, if applicable: Not currently applicable because the example uses the synchronous memory source.

## Content voice
- Tone: Direct, technical, concise, and self-explaining.
- Terminology: Use the canonical ETAF vocabulary: View, Component, Host, Context, Data Controller, Runtime, event, and public API.
- Microcopy rules: Name the capability being demonstrated, state the visible effect of actions, and avoid promotional filler.

## Implementation constraints
- Framework/styling system: Emacs 29.1+, ETAF public View/Component APIs, and Ebox public layout/style properties only.
- Design-token constraints: Reuse the palette helper and semantic token keys; do not add a parallel theme or CSS layer.
- Performance constraints: Interactive actions remain synchronous and bounded; visual polish must not add hidden full-tree work or timers beyond the existing viewport sync.
- Compatibility constraints: `etaf-playground` must remain independent from `ebox-playground` and must not call `ebox--*` private APIs.
- Test/screenshot expectations: `make check` passes; fullscreen GUI screenshots use one target buffer window; dynamic checks cover navigation, selection, insertion, theme toggle, and return to Overview; no visible truncation/continuation indicators or accidental wrapping are accepted.

## Open questions
- [ ] Expand the official `etaf-ui` catalog before presenting the catalog example as a migration-complete component gallery / maintainer / blocks parity claims.
