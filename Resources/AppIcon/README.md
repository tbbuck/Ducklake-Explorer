# App icon

A rubber duck (DuckDB-yellow body and head) floating on a waterline, with the
Stratum water-depth ramp descending beneath it as wavy laminae. Design "C2b",
chosen 2026-09-10. Palette from `DESIGN-TOKENS.md` (Night).

| File | Role |
|---|---|
| `AppIcon.icon/` | **The app icon.** Icon Composer bundle (Liquid Glass): `icon.json` + one 1024px full-canvas SVG per layer under `Assets/`. Referenced from `project.yml` via `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`; actool renders every size (and a fallback icns) from it. |
| `DuckLakeExplorer-icon.svg` | Flat master of the same design, with Apple's squircle tile baked in. |
| `DuckLakeExplorer-icon-small.svg` | Hand-tuned art for 16px and 32px: bigger duck, two flat water bands, no detail. |
| `DuckLakeExplorer.icns` | Legacy icns built from the two flat masters by `scripts/render-app-icon.sh`. For DMG art, docs, and non-Xcode packaging only. |
| `canvas/` | Sources of the design canvas used to choose the icon (final on page 1, explorations on page 2). `early/` holds the first-round sketches. |

## Icon Composer bundle notes

Learned from Apple's Landmarks sample and confirmed by compiling test bundles
with actool:

- Layers are full-canvas 1024×1024 SVGs. The system applies the squircle mask,
  so the flat masters' 824pt tile is scaled up by 1024/824 inside each layer.
- **Arrays are top-to-bottom.** The first group renders above the second, and the
  first layer in a group renders above the next. (Get this wrong and lower
  layers silently disappear.)
- `glass: true` gives a layer the Liquid Glass material; the group's `shadow`,
  `specular`, `translucency` and `lighting` apply on top.
- Keep layer SVGs simple: shapes, paths, fills, gradients. No filters, masks or
  text.

## Regenerating

```sh
scripts/render-app-icon.sh        # flat masters -> DuckLakeExplorer.icns
scripts/render-icon-bundle.sh     # compile AppIcon.icon with actool and unpack it to look
xcodegen generate                 # only needed if project.yml changed
```
