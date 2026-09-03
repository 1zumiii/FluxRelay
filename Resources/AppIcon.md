# FluxRelay App Icon

The icon uses an ivory F-shaped ribbon ending in a download arrow, on an emerald tile. It was generated with the built-in image generation tool, then locally prepared with the user's approval to remove the baked-in checkerboard matte and add transparent Dock margins.

- `AppIcon-source.png`: original generated bitmap.
- `AppIcon.png`: 1024-pixel RGBA master consumed by `Scripts/package-app.sh`.
- The packaging script exports every macOS icon size, including Retina representations.

To rebuild the transparent master from this source:

```sh
swift Scripts/prepare-app-icon.swift Resources/AppIcon-source.png Resources/AppIcon.png
```

The preparation script is specific to this source's light neutral exterior matte; it is not a general background remover.

## Generation Prompt

Create a finished production macOS app icon for FluxRelay, a native download manager. Brand direction: data moving and being relayed, precise, modern, quiet craftsmanship. Square raster icon with transparent outer background and corners. Center a macOS rounded-square tile occupying about 82% of the canvas, a rich deep emerald/teal enamel surface with very subtle directional lighting, not a glass bubble. In its center, make a single large distinctive geometric ivory-white route/ribbon symbol: a broad vertical stem and two short horizontal rightward arms suggesting an F; the lower part of the stem terminates in a bold downward arrow, conveying downloading. Keep the silhouette readable at 32px, with substantial stroke widths, clean straight segments and restrained softened corners. A small mint-colored edge on one fold gives a sense of flow. The symbol feels slightly raised with a soft tight contact shadow, not glossy chrome. Front-facing, no tilt or perspective. No border frame, extra background plate, tray, purple, wordmark, text, watermark, or surrounding illustration.

The final edit requested removal of the exterior checkerboard only, keeping the tile, symbol, proportions, colors, and internal shadows unchanged. The generated result still had an opaque matte, so the local preparation step provides the actual alpha channel.
