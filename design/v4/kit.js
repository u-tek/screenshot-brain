// Shared pieces for the v2 mockups. Everything here is drawable in SwiftUI the same way:
// dot-matrix numerals are a 5×7 grid of circles, the folder is one path, the "screenshot"
// textures are the user's own screenshot blurred along one axis.

const GLYPHS = {
  "0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
  "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
  "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
  "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
  "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
  "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
  "6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
  "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
  "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
  "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
  "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
  ":": [".....", "..#..", ".....", ".....", ".....", "..#..", "....."],
  " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
};

/** Dot-matrix text as inline SVG. `dot` is the dot diameter, `pitch` the grid step. */
function dots(text, { dot = 6, pitch = 8, color = "#f4f3f1", unlit = 0.07, glow = true } = {}) {
  const chars = [...String(text)];
  const cols = chars.length * 6 - 1;
  const w = cols * pitch, h = 7 * pitch;
  let circles = "";
  chars.forEach((ch, i) => {
    const g = GLYPHS[ch] || GLYPHS[" "];
    g.forEach((row, y) => [...row].forEach((c, x) => {
      const cx = (i * 6 + x) * pitch + pitch / 2, cy = y * pitch + pitch / 2;
      if (c === "#") circles += `<circle cx="${cx}" cy="${cy}" r="${dot / 2}" fill="${color}"/>`;
      else if (unlit > 0) circles += `<circle cx="${cx}" cy="${cy}" r="${dot / 2}" fill="${color}" opacity="${unlit}"/>`;
    }));
  });
  const id = "g" + Math.random().toString(36).slice(2, 7);
  const filter = glow ? `<filter id="${id}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${dot * 0.45}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` : "";
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" style="display:block;overflow:visible">${filter}<g ${glow ? `filter="url(#${id})"` : ""}>${circles}</g></svg>`;
}

/** The folder: a raised tab on the top-left edge, flowing into the body with one soft step. */
function folderPath(w, h, { tab = 0.42, tabH = 30, r = 26 } = {}) {
  const tw = Math.round(w * tab);
  return `M0 ${r} Q0 0 ${r} 0 L${tw - 22} 0 C${tw - 6} 0 ${tw - 4} ${tabH} ${tw + 16} ${tabH} L${w - r} ${tabH} Q${w} ${tabH} ${w} ${tabH + r} L${w} ${h - r} Q${w} ${h} ${w - r} ${h} L${r} ${h} Q0 ${h} 0 ${h - r} Z`;
}
function folderClip(el, opts) {
  const r = el.getBoundingClientRect();
  el.style.clipPath = `path('${folderPath(r.width, r.height, opts)}')`;
}

/** A stand-in for the user's screenshot, blurred along one axis like a long exposure. */
function screenshot(kind, w, h, { blurX = 26, blurY = 6, sharp = false } = {}) {
  const id = "s" + Math.random().toString(36).slice(2, 7);
  const scenes = {
    event: `
      <rect width="${w}" height="${h}" fill="#14040b"/>
      <circle cx="${w * .62}" cy="${h * .3}" r="${w * .36}" fill="#ff2f7a"/>
      <circle cx="${w * .28}" cy="${h * .22}" r="${w * .2}" fill="#7a2cff" opacity=".85"/>
      <ellipse cx="${w * .5}" cy="${h * .52}" rx="${w * .22}" ry="${h * .2}" fill="#0a0206"/>
      <circle cx="${w * .5}" cy="${h * .34}" r="${w * .09}" fill="#1a0610"/>
      <rect x="${w * .1}" y="${h * .7}" width="${w * .8}" height="${h * .07}" rx="4" fill="#fff"/>
      <rect x="${w * .1}" y="${h * .8}" width="${w * .5}" height="${h * .035}" rx="3" fill="#ffc2da"/>
      <rect x="${w * .1}" y="${h * .86}" width="${w * .62}" height="${h * .03}" rx="3" fill="#ff7fb0" opacity=".8"/>`,
    place: `
      <defs><linearGradient id="${id}s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffb35c"/><stop offset=".55" stop-color="#ff5a2a"/><stop offset="1" stop-color="#3a0d05"/></linearGradient></defs>
      <rect width="${w}" height="${h}" fill="url(#${id}s)"/>
      <rect x="${w * .12}" y="${h * .42}" width="${w * .76}" height="${h * .5}" fill="#1d0a05"/>
      <rect x="${w * .2}" y="${h * .52}" width="${w * .24}" height="${h * .2}" fill="#ffcf7a"/>
      <rect x="${w * .56}" y="${h * .52}" width="${w * .24}" height="${h * .2}" fill="#ff9b4a"/>
      <circle cx="${w * .3}" cy="${h * .45}" r="${w * .05}" fill="#ff3b1f"/>
      <circle cx="${w * .7}" cy="${h * .45}" r="${w * .05}" fill="#ff3b1f"/>
      <rect x="${w * .12}" y="${h * .2}" width="${w * .6}" height="${h * .06}" rx="4" fill="#fff" opacity=".9"/>`,
    product: `
      <rect width="${w}" height="${h}" fill="#dfe3ec"/>
      <ellipse cx="${w * .52}" cy="${h * .42}" rx="${w * .4}" ry="${h * .16}" fill="#2f4dff" transform="rotate(-14 ${w * .52} ${h * .42})"/>
      <ellipse cx="${w * .46}" cy="${h * .46}" rx="${w * .24}" ry="${h * .07}" fill="#fff" transform="rotate(-14 ${w * .46} ${h * .46})"/>
      <rect x="${w * .1}" y="${h * .72}" width="${w * .5}" height="${h * .05}" rx="3" fill="#111"/>
      <rect x="${w * .1}" y="${h * .8}" width="${w * .3}" height="${h * .05}" rx="3" fill="#ff4b2b"/>`,
    recipe: `
      <rect width="${w}" height="${h}" fill="#f1ead8"/>
      <circle cx="${w * .5}" cy="${h * .42}" r="${w * .36}" fill="#2f6b49"/>
      <circle cx="${w * .5}" cy="${h * .42}" r="${w * .26}" fill="#c8e86a"/>
      <circle cx="${w * .42}" cy="${h * .38}" r="${w * .08}" fill="#ff5b3a"/>
      <circle cx="${w * .6}" cy="${h * .47}" r="${w * .07}" fill="#f7d14a"/>
      <rect x="${w * .1}" y="${h * .8}" width="${w * .6}" height="${h * .05}" rx="3" fill="#1e2a20"/>`,
  };
  const blur = sharp ? "" : `<filter id="${id}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="${blurX} ${blurY}"/></filter>`;
  return `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid slice" style="display:block">${blur}<g ${sharp ? "" : `filter="url(#${id})"`}>${scenes[kind]}</g></svg>`;
}

function statusBar(dark = true) {
  const c = dark ? "#f4f3f1" : "#121214";
  return `<div class="status" style="color:${c}"><span>9:41</span><span class="icons">
    <svg width="18" height="12"><rect x="0" y="8" width="3" height="4" rx="1" fill="${c}"/><rect x="5" y="5" width="3" height="7" rx="1" fill="${c}"/><rect x="10" y="2" width="3" height="10" rx="1" fill="${c}"/><rect x="15" y="0" width="3" height="12" rx="1" fill="${c}"/></svg>
    <svg width="16" height="12" viewBox="0 0 16 12"><path d="M8 11.5l2.4-2.9a3.6 3.6 0 0 0-4.8 0zM3.6 6.4a6.4 6.4 0 0 1 8.8 0l1.6-1.9a8.9 8.9 0 0 0-12 0zM.4 2.9a11.3 11.3 0 0 1 15.2 0" fill="${c}" stroke="${c}" stroke-width=".2"/></svg>
    <svg width="27" height="13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="${c}" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2" fill="${c}"/><rect x="25" y="4.5" width="1.6" height="4" rx=".8" fill="${c}" opacity=".4"/></svg>
  </span></div>`;
}

function icon(name, size = 18, color = "currentColor") {
  const s = `width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"`;
  const paths = {
    back: `<path d="M15 5l-7 7 7 7"/>`,
    more: `<circle cx="5" cy="12" r="1.2" fill="${color}"/><circle cx="12" cy="12" r="1.2" fill="${color}"/><circle cx="19" cy="12" r="1.2" fill="${color}"/>`,
    check: `<path d="M5 12.5l4.5 4.5L19 7.5"/>`,
    x: `<path d="M6 6l12 12M18 6L6 18"/>`,
    arrow: `<path d="M5 12h14M13 6l6 6-6 6"/>`,
    cal: `<rect x="4" y="5" width="16" height="15" rx="3"/><path d="M4 10h16M9 3v4M15 3v4"/>`,
    map: `<path d="M9 4l-5 2v14l5-2 6 2 5-2V4l-5 2z"/><path d="M9 4v14M15 6v14"/>`,
    send: `<path d="M20 4L10 14M20 4l-6 16-4-6-6-4z"/>`,
    stack: `<rect x="5" y="9" width="14" height="11" rx="3"/><path d="M7 6h10M9 3h6"/>`,
    sliders: `<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>`,
    bracket: `<path d="M8 4H5v16h3M16 4h3v16h-3"/>`,
    home: `<path d="M4 11l8-7 8 7v8.5a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H5.5A1.5 1.5 0 0 1 4 19.5z"/>`,
    bookmark: `<path d="M7 4h10v16l-5-4-5 4z"/>`,
    spark: `<path d="M12 3l1.8 5.4L19 10l-5.2 1.6L12 17l-1.8-5.4L5 10l5.2-1.6z"/><path d="M19 16l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"/>`,
    search: `<circle cx="11" cy="11" r="6"/><path d="M20 20l-4.5-4.5"/>`,
    filter: `<path d="M4 6h16l-6 7.5V19l-4 1.5v-7z"/>`,
    ticket: `<path d="M4 7h16v3a2 2 0 0 0 0 4v3H4v-3a2 2 0 0 0 0-4z"/><path d="M14 7v10" stroke-dasharray="1.5 2"/>`,
    plus: `<path d="M12 5v14M5 12h14"/>`,
  };
  return `<svg ${s}>${paths[name]}</svg>`;
}
