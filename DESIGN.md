# Design

## Source of truth

- Status: Active draft for the sole reviewed pair
- Last refreshed: 2026-08-20
- Primary product surface: `examples/operations-console.etaf` + `examples/operations-console.el`
- Visual reference: `design/operations-console.html`
- Evidence reviewed: current pair loader/manifest, `etaf-ui.el`, Ebox viewport contract, and the current GUI/performance evidence.

## Brand

- Personality: calm operations cockpit; precise, warm, and quietly technical.
- Trust signals: explicit status chips, visible last-updated time, deterministic counts, clear success/error feedback.
- Avoid: generic toy dashboard, rainbow gradients, dense ungrouped controls, decorative widgets with no semantic state.

## Product goals

- Make one attractive app prove ETAF's Component, composition, reactive, Context/Theme, Behavior, event/Action, Data, Resource, error-boundary, focus, and lifecycle contracts.
- Do not add another Playground scenario or hide framework limitations behind fake animation.
- Keep the HTML prototype and ETAF rendering aligned in hierarchy, state labels, interaction outcomes, and compact/fullscreen geometry.

## Personas and jobs

- Primary personas: ETAF framework reviewer and application author learning the public API.
- User jobs: understand the layout model, trigger each capability, inspect visible state changes, and verify recovery/cleanup behavior.
- Key contexts: 900–940 px compact GUI, fullscreen GUI, keyboard-only review, and batch semantic tests.

## Information architecture

- Shell: brand/header -> navigation tabs -> page surface -> persistent status footer.
- Overview: hero/status strip, KPI cards, activity/control workspace, capability cards, and event timeline.
- Data: query/selection summary, interactive DataGrid, and selection detail panel.
- Resource: resource status, reload/fail-next controls, boundary result, and cleanup counter.
- Content hierarchy: page title and status first; primary action second; diagnostics/details third.

## Design principles

1. One visual hierarchy: every control belongs to a named surface and every surface has a visible status.
2. State before decoration: theme, loading, error, selected, disabled, and success states are readable as text as well as color.
3. Stable geometry: controls remain single-line at compact width; page changes replace only the page surface.
4. Public API truth: the prototype may use ordinary HTML/JS, but the ETAF port uses only public ETAF/ETAF-UI APIs.

## Visual language

- Color: ink navy `#142235`, paper `#F6F1E8`, slate `#526174`, teal `#2E8B83`, coral `#E26D5A`, amber `#D99A3D`, success `#3E9B72`.
- Typography: readable sans body, compact monospace labels/metrics, bold page titles.
- Spacing/layout rhythm: one-line outer rhythm, two-column workspace, fixed gaps, full-width shell, deliberate card padding.
- Shape/elevation: thin dark borders and restrained card elevation; no floating overlay is required by the ETAF port.
- Motion: no animation is required; state changes are immediate and reduced-motion safe.
- Imagery/iconography: text marks and Unicode status glyphs only; no external asset dependency.

## Components

- Existing components to reuse: public `button`, `checkbox`, `label`, `panel`, and `data-grid` from `etaf-ui`.
- New/changed components: `operations-console-shell`, `hero-status`, `metric-strip`, `activity-card`, `capability-card`, `timeline`, `data-page`, and `resource-page` in the companion.
- Variants/states: active/inactive nav, light/dark theme, selected/unselected row, Behavior on/off, resource ready/loading/error, boundary handled, compact/fullscreen.
- Ownership: `.etaf` owns static composition and section names; `.el` owns tokens, props, refs, resources, handlers, and state.

## Accessibility

- Target: keyboard-complete, high-contrast text, semantic roles through public UI components.
- Keyboard/focus: Tab and Shift-Tab traverse nav/actions/data rows; RET dispatches the focused ref; focus clears when a target is removed.
- Every state has text feedback; color is never the only signal. No hover-only behavior.
- Ebox Theme carries inherited Ebox defaults; application palette lookups remain
  in the companion, while the Renderer filters unknown token names before they
  reach Ebox geometry.

## Responsive behavior

- Supported surfaces: compact 900–940 px GUI body and fullscreen desktop GUI.
- Metric cards remain in one row when possible; workspace falls back from two columns to stacked sections; controls keep intrinsic single-line widths.
- Use `flex` for rows that distribute remaining width; reserve `row` for fixed
  intrinsic control groups. The navigation control group is max-content so
  each hover/active range remains an independent control.
- Mouse-1 and keyboard activation use the same public refs.

## Interaction states

- Loading: resource card reports `Loading…` without moving the shell.
- Empty: DataGrid reports an explicit empty state and keeps selection controls available.
- Error: resource reload can fail once; the boundary card reports the handled error and recovery remains available.
- Success: action/status and timestamp update visibly.
- Disabled: unavailable actions expose disabled semantics rather than silently ignoring input.

## Content voice

- Tone: concise, operational, and explanatory; labels name the framework capability being demonstrated.
- Terminology: use `Component`, `Context`, `Theme`, `Behavior`, `Action`, `Data`, `Resource`, and `Boundary` consistently.
- Microcopy: prefer a visible verb + result (`Reload resource`, `Handled: …`, `Selected Beacon`) over generic `Done`.

## Implementation constraints

- Framework/styling: ETAF public View DSL in `.etaf`/`.el`; Ebox renders the result; no HTML/CSS runtime dependency.
- Design tokens: keep palette/spacing tokens in one companion source and reuse them; no scattered ad-hoc colors.
- Performance: ordinary warm p50 <=100 ms, counter/resource p50 <=150 ms, every measured max <=250 ms; one publication per logical action.
- Compatibility: preserve one same-basename `operations-console` pair, safe static reader, public API boundary, mount twice/unmount cleanup, and manifest refs.
- Navigation: the stable page ref is read by the retained router Component; its
  page Host is the single semantic Range anchor, so page switches replace one
  Range payload instead of rebuilding the shell root.
- Review: HTML is the visual reference; ETAF needs compact/fullscreen screenshots and dynamic keyboard/mouse checkpoints.

## Open questions

- [ ] User review may adjust palette or page naming after the first HTML/ETAF comparison; behavior and public-ref coverage remain fixed.
