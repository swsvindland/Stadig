# The README's images

Small copies made for the repository's front page, so it loads fast and its links don't break when a capture is retaken. Every other screenshot is in `Store/` and shown by [screenshots.md](../screenshots.md).

| File | From | How |
|---|---|---|
| `banner.png` | `Site/public/og.png` | Copied. `Site/scripts/og.sh` draws it. |
| `lift-set.webp`, `lift-shape.webp`, `macro-today.webp`, `macro-plan.webp` | `Site/public/shots/` (`lift-set`, `lift-shape`, `macro-today`, `macro-plan`) | Copied, without the hash in the name. |
| `lift-mac.webp` | `Store/lift/.storeassets/captures/desktop/today.png` | `cwebp -q 84 -resize 1600 0` |
| `macro-mac.webp` | `Store/macro-mac-vision/.storeassets/captures/desktop/today.png` | `cwebp -q 84 -resize 1600 0` |
| `lift-vision.webp` | `Store/lift/.storeassets/captures/xr/today.png` | `cwebp -q 82 -resize 1600 0` |
| `lift-icon.png`, `macro-icon.png` | `Store/<app>/.storeassets/brand/icon.png` | `sips -Z 192` |

When a screen here changes, retake the source (`Site/README.md` for the site's shots, `Store/README.md` for the store's) and make the copy again.
