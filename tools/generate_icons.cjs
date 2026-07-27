const fs = require("fs");
const path = require("path");
const sharp = require("sharp");
const { DOMParser, XMLSerializer } = require("@xmldom/xmldom");

const SVG_PATH = path.resolve(__dirname, "..", "docs", "assets", "icon.svg");

const TARGETS = [
  {
    out: path.resolve(__dirname, "..", "AppScope", "resources", "base", "media", "background.png"),
    layer: "background",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "AppScope", "resources", "base", "media", "foreground.png"),
    layer: "foreground",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "AppScope", "resources", "base", "media", "leantty_icon.png"),
    layer: "full",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "entry", "src", "main", "resources", "base", "media", "background.png"),
    layer: "background",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "entry", "src", "main", "resources", "base", "media", "foreground.png"),
    layer: "foreground",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "entry", "src", "main", "resources", "base", "media", "leantty_icon.png"),
    layer: "full",
    size: 1024,
  },
  {
    out: path.resolve(__dirname, "..", "entry", "src", "main", "resources", "base", "media", "startIcon.png"),
    layer: "full",
    size: 144,
  },
];

function prepareSvg(layer) {
  const svgText = fs.readFileSync(SVG_PATH, "utf-8");
  const parser = new DOMParser();
  const doc = parser.parseFromString(svgText, "image/svg+xml");
  const root = doc.documentElement;

  if (layer === "background") {
    const groups = root.getElementsByTagName("g");
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].getAttribute("id") === "foreground") {
        groups[i].setAttribute("style", "display:none");
      }
    }
  } else if (layer === "foreground") {
    const groups = root.getElementsByTagName("g");
    for (let i = 0; i < groups.length; i++) {
      if (groups[i].getAttribute("id") === "background") {
        groups[i].setAttribute("style", "display:none");
      }
    }
  }

  const serializer = new XMLSerializer();
  return serializer.serializeToString(root);
}

async function generateIcon(outPath, layer, size) {
  const svgStr = prepareSvg(layer);
  const svgBuffer = Buffer.from(svgStr, "utf-8");

  await sharp(svgBuffer).resize(size, size).png().toFile(outPath);

  console.log(`Generated: ${outPath} (${size}x${size}, layer=${layer})`);
}

async function main() {
  for (const t of TARGETS) {
    await generateIcon(t.out, t.layer, t.size);
  }
  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
