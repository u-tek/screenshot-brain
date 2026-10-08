# Design v4: the references, copied

Each screen copies one reference element 1:1 (layout, proportions, colours, components), with
our content swapped in and no other brand's logo, name or photo. No dot-matrix numerals, no
tilts. See BRIEF.md for the rules the screens were built to.

| Screen | Reference |
|---|---|
| home | 01, "Sugar" screen |
| scan | 01, sensor dial |
| recaptime | 01, "Complete setup" |
| saved | 03, "Overview" |
| item | 03, light detail and scenarios |
| triage | 09 folder card + 10 pill row |
| story | 07, silhouette story |
| peak | 02, mood axes and orb |
| reveals | 06, month cards with glass type |
| history | 11 energy card + 10 timeline |
| stillwant | 05, stacked boxes |
| widget | 08, folder widget |

Render with `node render.js <names…>` (headless Chromium via Playwright) into `out/`.

## One system

`system.css` is the shared system every screen uses, and `SYSTEM.md` the rules:
- one warm near-black ground with fine grain;
- one warm palette: neutrals plus a single ramp from deep ember to bone. The five kinds of thing
  are steps on it (events ember, places coral, products apricot, recipes sand, reference stone),
  and warm white is the only accent, for done, progress and the live point;
- Inter Display Light numbers, mono caps labels, Inter body, serif only for Reveal headlines;
- one component per job: `.cta` to move forward, `.seg` to decide, `.scenario` to act on a
  thing, `.btn-circle` and `.chip-circle`, `.tile` and `.glass`;
- navigation: the tab bar on Home, Saved and Reveals, a back header on opened screens, and story
  bars with a close button on Reveal cards;
- the user's screenshots are drawn as real pages (a gig listing, a ramen spot, a lamp shop, a
  recipe) by `screenshot()` in `kit.js`, cropped as thumbnails or to just their photo.

Contact sheets: `out/final-1.png` (main tabs and an item), `out/final-2.png` (recap, still
want, score, recap time), `out/final-3.png` (Reveal cards, onboarding scan, widget).
