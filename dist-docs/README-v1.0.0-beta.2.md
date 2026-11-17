# Visor Markdown 1.0.0-beta.2

**Second beta · Pre-release**

## What changed since 1.0.0-beta.1

- **Unicode character map.** Use **Insert character** next to the Markdown reference to browse characters and icons. Search the entire offline Unicode 17.0 catalog by symbol, English name, or Unicode code. Choose an entry to insert it at the cursor or replace the current selection.
- **PDF export.** A bundled fallback font lets the exporter render additional symbols, including ✓, ★, and ⚠.
- **AppImage packaging.** The Linux packager can now generate an AppImage with the application icon, desktop launcher, and Markdown file associations for desktop integration tools.
- **Third-party notices.** Application bundles include an index of license notices, including those for the Unicode data, bundled fonts, and additional dependency notices.

## Downloads and documentation

[Download 1.0.0-beta.2 on GitHub](https://github.com/julio-viera/VisorMarkdown/releases/tag/v1.0.0-beta.2) · [Release history](../RELEASES.md) · [Previous beta](README-v1.0.0-beta.1.md) · [Third-party notices](../THIRD_PARTY_NOTICES.md)

### Build an AppImage

Build the Linux release bundle with `tools/build.sh`. With `appimagetool` on your path, run `tools/package-appimage.sh`. You can also set `APPIMAGETOOL` to the executable path and pass a custom bundle directory as the first argument. The package is written to `dist/<version>/appimage/`. `tools/package-all.sh` also builds this format.

For offline packaging, set `APPIMAGE_RUNTIME` to a local Type 2 runtime for your architecture.

Run the executable AppImage on a compatible Linux system with GTK 3 and the Flutter bundle’s system libraries.
