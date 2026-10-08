// Prototype behaviour for the design screens. The build step adds this script to every screen; it
// wires taps, swipes and small state changes, and asks the shell (the parent page) to navigate.
(function () {
  const NAME = (location.pathname.split('/').pop() || '').replace(/\.html$/, '');
  let DATA = {};
  try { if (location.hash.length > 1) DATA = JSON.parse(decodeURIComponent(location.hash.slice(1))); } catch (e) { DATA = {}; }

  const post = (m) => parent.postMessage(m, '*');
  const go = (to, data) => post({ type: 'go', to, data, how: 'push' });
  const present = (to, data) => post({ type: 'go', to, data, how: 'modal' });
  const swap = (to, data) => post({ type: 'replace', to, data });
  const tabTo = (to) => post({ type: 'tab', to });
  const back = () => post({ type: 'back' });
  const close = () => post({ type: 'close' });
  const toast = (text) => post({ type: 'toast', text });

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const text = (el) => (el ? el.textContent.replace(/\s+/g, ' ').trim() : '');
  const byText = (sel, t) => $$(sel).find(el => text(el).toUpperCase().startsWith(t.toUpperCase()));
  const EASE = 'cubic-bezier(.32,.72,0,1)';

  function tap(el, fn) {
    if (!el) return;
    el.classList.add('p-tap');
    el.addEventListener('click', (e) => { e.stopPropagation(); fn(e); });
  }

  const css = document.createElement('style');
  css.textContent = `
    html, body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; -webkit-tap-highlight-color: transparent; }
    .p-tap { cursor: pointer; transition: scale .18s cubic-bezier(.3,.7,.4,1), opacity .18s, filter .18s; }
    .p-tap:active { scale: .965; opacity: .86; }
    @media (prefers-reduced-motion: reduce) { .p-tap { transition: none; } }`;
  document.head.appendChild(css);

  // The four things the sample library is about, and what each one offers.
  const ITEMS = {
    mallrat: { kind: 'event', label: 'EVENT · SUN 11 OCT · 7PM', title: 'Mallrat', sub: 'Enmore Theatre, Newtown', shot: 'event',
      actions: [['cal', 'ADD TO CALENDAR', 'Added to Calendar for Sun 11 Oct, 7pm'], ['map', 'MAPS', 'Directions to Enmore Theatre open in Maps'],
        ['send', 'SEND', 'The share sheet opens here']] },
    ramen: { kind: 'place', label: 'PLACE · OPEN TILL 10PM', title: 'Ramen Ikkyu', sub: 'Haymarket, Sydney', shot: 'place',
      actions: [['map', 'GET DIRECTIONS', 'Directions to Ramen Ikkyu open in Maps'], ['cal', 'PLAN', 'Pick a night to go'],
        ['send', 'SEND', 'The share sheet opens here']] },
    lamp: { kind: 'product', label: 'PRODUCT · $189 · SALE ENDS FRI', title: 'Dune lamp', sub: 'Studio Kiri', shot: 'product',
      actions: [['arrow', 'OPEN PRODUCT', 'The shop page opens in Safari'], ['cal', 'REMIND ME', "We'll remind you on Thursday"],
        ['send', 'SEND', 'The share sheet opens here']] },
    rigatoni: { kind: 'recipe', label: 'RECIPE · 25 MIN · SERVES 2', title: 'Rigatoni', sub: 'Tomato butter rigatoni', shot: 'recipe',
      actions: [['arrow', 'OPEN RECIPE', 'The recipe opens in Safari'], ['stack', 'SHOPPING LIST', 'Five ingredients added to Reminders'],
        ['send', 'SEND', 'The share sheet opens here']] },
  };
  const LIGHT = { event: 'events', place: 'places', product: 'products', recipe: 'recipes' };

  // Places in the Still want list. Each opens as a place, with its own name on the saved page.
  const PLACES = {
    'Ramen Ikkyu': { sub: 'Haymarket, Sydney', meta: '4.7 (1,284) · Japanese · $$', addr: 'Shop 7, 401 Sussex St, Haymarket' },
    'Bar Totti’s': { sub: 'Barangaroo, Sydney', meta: '4.6 (2,310) · Italian · $$$', addr: '10 Barangaroo Ave, Barangaroo' },
    'Chaco Bar': { sub: 'Darlinghurst, Sydney', meta: '4.8 (906) · Yakitori · $$', addr: '186–188 Victoria St, Darlinghurst' },
  };
  function placeItem(name) {
    const p = PLACES[name] || PLACES['Ramen Ikkyu'];
    return { kind: 'place', label: 'PLACE · SAVED ' + (name === 'Ramen Ikkyu' ? '3 WEEKS' : '2 MONTHS') + ' AGO', title: p.title || name, sub: p.sub, shot: 'place',
      rename: [['Ramen Ikkyu', p.title || name], ['4.7 (1,284) · Japanese · $$', p.meta], ['Shop 7, 401 Sussex St, Haymarket', p.addr]],
      actions: [['map', 'GET DIRECTIONS', `Directions to ${p.title || name} open in Maps`], ['cal', 'PLAN', 'Pick a night to go'], ['send', 'SEND', 'The share sheet opens here']] };
  }
  function shotOf(item, w, h, opts) {
    let html = screenshot(item.shot, w, h, opts);
    (item.rename || []).forEach(([a, b]) => { html = html.split(a).join(b); });
    return html;
  }

  const SETUP = {
    // Setup: start reading, watch the count run, then land on Home.
    scan() {
      const cta = $('.cta'), title = $('.title');
      const dial = $('#dial');
      let started = false;
      tap(cta, () => {
        if (started) return; started = true;
        const g = dial && dial.querySelector(':scope > g:last-of-type');
        if (g) {
          const wrap = document.createElementNS('http://www.w3.org/2000/svg', 'g');
          g.parentNode.insertBefore(wrap, g); wrap.appendChild(g);
          wrap.style.transformOrigin = '196.5px 570px';
          wrap.animate([{ transform: 'rotate(0deg)' }, { transform: 'rotate(120deg)' }], { duration: 2600, easing: 'cubic-bezier(.45,0,.2,1)', fill: 'forwards' });
        }
        cta.querySelector('span').textContent = 'Reading…';
        const total = 412, t0 = performance.now();
        (function step(now) {
          const k = Math.min(1, (now - t0) / 2600), n = Math.round(total * (1 - Math.pow(1 - k, 2)));
          title.innerHTML = k < 1 ? `Reading ${n} of ${total}<br>screenshots on this iPhone` : `All ${total} read.<br>Here's what you saved.`;
          if (k < 1) requestAnimationFrame(step); else setTimeout(() => post({ type: 'root', to: 'home' }), 700);
        })(t0);
      });
    },

    home() {
      tabs();
      const days = $$('.days .chip-circle');
      days.forEach(d => tap(d, () => { days.forEach(x => x.classList.remove('on')); d.classList.add('on'); }));
      tap($('.days .btn-circle'), () => go('recaptime'));
      tap($('.t-num-xl'), () => go('history'));
      tap($('#chart'), () => go('history'));
      const tiles = $$('.bento .tile');
      tap(tiles[0], () => go('history'));
      tap(tiles[1], () => go('stillwant'));
      tap(tiles[2], () => go('history'));
      tap(tiles[3], () => go('item', ITEMS.mallrat));
      tap(tiles[4], () => go('item', ITEMS.lamp));
    },

    saved() {
      tabs();
      $$('.grid .tile').forEach(t => tap(t, () => {
        const name = text($('.lbl', t)).split('·')[0].trim();
        if (/PLACES/.test(name)) go('stillwant');
        else toast(`Only Places is filled in for this prototype`);
      }));
      $$('.hdr .btn-circle').forEach(b => tap(b, () => toast('Search and filters come later')));
    },

    reveals() {
      tabs();
      $$('.card').forEach(c => tap(c, () => present('story')));
      tap($('.btn-circle'), () => toast('Pick another year here'));
    },

    item() {
      const item = DATA && DATA.title && DATA.title !== 'Mallrat' ? DATA : ITEMS.mallrat;
      const light = LIGHT[item.kind] || 'events';
      const backBtn = $$('.hdr .btn-circle')[0], more = $$('.hdr .btn-circle')[1];
      tap(backBtn, back);
      tap(more, () => toast('Edit, move or delete'));
      if (item !== ITEMS.mallrat) {
        const lbl = $('.ident .kind .t-label'); if (lbl) lbl.textContent = item.label;
        const dot = $('.ident .kind i'); if (dot) { dot.style.background = `var(--${light}-c)`; dot.style.boxShadow = `0 0 8px var(--${light}-c)`; }
        const t = $('.ident .t-large'); if (t) t.textContent = item.title;
        const s = $('.ident .t-body'); if (s) s.textContent = item.sub;
        const l = $('.hero .light'); if (l) l.style.background = `var(--${light}-c)`;
        const shot = $('.shot'); if (shot) shot.innerHTML = shotOf(item, shot.offsetWidth, shot.offsetHeight, { sharp: true });
        const count = $('.count'); if (count) count.textContent = '1 SCREENSHOT';
      }
      const sc = $$('.scenario');
      const fill = sc.find(x => x.classList.contains('fill')), rest = sc.filter(x => !x.classList.contains('fill'));
      const acts = item.actions || ITEMS.mallrat.actions;
      if (fill) {
        fill.innerHTML = icon(acts[0][0], 18) + acts[0][1];
        if (item !== ITEMS.mallrat) fill.style.background = `linear-gradient(100deg, var(--${light}-c), color-mix(in srgb, var(--${light}-c) 70%, var(--${light}-d)))`;
        tap(fill, () => toast(acts[0][2]));
      }
      rest.forEach((b, i) => {
        if (/DONE/.test(text(b))) return tap(b, () => { toast(`${item.title} is done. Score 7`); setTimeout(back, 900); });
        const a = acts[i + 1];
        if (a) { b.innerHTML = icon(a[0], 18) + a[1]; if (item !== ITEMS.mallrat) b.style.setProperty('--c', `var(--${light}-c)`); tap(b, () => toast(a[2])); }
      });
    },

    stillwant() {
      const btns = $$('.btn-circle');
      tap(btns[0], back);
      tap(btns[1], () => toast('Filter by area or when you saved it'));
      const titles = $$('.title');
      const boxes = $$('.wheel .box');
      titles.forEach((t, i) => {
        const name = text($('.t-title', t));
        const data = name === 'Studio Kiri' ? ITEMS.lamp : name === 'Enmore Theatre' ? ITEMS.mallrat : placeItem(name);
        const open = () => go('item', data);
        tap(t, open);
        if (boxes[i]) tap(boxes[i], open);
      });
    },

    triage() {
      const DECK = [
        { item: ITEMS.mallrat, label: 'EVENT', title: 'Mallrat at the Enmore', sub: 'Sun 11 Oct · Doors 7pm', big: '11', unit: 'Oct', right: '2 SCREENSHOTS' },
        { item: ITEMS.ramen, label: 'PLACE', title: 'Ramen Ikkyu', sub: 'Haymarket · Open till 10pm', big: '3', unit: 'weeks ago', right: '1 SCREENSHOT' },
        { item: ITEMS.lamp, label: 'PRODUCT', title: 'Dune lamp, Studio Kiri', sub: '$189 · Sale ends Friday', big: '2', unit: 'days left', right: '1 SCREENSHOT' },
        { item: ITEMS.rigatoni, label: 'RECIPE', title: 'Tomato butter rigatoni', sub: '25 min · Serves 2', big: '5', unit: 'ingredients', right: '1 SCREENSHOT' },
      ];
      const card = $('.card'), counter = byText('.t-label', '1 /');
      const seg = $$('.seg .seg-btn');
      const tally = { keep: 0, drop: 0, done: 0 };
      let i = 0, busy = false;
      tap($('.btn-circle'), close);

      function fill(c) {
        const light = LIGHT[c.item.kind];
        const kind = $('.kind .t-label', card); if (kind) kind.textContent = c.label;
        const dot = $('.kind .dot', card) || $('.kind i', card); if (dot) dot.style.background = `var(--${light}-c)`;
        const ttl = $('.ttl', card); if (ttl) ttl.textContent = c.title;
        const sub = $('.meta .t-body', card); if (sub) sub.textContent = c.sub;
        const big = $('.when .t-num-l', card); if (big) big.textContent = c.big;
        const unit = $('.when .t-unit', card); if (unit) unit.textContent = c.unit;
        const right = $$('.when > *', card).pop(); if (right && right !== big?.parentNode) right.textContent = c.right;
        const shot = $('#shot');
        if (shot) {
          const inEl = $('.in', card), r = inEl.getBoundingClientRect(), panel = $('.panel', card);
          shot.innerHTML = screenshot(c.item.shot, r.width + 20, r.height - (panel ? panel.offsetHeight : 228) + 90, { hero: true, blurX: 14, blurY: 5 });
        }
        if (counter) counter.textContent = `${i + 1} / ${DECK.length}`;
      }

      async function decide(kind) {
        if (busy) return; busy = true;
        tally[kind]++;
        const out = { keep: 'translate(120%, 0) rotate(10deg)', drop: 'translate(-120%, 0) rotate(-10deg)', done: 'translate(0, -110%) scale(.96)' }[kind];
        toast({ keep: 'Kept. It stays in Still want', drop: 'Dropped', done: 'Done. Score 7' }[kind]);
        await card.animate([{ transform: card.style.transform || 'none', opacity: 1 }, { transform: out, opacity: 0 }], { duration: 380, easing: 'cubic-bezier(.4,0,1,1)', fill: 'forwards' }).finished;
        i++;
        if (i >= DECK.length) {
          toast(`Tonight's recap is done: ${tally.keep} kept, ${tally.drop} dropped, ${tally.done} done`);
          setTimeout(close, 700); return;
        }
        card.getAnimations().forEach(a => a.cancel()); card.style.transform = '';
        fill(DECK[i]);
        await card.animate([{ transform: 'scale(.92)', opacity: 0 }, { transform: 'scale(1)', opacity: 1 }], { duration: 420, easing: EASE }).finished;
        busy = false;
      }
      tap(seg.find(b => /Still want/.test(text(b))), () => decide('keep'));
      tap(seg.find(b => /Drop/.test(text(b))), () => decide('drop'));
      tap(seg.find(b => /Done/.test(text(b))), () => decide('done'));

      // Drag the card: right keeps it, left drops it, up marks it done.
      let sx = 0, sy = 0, dragging = false;
      card.style.touchAction = 'none';
      card.addEventListener('pointerdown', (e) => { if (busy) return; dragging = true; sx = e.clientX; sy = e.clientY; card.setPointerCapture(e.pointerId); });
      card.addEventListener('pointermove', (e) => {
        if (!dragging) return;
        const dx = e.clientX - sx, dy = Math.min(0, e.clientY - sy);
        card.style.transform = `translate(${dx}px, ${dy}px) rotate(${dx / 24}deg)`;
      });
      const end = (e) => {
        if (!dragging) return; dragging = false;
        const dx = e.clientX - sx, dy = e.clientY - sy;
        if (dx > 110) return decide('keep');
        if (dx < -110) return decide('drop');
        if (dy < -140) return decide('done');
        card.animate([{ transform: card.style.transform || 'none' }, { transform: 'none' }], { duration: 380, easing: EASE });
        card.style.transform = '';
      };
      card.addEventListener('pointerup', end);
      card.addEventListener('pointercancel', end);
      fill(DECK[0]);
    },

    history() {
      tap($('.btn-circle'), back);
      tap(byText('.seg-btn', 'Start recap'), () => present('triage'));
      tap(byText('.seg-btn', 'Recap time'), () => go('recaptime'));
    },

    recaptime() {
      tap($('.btn-circle'), back);
      const big = $('.big'), unit = $('.unit'), toggle = $('.toggle');
      let minutes = 21 * 60 + 30, on = true;
      const fmt = (m) => { const h = Math.floor(m / 60) % 24, mm = m % 60; return [`${((h + 11) % 12) + 1}:${String(mm).padStart(2, '0')}`, h < 12 ? 'AM' : 'PM']; };
      const render = () => { const [t, ap] = fmt(minutes); big.textContent = t; unit.textContent = ap; };
      tap(toggle, () => {
        on = !on;
        const knob = $('i', toggle);
        knob.animate([{ transform: `translateX(${on ? -26 : 0}px)` }, { transform: `translateX(${on ? 0 : -26}px)` }], { duration: 300, easing: EASE, fill: 'forwards' });
        toggle.style.background = on ? '#1d0e08' : 'rgba(29,14,8,.25)';
        $('.card').animate([{ filter: on ? 'saturate(.3) brightness(.85)' : 'none' }, { filter: on ? 'none' : 'saturate(.3) brightness(.85)' }], { duration: 300, fill: 'forwards' });
        toast(on ? 'Nightly recap on' : 'Nightly recap off');
      });
      const days = $$('.days span');
      const sayDays = () => {
        const sel = days.map(d => d.classList.contains('on'));
        const wk = sel.slice(0, 5).every(Boolean), we = sel.slice(5).every(Boolean), none = !sel.some(Boolean);
        return none ? 'on no nights' : wk && we ? 'every night' : wk && !sel[5] && !sel[6] ? 'on weeknights' : we && !sel.slice(0, 5).some(Boolean) ? 'on weekends' : `${sel.filter(Boolean).length} nights a week`;
      };
      days.forEach(d => tap(d, () => d.classList.toggle('on')));
      // Drag across the ruler (or the time) to move by quarter hours.
      const ruler = $('#ruler');
      [ruler, big].forEach(el => {
        if (!el) return;
        el.style.touchAction = 'none'; el.style.cursor = 'ew-resize';
        let x0 = 0, m0 = 0, down = false;
        el.addEventListener('pointerdown', (e) => { down = true; x0 = e.clientX; m0 = minutes; el.setPointerCapture(e.pointerId); });
        el.addEventListener('pointermove', (e) => {
          if (!down) return;
          const steps = Math.round((x0 - e.clientX) / 14);
          minutes = ((m0 + steps * 15) % 1440 + 1440) % 1440; render();
          ruler.style.transform = `translateX(${((e.clientX - x0) % 44)}px)`;
        });
        const up = () => { down = false; ruler.animate([{ transform: ruler.style.transform || 'none' }, { transform: 'none' }], { duration: 300, easing: EASE }); ruler.style.transform = ''; };
        el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
      });
      const cta = $('#cta') || $('.cta');
      tap(cta, () => { const [t, ap] = fmt(minutes); toast(on ? `Recap set for ${t} ${ap.toLowerCase()}, ${sayDays()}` : 'Saved. Nightly recap is off'); setTimeout(back, 900); });
    },

    story() {
      reveal({ next: () => swap('peak'), prev: null });
    },

    peak() {
      reveal({ next: () => { toast("That's this month's Reveal"); close(); }, prev: () => swap('story') });
      const tabsEl = $$('.t-label').filter(el => ['TIME', 'DAY', 'CATEGORY', 'MONTH', 'SOURCE'].includes(text(el)));
      const panelLabel = byText('.glass .t-label', 'PEAK'), panelValue = $('.glass .t-num-l') && $('.glass .t-num-l').parentNode;
      const orb = [$('.orb-disc'), $$('svg.abs')[1]].filter(Boolean);
      const VIEWS = {
        TIME: ['PEAK · TUESDAYS', ['12:40', 'am'], [0, 0]],
        DAY: ['BUSIEST · SUNDAYS', ['41', 'saved'], [100, 170]],
        CATEGORY: ['MOST · PLACES', ['61', 'saved'], [40, 220]],
        MONTH: ['BUSIEST · JULY', ['72', 'saved'], [170, 30]],
        SOURCE: ['MOST FROM · BROWSER', ['58', '%'], [96, 120]],
      };
      tabsEl.forEach(t => tap(t, () => {
        tabsEl.forEach(x => (x.style.color = 'var(--ink-3)')); t.style.color = 'var(--ink)';
        const [l, v, [dx, dy]] = VIEWS[text(t)];
        if (panelLabel) panelLabel.textContent = l;
        if (panelValue) panelValue.innerHTML = `<span class="t-num-l">${v[0]}</span><span class="t-unit" style="margin-left:4px">${v[1]}</span>`;
        orb.forEach(o => o.animate([{ transform: getComputedStyle(o).transform === 'none' ? 'translate(0,0)' : getComputedStyle(o).transform }, { transform: `translate(${dx}px, ${dy}px)` }], { duration: 700, easing: EASE, fill: 'forwards' }));
      }));
      tap($('#send'), () => toast('Share this card to your story'));
    },

    widget() {
      const open = () => present('triage');
      ['.card', '#thumb', '.lyrics'].forEach(s => tap($(s), open));
      tap($('#ctl-x'), () => toast('Dropped. Next up: Ramen Ikkyu'));
      tap($('#ctl-go'), () => toast('Kept. It stays in Still want'));
      tap($('#ctl-keep'), () => toast('Done. Score 7'));
    },
  };

  function tabs() {
    const t = $$('.tabbar .tab');
    ['home', 'saved', 'reveals'].forEach((n, i) => tap(t[i], () => { if (n !== NAME) tabTo(n); }));
  }

  // Reveal cards: the current story bar fills, then the next card. Tap the right side to skip ahead,
  // the left side to go back, or the close button to leave.
  function reveal({ next, prev }) {
    const bars = $$('.story-bars span');
    const cur = Math.max(0, bars.findIndex(b => b.classList.contains('on')));
    bars.forEach((b, i) => { b.style.position = 'relative'; b.style.overflow = 'hidden'; if (i < cur) b.style.background = 'var(--accent)'; });
    const bar = bars[cur];
    let timer;
    if (bar) {
      bar.classList.remove('on');
      const f = document.createElement('i');
      f.style.cssText = 'position:absolute;left:0;top:0;bottom:0;width:100%;background:var(--accent);transform-origin:0 50%;transform:scaleX(0)';
      bar.appendChild(f);
      const a = f.animate([{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], { duration: 7000, easing: 'linear', fill: 'forwards' });
      a.finished.then(() => { timer = setTimeout(next, 150); });
    }
    tap($('#close') || $('.story-head .btn-circle'), () => { clearTimeout(timer); close(); });
    document.body.addEventListener('click', (e) => {
      if (e.target.closest('.p-tap')) return;
      const x = e.clientX / innerWidth;
      if (x > .35) next(); else if (prev) prev();
    });
  }

  function ready() {
    try { (SETUP[NAME] || (() => {}))(); } catch (e) { console.error(e); }
    requestAnimationFrame(() => requestAnimationFrame(() => post({ type: 'ready' })));
  }
  if (document.readyState === 'complete') ready();
  else addEventListener('load', () => (document.fonts ? document.fonts.ready : Promise.resolve()).then(ready));
})();
