// Shared pieces for the mockups. Everything here is drawable in SwiftUI the same way:
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

/** A stand-in for the user's screenshot: a real-looking page (gig, restaurant, shop, recipe) drawn
    at phone size (390×844), cropped to w×h from the top like a thumbnail, optionally blurred. */
let __shotId = 0;
function screenshot(kind, w, h, { blurX = 26, blurY = 6, sharp = false, hero = false } = {}) {
  // hero: show only the page's photo (its top and height on the 390×844 page), scaled to cover.
  const HERO = { event: [100, 300], place: [0, 380], product: [100, 420], recipe: [0, 400] }[kind];
  const W = 390, H = 844, k = hero ? Math.max(w / W, h / HERO[1]) : Math.max(w / W, h / H);
  const dy = hero ? -HERO[0] * k - (HERO[1] * k - h) / 2 : 0;
  const id = "shot" + (++__shotId);
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const ab = (css) => `<div style="position:absolute;${css}"></div>`;
  const bar = (c) => `<div style="position:absolute;top:0;left:0;right:0;height:50px;display:flex;justify-content:space-between;align-items:center;padding:12px 30px 0 36px;font:600 16px Inter;color:${c}"><span>9:41</span><span style="display:flex;gap:5px;align-items:center">
    <svg width="17" height="11"><rect x="0" y="7" width="3" height="4" rx="1" fill="${c}"/><rect x="4.6" y="5" width="3" height="6" rx="1" fill="${c}"/><rect x="9.2" y="2.5" width="3" height="8.5" rx="1" fill="${c}"/><rect x="13.8" y="0" width="3" height="11" rx="1" fill="${c}"/></svg>
    <svg width="25" height="12"><rect x=".5" y=".5" width="21" height="11" rx="3.2" fill="none" stroke="${c}" opacity=".4"/><rect x="2" y="2" width="18" height="8" rx="2" fill="${c}"/></svg></span></div>`;
  const scenes = {
    event: () => {
      let crowd = "";
      // crowd: heads 34 +/-20% with a neck gap, sloped shoulders about 2.2x the head, heights +/-6
      for (let i = 0; i < 13; i++) {
        const s = 34 * (0.8 + rnd() * 0.4), x = -14 + i * 33 + rnd() * 10, y = 230 + (rnd() * 12 - 6);
        crowd += ab(`left:${x}px;top:${y}px;width:${s}px;height:${s * 1.18}px;border-radius:50% 50% 46% 46%;background:#0b0504`);
        crowd += ab(`left:${x - s * .62}px;top:${y + s * 1.02}px;width:${s * 2.24}px;height:90px;border-radius:${s * .9}px ${s * .9}px 0 0 / ${s * .55}px ${s * .55}px 0 0;background:#0b0504`);
      }
      // raised arms: shoulder -> elbow -> hand, the upper arm 11 wide tapering to a 9-wide forearm, the hand a rounded mitten barely wider than the wrist
      const arm = ([sx, sy, ex, ey, hx, hy]) => {
        const a = Math.atan2(hy - ey, hx - ex) * 180 / Math.PI + 90;
        return `<path d="M${sx} ${sy} L${ex} ${ey}" stroke-width="11"/><path d="M${ex} ${ey} L${hx} ${hy}" stroke-width="9"/><ellipse cx="${hx}" cy="${hy}" rx="5.5" ry="7.5" transform="rotate(${a.toFixed(1)} ${hx} ${hy})" stroke="none"/>`;
      };
      crowd += `<svg style="position:absolute;left:0;top:0" width="393" height="300" viewBox="0 0 393 300" fill="#0b0504" stroke="#0b0504" stroke-linecap="round" stroke-linejoin="round">${[[64, 278, 46, 240, 64, 200], [126, 274, 138, 242, 128, 208], [270, 274, 258, 244, 270, 210], [314, 278, 334, 242, 320, 200], [358, 282, 346, 252, 362, 222]].map(arm).join("")}</svg>`;
      const beam = (x, r, o) => ab(`left:${x}px;top:96px;width:70px;height:300px;transform-origin:50% 0;transform:rotate(${r}deg);background:linear-gradient(180deg,rgba(255,214,170,${o}),rgba(255,160,100,0));filter:blur(7px)`);
      return `<div style="position:absolute;inset:0;background:#0d0806"></div>
        ${bar("#fff")}
        <div style="position:absolute;top:56px;left:20px;right:20px;display:flex;align-items:center;justify-content:space-between;color:#fff;font:600 17px Inter">${icon("back", 22)}<span>Event</span>${icon("send", 20)}</div>
        <div style="position:absolute;top:100px;left:0;right:0;height:300px;overflow:hidden;background:radial-gradient(70% 80% at 50% 30%,#ffa660 0%,#e8622e 28%,#7a2410 60%,#1a0a06 100%)">
          ${beam(90, 22, .55)}${beam(160, 0, .7)}${beam(230, -22, .55)}
          ${ab("left:120px;top:20px;width:150px;height:150px;border-radius:50%;background:#fff3e0;filter:blur(40px);opacity:.55")}
          <svg style="position:absolute;left:0;top:0" width="393" height="300" viewBox="0 0 393 300" fill="#160806">
            <circle cx="195" cy="121" r="16"/>
            <path d="M189 134 L189 144 C182 147 172 149 166 154 C161 159 159 168 160 180 L171 270 L219 270 L230 180 C231 168 229 159 224 154 C218 149 208 147 201 144 L201 134 Z"/>
            <path d="M146 290 L180.5 141" stroke="#160806" stroke-width="3" stroke-linecap="round"/>
            <rect x="176.5" y="128" width="8" height="14" rx="4" transform="rotate(13 180.5 135)"/>
          </svg>
          ${crowd}
        </div>
        <div style="position:absolute;top:420px;left:20px;right:20px;font-family:Inter">
          <div style="font:600 12px Inter;letter-spacing:.08em;color:#ff8a57">ENMORE THEATRE · NEWTOWN</div>
          <div style="font:700 40px/1.05 Inter;letter-spacing:-.02em;color:#fff;margin-top:8px">Mallrat</div>
          <div style="font:400 17px Inter;color:#b8ada3;margin-top:4px">Butterfly Blue Tour</div>
          <div style="display:flex;gap:10px;align-items:center;margin-top:22px;font:400 15px Inter;color:#ece4da">${icon("cal", 18)}Sun 11 October · Doors 7pm</div>
          <div style="display:flex;gap:10px;align-items:center;margin-top:12px;font:400 15px Inter;color:#ece4da">${icon("map", 18)}118 Enmore Rd, Newtown</div>
          <div style="height:1px;background:#2b211c;margin-top:22px"></div>
          <div style="display:flex;justify-content:space-between;align-items:center;margin-top:20px">
            <div><div style="font:400 13px Inter;color:#9a8e84">From</div><div style="font:600 24px Inter;color:#fff">$69.90</div></div>
            <div style="height:50px;padding:0 28px;border-radius:25px;background:#ff6a2b;color:#1a0904;font:600 16px Inter;display:flex;align-items:center">Get tickets</div>
          </div>
          <div style="font:600 13px Inter;letter-spacing:.06em;color:#9a8e84;margin-top:28px">LINEUP</div>
          <div style="display:flex;gap:8px;margin-top:10px">${["Mallrat", "Cub Sport", "Ruby Fields"].map(t => `<span style="height:34px;padding:0 14px;border-radius:17px;background:#1f1714;color:#ece4da;font:500 14px Inter;display:flex;align-items:center">${t}</span>`).join("")}</div>
        </div>`;
    },
    place: () => {
      let noodles = "";
      for (let i = 0; i < 9; i++) noodles += ab(`left:${78 + i * 9}px;top:${150 + i * 6}px;width:150px;height:110px;border-radius:50%;border:3px solid #f6dba0;border-color:#f6dba0 transparent transparent transparent;transform:rotate(${-30 + i * 8}deg);opacity:.95`);
      let greens = "";
      for (let i = 0; i < 16; i++) greens += ab(`left:${150 + rnd() * 120}px;top:${110 + rnd() * 90}px;width:9px;height:9px;border-radius:50%;border:2.5px solid #e6cf9a`);
      return `<div style="position:absolute;inset:0;background:#faf6f1"></div>
        <div style="position:absolute;top:0;left:0;right:0;height:380px;overflow:hidden;background:linear-gradient(160deg,#5a3520,#2a160c)">
          ${ab("left:-40px;top:0;width:470px;height:380px;background:repeating-linear-gradient(100deg,rgba(255,220,180,.05) 0 3px,transparent 3px 22px)")}
          ${ab("left:250px;top:-20px;width:14px;height:300px;border-radius:7px;background:linear-gradient(90deg,#d8ab78,#a5743f);transform:rotate(28deg)")}
          ${ab("left:276px;top:-20px;width:14px;height:300px;border-radius:7px;background:linear-gradient(90deg,#d8ab78,#a5743f);transform:rotate(34deg)")}
          ${ab("left:30px;top:40px;width:330px;height:330px;border-radius:50%;background:radial-gradient(circle,#2a1b14 62%,#120a06 70%);box-shadow:0 30px 60px rgba(0,0,0,.6)")}
          ${ab("left:52px;top:62px;width:286px;height:286px;border-radius:50%;background:radial-gradient(circle at 45% 40%,#f6c983,#dc8f3e 55%,#a65a21)")}
          ${ab("left:70px;top:84px;width:70px;height:130px;background:#1c1912;transform:rotate(14deg);border-radius:3px")}
          ${noodles}
          ${ab("left:196px;top:96px;width:86px;height:86px;border-radius:50%;background:radial-gradient(circle,#efc2aa 30%,#c47353 70%);box-shadow:inset 0 0 0 5px #8a4128")}
          ${ab("left:214px;top:164px;width:80px;height:80px;border-radius:50%;background:radial-gradient(circle,#efc2aa 30%,#c47353 70%);box-shadow:inset 0 0 0 5px #8a4128")}
          ${ab("left:110px;top:226px;width:76px;height:60px;border-radius:50%;background:#fbf3e4")}
          ${ab("left:126px;top:238px;width:38px;height:36px;border-radius:50%;background:radial-gradient(circle at 40% 40%,#ffbe5c,#f07a1c)")}
          ${ab("left:186px;top:244px;width:76px;height:60px;border-radius:50%;background:#fbf3e4")}
          ${ab("left:206px;top:256px;width:38px;height:36px;border-radius:50%;background:radial-gradient(circle at 40% 40%,#ffbe5c,#f07a1c)")}
          ${greens}
          ${bar("#fff")}
          <div style="position:absolute;top:58px;left:16px;width:40px;height:40px;border-radius:50%;background:rgba(255,255,255,.92);display:flex;align-items:center;justify-content:center;color:#1b1512">${icon("back", 20)}</div>
          <div style="position:absolute;top:58px;right:16px;width:40px;height:40px;border-radius:50%;background:rgba(255,255,255,.92);display:flex;align-items:center;justify-content:center;color:#1b1512">${icon("bookmark", 18)}</div>
        </div>
        <div style="position:absolute;top:398px;left:20px;right:20px">
          <div style="font:700 28px Inter;letter-spacing:-.02em;color:#1b1512">Ramen Ikkyu</div>
          <div style="font:400 15px Inter;color:#6f645a;margin-top:6px"><span style="color:#e2582b">★</span> 4.7 (1,284) · Japanese · $$</div>
          <div style="font:400 15px Inter;color:#6f645a;margin-top:4px"><span style="color:#c2410c;font-weight:600">Open</span> · Closes 10 pm</div>
          <div style="display:flex;gap:8px;margin-top:18px">
            <span style="height:40px;padding:0 18px;border-radius:20px;background:#1b1512;color:#fff;font:600 14px Inter;display:flex;align-items:center">Directions</span>
            <span style="height:40px;padding:0 18px;border-radius:20px;border:1px solid #d9cfc4;color:#1b1512;font:600 14px Inter;display:flex;align-items:center">Call</span>
            <span style="height:40px;padding:0 18px;border-radius:20px;border:1px solid #d9cfc4;color:#1b1512;font:600 14px Inter;display:flex;align-items:center">Website</span>
          </div>
          <div style="height:1px;background:#ebe3d9;margin-top:20px"></div>
          <div style="display:flex;gap:10px;align-items:center;margin-top:16px;font:400 15px Inter;color:#2a221c">${icon("map", 18)}Shop 7, 401 Sussex St, Haymarket</div>
          <div style="position:relative;height:150px;border-radius:16px;margin-top:14px;overflow:hidden;background:#efe6da">
            ${ab("left:-20px;top:60px;width:420px;height:10px;background:#fff;transform:rotate(-8deg)")}
            ${ab("left:140px;top:-20px;width:10px;height:200px;background:#fff;transform:rotate(14deg)")}
            ${ab("left:250px;top:-20px;width:7px;height:200px;background:#fff;transform:rotate(-4deg)")}
            ${ab("left:20px;top:90px;width:90px;height:50px;border-radius:8px;background:#e4dcc6")}
            ${ab("left:170px;top:58px;width:22px;height:22px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);background:#e2582b;box-shadow:0 0 0 4px rgba(226,88,43,.2)")}
          </div>
        </div>`;
    },
    product: () => `<div style="position:absolute;inset:0;background:#f4efe9"></div>
        ${bar("#1b1512")}
        <div style="position:absolute;top:56px;left:20px;right:20px;display:flex;align-items:center;justify-content:space-between;color:#1b1512;font:600 17px Inter">${icon("back", 22)}<span>Studio Kiri</span>${icon("bookmark", 20)}</div>
        <div style="position:absolute;top:100px;left:0;right:0;height:420px;overflow:hidden;background:radial-gradient(80% 70% at 50% 40%,#f3e9dd,#e3d6c6)">
          ${ab("left:85px;top:350px;width:220px;height:30px;border-radius:50%;background:rgba(80,40,15,.28);filter:blur(10px)")}
          ${ab("left:110px;top:200px;width:170px;height:170px;border-radius:50%;background:radial-gradient(circle at 34% 28%,#f6b48c,#cf6a3d 45%,#7d3417 100%)")}
          ${ab("left:188px;top:170px;width:14px;height:40px;background:linear-gradient(90deg,#5a3a26,#8a6448)")}
          ${ab("left:70px;top:200px;width:250px;height:60px;border-radius:50%;background:rgba(255,200,140,.55);filter:blur(16px)")}
          <div style="position:absolute;left:80px;top:60px;width:230px;height:130px;clip-path:polygon(20% 0,80% 0,100% 100%,0 100%);background:linear-gradient(180deg,#fcf6ec,#efd9bd)"></div>
          ${ab("left:80px;top:182px;width:230px;height:10px;border-radius:50%;background:#e6c9a6")}
          <div style="position:absolute;bottom:14px;left:0;right:0;display:flex;justify-content:center;gap:6px">${[1, 0, 0, 0].map(o => `<span style="width:6px;height:6px;border-radius:3px;background:${o ? "#1b1512" : "#c9bcae"}"></span>`).join("")}</div>
        </div>
        <div style="position:absolute;top:540px;left:20px;right:20px">
          <div style="font:600 12px Inter;letter-spacing:.08em;color:#8a7d71">LIGHTING</div>
          <div style="font:600 26px Inter;letter-spacing:-.02em;color:#1b1512;margin-top:6px">Dune table lamp</div>
          <div style="font:500 20px Inter;color:#1b1512;margin-top:6px">$189</div>
          <div style="font:400 13px Inter;color:#8a7d71;margin-top:18px">Colour · Terracotta</div>
          <div style="display:flex;gap:10px;margin-top:10px">
            <span style="width:30px;height:30px;border-radius:50%;background:#c8653a;box-shadow:0 0 0 2px #f4efe9,0 0 0 3.5px #1b1512"></span>
            <span style="width:30px;height:30px;border-radius:50%;background:#e6cfb2"></span>
            <span style="width:30px;height:30px;border-radius:50%;background:#f7f1e8;box-shadow:inset 0 0 0 1px #d9cfc4"></span>
          </div>
          <div style="height:54px;border-radius:27px;background:#1b1512;color:#fff;font:600 16px Inter;display:flex;align-items:center;justify-content:center;margin-top:22px">Add to bag</div>
          <div style="font:400 13px Inter;color:#8a7d71;text-align:center;margin-top:12px">Free delivery over $150</div>
        </div>`,
    recipe: () => {
      let pasta = "";
      for (let i = 0; i < 26; i++) {
        const a = rnd() * Math.PI * 2, r = Math.sqrt(rnd()) * 78;
        pasta += ab(`left:${195 + Math.cos(a) * r - 18}px;top:${200 + Math.sin(a) * r - 8}px;width:36px;height:16px;border-radius:8px;background:linear-gradient(180deg,#f39a58,#d6622c);box-shadow:inset -7px 0 0 #9c3a18,0 2px 3px rgba(80,20,5,.35);transform:rotate(${rnd() * 180}deg)`);
      }
      let cheese = "";
      for (let i = 0; i < 22; i++) cheese += ab(`left:${130 + rnd() * 130}px;top:${140 + rnd() * 120}px;width:${3 + rnd() * 4}px;height:2px;background:#fff6e4;transform:rotate(${rnd() * 180}deg)`);
      return `<div style="position:absolute;inset:0;background:#fbf7f1"></div>
        <div style="position:absolute;top:0;left:0;right:0;height:400px;overflow:hidden;background:#ebdfcf">
          ${ab("inset:0;background:repeating-linear-gradient(0deg,rgba(120,90,60,.06) 0 1px,transparent 1px 4px),repeating-linear-gradient(90deg,rgba(120,90,60,.05) 0 1px,transparent 1px 4px)")}
          ${ab("left:45px;top:50px;width:300px;height:300px;border-radius:50%;background:#fbf8f3;box-shadow:0 18px 40px rgba(90,50,20,.28)")}
          ${ab("left:80px;top:85px;width:230px;height:230px;border-radius:50%;background:#f2ebe1;box-shadow:inset 0 2px 6px rgba(90,50,20,.15)")}
          ${ab("left:100px;top:105px;width:190px;height:190px;border-radius:50%;background:radial-gradient(circle,#e5552c,#b8361a 70%,rgba(184,54,26,0) 72%)")}
          ${pasta}${cheese}
          ${ab("left:170px;top:160px;width:26px;height:14px;border-radius:50% 0;background:#6b4f24;transform:rotate(-20deg)")}
          ${ab("left:214px;top:220px;width:24px;height:13px;border-radius:50% 0;background:#6b4f24;transform:rotate(30deg)")}
          ${ab("left:342px;top:60px;width:10px;height:290px;border-radius:5px;background:linear-gradient(90deg,#d9d3cb,#a8a198)")}
          ${bar("#1b1512")}
        </div>
        <div style="position:absolute;top:418px;left:20px;right:20px">
          <div style="font:600 12px Inter;letter-spacing:.08em;color:#c2410c">DINNER · 25 MIN</div>
          <div style="font:700 28px/1.12 Inter;letter-spacing:-.02em;color:#1b1512;margin-top:8px">Tomato butter rigatoni</div>
          <div style="font:400 15px Inter;color:#6f645a;margin-top:6px">Serves 2 · Easy · Vegetarian</div>
          <div style="display:flex;gap:22px;margin-top:20px;font:600 15px Inter;color:#9a8e84;border-bottom:1px solid #ebe3d9"><span style="color:#1b1512;padding-bottom:10px;border-bottom:2px solid #1b1512">Ingredients</span><span>Method</span><span>Notes</span></div>
          ${["400 g rigatoni", "1 tin whole peeled tomatoes", "80 g unsalted butter", "1 brown onion, halved", "Parmesan, to serve"].map(t => `<div style="display:flex;gap:12px;align-items:center;margin-top:16px;font:400 15px Inter;color:#2a221c"><span style="width:20px;height:20px;border-radius:50%;border:1.5px solid #cfc3b6"></span>${t}</div>`).join("")}
        </div>`;
    },
  };
  const blur = sharp ? "" : `<svg width="0" height="0" style="position:absolute"><filter id="${id}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="${blurX / k} ${blurY / k}"/></filter></svg>`;
  const base = { event: "#0d0806", place: "#3a2215", product: "#ebe2d6", recipe: "#ebdfcf" }[kind];
  return `<div style="position:relative;width:${w}px;height:${h}px;overflow:hidden;background:${base}">${blur}
    <div style="position:absolute;left:50%;top:${dy}px;width:${W}px;height:${H}px;transform:translateX(-50%) scale(${k});transform-origin:50% 0;${sharp ? "" : `filter:url(#${id});`}">${scenes[kind]()}</div></div>`;
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
