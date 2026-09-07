// Builds BarClone/branding/logo.svg with a real WoW spell icon embedded, then rasterizes it.
const sharp = require("sharp");
const fs = require("fs");

const OUT_DIR = "E:/Games/World of Warcraft/_anniversary_/Interface/AddOns/BarClone/branding";
// Left icon (source) and right icon (target). Defaults: Mortal Strike -> Bloodthirst.
const ICON_FROM = process.argv[2] || "icons/ability_warrior_savageblow.jpg";
const ICON_TO = process.argv[3] || "icons/spell_nature_bloodlust.jpg";

async function main() {
  // Upscale the 56px icons cleanly and embed them as PNG.
  const embed = async (file) => {
    const buf = await sharp(file)
      .resize(256, 256, { kernel: sharp.kernel.lanczos3 })
      .sharpen({ sigma: 0.8 })
      .png()
      .toBuffer();
    return "data:image/png;base64," + buf.toString("base64");
  };
  const iconFrom = await embed(ICON_FROM);
  const iconTo = await embed(ICON_TO);

  const button = (x, y, dataUri) => `
  <g transform="translate(${x},${y})" filter="url(#shadow)">
    <rect x="4" y="4" width="144" height="144" rx="14" fill="url(#frame)" stroke="url(#gold)" stroke-width="8"/>
    <clipPath id="clip${x}"><rect x="18" y="18" width="116" height="116" rx="6"/></clipPath>
    <image href="${dataUri}" xlink:href="${dataUri}" x="18" y="18" width="116" height="116" clip-path="url(#clip${x})" preserveAspectRatio="xMidYMid slice"/>
    <rect x="18" y="18" width="116" height="116" rx="6" fill="none" stroke="#000" stroke-opacity="0.6" stroke-width="3"/>
    <rect x="21" y="21" width="110" height="110" rx="4" fill="none" stroke="#fff" stroke-opacity="0.12" stroke-width="2"/>
  </g>`;

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#241d12"/>
      <stop offset="1" stop-color="#0f0c08"/>
    </linearGradient>
    <linearGradient id="frame" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#6b5730"/>
      <stop offset="1" stop-color="#2a2114"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffe9a8"/>
      <stop offset="0.5" stop-color="#e2b34a"/>
      <stop offset="1" stop-color="#9a6a12"/>
    </linearGradient>
    <radialGradient id="glowHalo" cx="50%" cy="50%" r="50%">
      <stop offset="0" stop-color="#ffcc55" stop-opacity="0.45"/>
      <stop offset="1" stop-color="#ffcc55" stop-opacity="0"/>
    </radialGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="8" stdDeviation="8" flood-color="#000" flood-opacity="0.7"/>
    </filter>
  </defs>

  <rect x="0" y="0" width="512" height="512" rx="100" fill="url(#bg)"/>
  <rect x="10" y="10" width="492" height="492" rx="92" fill="none" stroke="#5c4a26" stroke-width="4" stroke-opacity="0.8"/>

  <circle cx="396" cy="256" r="120" fill="url(#glowHalo)"/>
${button(40, 180, iconFrom)}
  <g filter="url(#shadow)">
    <path d="M206 236 H272 V206 L322 256 L272 306 V276 H206 Z"
          fill="url(#gold)" stroke="#3a2a0c" stroke-width="5" stroke-linejoin="round"/>
    <path d="M214 244 H266" fill="none" stroke="#fff4cc" stroke-width="3" stroke-opacity="0.7" stroke-linecap="round"/>
  </g>
${button(320, 180, iconTo)}
</svg>
`;

  fs.writeFileSync(`${OUT_DIR}/logo.svg`, svg);
  for (const s of [512, 400, 128]) {
    await sharp(Buffer.from(svg), { density: 300 }).resize(s, s).png().toFile(`${OUT_DIR}/logo-${s}.png`);
    console.log("wrote", s);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
