# Brief: copy the reference elements exactly, as Screenshot Brain screens

Screenshot Brain is an iPhone app that reads your screenshots (places, gigs, products, recipes)
and helps you act on them: a nightly "recap" deck where you keep / drop / tick off each one, a
score of things done, a Home, and a monthly "Reveal" story about what you've been saving.

The owner has rejected every design that *interpreted* the references. They want each reference
**copied exactly**: the same composition, proportions, spacing, sizes, corner radii, colours,
gradients, type styles, component shapes and positions, the same symmetry. Your screen should
look like the reference screen with our content in it. If the reference has something, yours
has it in the same place at the same size.

## Hard rules

- **Copy the reference's layout 1:1.** Measure it. Same margins, same tile grid, same type
  sizes relative to the screen, same radii, same colours (sample them from the image).
- **Symmetric and straight.** No rotations, tilts, skews or off-centre stacks unless the
  reference itself has them.
- **No dot-matrix or dotted numerals.** Where a reference uses dotted digits, use clean numerals
  in the same position and size (a light or regular weight of Inter).
- **No other brands.** Never copy a logo, brand name, product name, or photo of a person. Where
  the reference has a photo, use our imagery: the user's screenshot as a stand-in from
  `screenshot(kind, w, h, {blurX, blurY, sharp})` in kit.js (kinds: event, place, product, recipe),
  or a soft blurred gradient made to match the photo's colours and shapes (e.g. a motion-blurred
  figure becomes blurred colour forms in the same arrangement). Where the reference has a logo,
  use our mark: `[ ] Screenshot Brain` (the bracket icon from `icon("bracket")`).
- Our content replaces theirs, using the mapping in your screen's spec. Copy is short and plain.
- Screen size: 393×852 points, an iPhone. Include the status bar (`statusBar(true)` from kit.js,
  or `statusBar(false)` on a light screen) and `<div class="home-indicator"></div>`. If the
  reference is shown inside a phone mockup, copy only the screen contents, full-bleed.
- Fonts available: Inter (system, all weights; "Inter Display" too), `.mono` (JetBrains Mono,
  for any monospace or technical caps), `.serif` (Instrument Serif, for any serif display type).

## Files

Work in `/tmp/claude-0/-home-user-screenshot-brain/51b7b37d-63e5-5a1f-a3bd-c8869c96e4f1/scratchpad/v4/`.
- Start your HTML with:
  `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="base.css"><script src="kit.js"></script>…`
  and put the screen in `<div class="phone">…</div>`. Read `kit.js` for the helpers.
- Render: `cd <dir> && NODE_PATH=$(npm root -g) node render.js <name>` writes `out/<name>.png`
  (793×1704). Then **look at the PNG and the reference side by side** with the Read tool and fix
  every difference in layout, size, colour and spacing. Do at least three render-compare-fix
  rounds. Stop when it matches.
- Only create or edit your own `<name>.html`. Don't touch other files.

Your final answer: the path to your PNG, and one line per deliberate difference from the
reference (content swaps don't count).
