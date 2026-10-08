// v3 additions: glass type with real depth. Uses screenshot(), statusBar(), icon(), folderPath()
// from kit.js.

/**
 * Glass type: a frosted face lit from the top left (an embossed specular highlight), an extruded
 * edge below it, a contact shadow, and a tinted light where it meets the surface.
 */
function glassType(text, { size = 160, weight = 600, width = 200, height = 200, tint = "#ffffff", depth = 7, family = "Inter Display" } = {}) {
  const id = "t" + Math.random().toString(36).slice(2, 7);
  const base = height - size * 0.2;
  const font = `font-family="${family}" font-weight="${weight}" font-size="${size}" letter-spacing="${-size * 0.04}"`;
  let edge = "";
  for (let i = depth; i >= 1; i--) {
    edge += `<text x="0" y="${base + i}" ${font} fill="${tint}" fill-opacity="${0.05 + (depth - i) * 0.012}" stroke="rgba(255,255,255,${0.04 + (depth - i) * 0.01})" stroke-width=".6">${text}</text>`;
  }
  return `<svg width="${width}" height="${height + 30}" viewBox="0 0 ${width} ${height + 30}" style="display:block;overflow:visible">
    <defs>
      <linearGradient id="${id}f" x1="0" y1="0" x2="0.3" y2="1">
        <stop offset="0" stop-color="#ffffff" stop-opacity=".55"/>
        <stop offset=".5" stop-color="${tint}" stop-opacity=".14"/>
        <stop offset="1" stop-color="#ffffff" stop-opacity=".28"/>
      </linearGradient>
      <linearGradient id="${id}k" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#fff" stop-opacity=".95"/>
        <stop offset=".5" stop-color="#fff" stop-opacity=".25"/>
        <stop offset="1" stop-color="#fff" stop-opacity=".7"/>
      </linearGradient>
      <filter id="${id}e" x="-20%" y="-20%" width="140%" height="140%">
        <feGaussianBlur in="SourceAlpha" stdDeviation="${size * 0.018}" result="b"/>
        <feSpecularLighting in="b" surfaceScale="${size * 0.05}" specularConstant="1.2" specularExponent="22" lighting-color="#ffffff" result="s">
          <fePointLight x="${-width * 0.4}" y="${-height * 0.8}" z="${size * 2.2}"/>
        </feSpecularLighting>
        <feComposite in="s" in2="SourceAlpha" operator="in" result="si"/>
        <feComposite in="SourceGraphic" in2="si" operator="arithmetic" k1="0" k2="1" k3=".9" k4="0"/>
      </filter>
      <filter id="${id}s" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="${size * 0.06}"/></filter>
      <filter id="${id}r" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="${size * 0.1} ${size * 0.03}"/></filter>
    </defs>
    <ellipse cx="${width * 0.45}" cy="${base + depth + 8}" rx="${width * 0.42}" ry="${size * 0.06}" fill="${tint}" opacity=".35" filter="url(#${id}r)"/>
    <text x="4" y="${base + depth + 10}" ${font} fill="#000" opacity=".35" filter="url(#${id}s)">${text}</text>
    ${edge}
    <text x="0" y="${base}" ${font} fill="url(#${id}f)" filter="url(#${id}e)">${text}</text>
    <text x="0" y="${base}" ${font} fill="none" stroke="url(#${id}k)" stroke-width="1.6">${text}</text>
  </svg>`;
}
