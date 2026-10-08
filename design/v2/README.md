# Design v2 mockups

The direction taken from references 01–12 after the first build's mist-and-swoosh look missed:

- **Colour lives inside objects.** A dark ground (or matte paper in light mode); every tile, slab
  and card carries its own light, saturated at the core and gone before the edge. One light per
  kind of thing: events magenta, places ember, products cobalt, recipes sage, reference cream.
- **Data as an instrument.** Dot-matrix numerals (a 5×7 grid of dots), hairline rulers with one lit
  mark, uppercase monospace labels, tight data rows.
- **The user's screenshot is the imagery.** Shown sharp where you need to recognise it, and
  blurred along one axis into the object's light everywhere else.
- **Objects, not pages.** Folder-tab cards, bento tiles, stacked slabs; dark tinted glass; a white
  primary pill and a lime "done".

Render with headless Chromium (Playwright): `node render.js home triage reveal item home-light widget`
writes PNGs to `out/`. The mono face is JetBrains Mono (OFL) standing in for SF Mono; Inter stands
in for SF Pro.
