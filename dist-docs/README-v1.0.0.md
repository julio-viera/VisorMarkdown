# Visor Markdown 1.0.0-beta.1

**First beta · Pre-release**

Visor Markdown is a Markdown editor and viewer with tabs, search, comparison, and export. Write in the editor and see the formatted document update beside it. The panels scroll together so you can follow the same part of the document.

## What you can do in this beta

- Open several documents in tabs, edit with line numbers, and move between search matches.
- Compare two documents side by side, with additions and removals highlighted and controls to jump between changes.
- Choose GitHub Flavored Markdown, CommonMark, or Markdown Original. Insert sample tables in GitHub mode.
- Export to Word (.docx), LibreOffice (.odt), PDF, HTML, plain text, or Markdown. Word and LibreOffice exports embed supported images using the same permissions as the preview.
- Follow the system theme or choose light or dark mode. Customize colors, fonts, and text sizes.

## Downloads and documentation

[Release history and downloads](../RELEASES.md) · [App overview](../README.md) · [Third-party notices](../THIRD_PARTY_NOTICES.md)

The project provides [packaging scripts](../tools/) for DEB, RPM, Flatpak, Snap, and AppImage on Linux.

### Build an AppImage

Build the Linux release bundle with `tools/build.sh`. With `appimagetool` on your path, run `tools/package-appimage.sh`. You can also set `APPIMAGETOOL` to the executable path and pass a custom bundle directory as the first argument. The package is written to `dist/<version>/appimage/`. `tools/package-all.sh` also builds this format.

For offline packaging, set `APPIMAGE_RUNTIME` to a local Type 2 runtime for your architecture.

Run the executable AppImage on a compatible Linux system with GTK 3 and the Flutter bundle’s system libraries. Desktop integration tools can use the included launcher, icon, and Markdown MIME associations.
