# Clickable prototype

The v4 design screens, wired together so they can be tapped through on a phone or in a browser.
Every screen is the design file itself (`design/v4/<name>.html`); this folder only adds:

- `shell.html`: the page that holds the phone, the navigation stack (push, back, modal, tabs) and
  the screen index. Published as the artifact's `index.html`.
- `proto.js`: added to every screen. It wires taps, swipes and small state changes (the recap deck,
  recap time, Reveal story bars, Peak's tabs) and asks the shell to navigate.
- `build.py`: copies the screens, adds the Inter webfont and `proto.js`, writes the shell.

```
python3 design/prototype/build.py design/v4 /path/to/dist
```

Everything is sample data: a gig (Mallrat at the Enmore), a ramen spot, a lamp and a recipe.
