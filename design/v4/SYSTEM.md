# Making the 12 screens one app

Folder: `/tmp/claude-0/-home-user-screenshot-brain/51b7b37d-63e5-5a1f-a3bd-c8869c96e4f1/scratchpad/v4/`

The screens in this folder each copy a different reference, so they look like 12 apps. Your job
is to make your screen use the shared system in `system.css` (read it fully) while **keeping
its layout and composition**: same elements in the same places. You change the materials (colours,
type, buttons, chrome), not the design.

Edit only your own `<name>.html`. Add `<link rel="stylesheet" href="system.css">` after
base.css. Prefer the system's classes and `var(--…)` tokens over local values. Render with
`cd <folder> && NODE_PATH=$(npm root -g) node render.js <name>` and look at `out/<name>.png`;
do at least two render-check rounds. Final answer: the PNG path and a one-line list of what you
changed.

## Rules for every screen

1. **Ground**: `var(--ground)` behind everything (except where the screen's content is full-bleed
   imagery, as noted in your checklist). Add `<div class="grain"></div>` if missing.
2. **Status bar**: `statusBar(true)` from kit.js, unmodified (no repositioning, no custom font
   size). **Remove any drawn dynamic island / camera pill.** Home indicator: the base
   `.home-indicator`, unmodified.
3. **Colour**: one warm palette. Neutrals (`--ground`, `--surface`, `--surface-2`, `--ink*`,
   `--line`) plus one warm ramp (`--ramp-0` deep ember … `--ramp-7` bone). The five kinds are
   steps on that ramp (`--events-*` ember, `--places-*` coral, `--products-*` apricot,
   `--recipes-*` sand, `--reference-*` stone), and `--accent` (warm white) marks done, progress
   and the live point. It is also the only white: selected chips, the primary pill, the CTA circle
   and story bars all use it, never `#fff`. Translucent whites are warm (`rgba(255,240,225,a)`).
   No other hue anywhere: no pink, blue, purple, green or lime. Imagery from `screenshot()` is
   drawn in the same warm range.
4. **Type**: big numbers `.t-num-xl` / `.t-num-l` (Inter Display Light); screen titles `.t-large`;
   titles beside a back button `.t-nav`; item names `.t-title`; secondary text `.t-body`; every
   small uppercase label `.t-label` (mono); Reveal headlines `.t-story` (serif). No other fonts,
   weights or tracking. Units after numbers: `.t-unit`.
5. **Components** (use exactly these, no local button styles):
   - Moving forward (start, set, continue): `.cta`, label on the left, `.go` circle with the glyph
     on the right.
   - Deciding on an item: `.seg`, always in the order Drop · Still want · Done, with Still want
     as `.seg-btn.primary` in the middle. The widget uses the same order.
   - Actions on one thing (calendar, maps, send, done): `.scenario` with `style="--c: var(--…-c)"`, all in the item's own kind.
     `.scenario.fill` gets a gradient background in the same light.
   - Round buttons: `.btn-circle` for actions (back, close, settings, search, filter), and
     `.chip-circle` (`.on` = selected) for choosable chips like days.
   - Surfaces: `.tile` (radius 28) holding one `.light`; cards that are objects use `--r-card`
     (34); glass panels `.glass`.
   - The mark: `<span class="mark">${icon('bracket', 18)}Screenshot Brain</span>`.
   - Icons: kit.js `icon(name, size)` only (`back`, `x`, `check`, `arrow`, `plus`, `home`, `bookmark`,
     `spark`, `search`, `filter`, `ticket`, `cal`, `map`, `send`, `sliders`, `more`, `stack`).
6. **Spacing**: 16pt side gutters (`--gutter`), 8pt between tiles (`--gap`). Content starts at
   y = 62 under the status bar.
7. **Navigation chrome**, exactly one of these:
   - **Main screens (home, saved, reveals)**: this tab bar at the bottom, with your tab `.on`:
     ```html
     <div class="tabbar">
       <div class="tab">${icon('home',20)}Home</div>
       <div class="tab">${icon('bookmark',20)}Saved</div>
       <div class="tab">${icon('spark',20)}Reveals</div>
     </div>
     ```
     Content may scroll under it, but nothing important sits behind it.
   - **Opened screens (item, stillwant, recaptime, history, triage)**: this header at y = 62:
     ```html
     <div style="position:absolute;top:62px;left:16px;right:16px;display:flex;align-items:center;gap:14px;z-index:60">
       <span class="btn-circle">${icon('back',20)}</span><span class="t-nav">Title</span>
       <span style="flex:1"></span><!-- optional right .btn-circle -->
     </div>
     ```
     (triage uses `icon('x',20)` instead of back.) Content starts below it (y ≈ 122).
   - **Reveal cards (story, peak)**: `.story-bars` (8 bars, viewed ones `.done`, the current one `.on`) and under it
     at y = 72 the mark at left and a 36pt `.btn-circle` with `icon('x',18)` at right. No tab bar.
   - **scan** and **widget** have no navigation chrome (onboarding and a widget showcase).
