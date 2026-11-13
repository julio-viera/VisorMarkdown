#!/usr/bin/env bash
# Package an already compiled Linux bundle. Never installs tools or publishes.
set -euo pipefail
cd "$(dirname "$0")/.."
kind="${1:-}"
case "$kind" in deb|rpm|flatpak|snap|appimage) ;; *) echo 'Usage: tools/package.sh deb|rpm|flatpak|snap|appimage [bundle-directory]' >&2; exit 2;; esac
case "$(uname -m)" in x86_64) flutterarch=x64;; aarch64) flutterarch=arm64;; *) echo 'Unsupported architecture' >&2; exit 1;; esac
bundle="${2:-build/linux/$flutterarch/release/bundle}"
bundle="$(realpath "$bundle")"
metadata="$bundle/data/flutter_assets/assets/app_info.json"
# Read the metadata shipped with this particular compiled application.
package_info="$(python3 tools/app-info.py package "$metadata")"
mapfile -t info <<< "$package_info"
version="${info[0]}"; native_version="${info[1]}"; name="${info[2]}"; author="${info[3]}"
license="${info[4]}"; appid="${info[5]}"; binary="${info[6]}"; repo="${info[7]}"
description="${info[8]}"
[[ -f "$bundle/$binary" ]] || { echo 'Run tools/build.sh first or supply a compiled bundle.' >&2; exit 1; }
out="$(pwd)/dist/$version/$kind"
mkdir -p "$out"
python3 tools/app-info.py package "$metadata" "$out"
need() { command -v "$1" >/dev/null || { echo "Missing packaging tool: $1" >&2; exit 1; }; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/opt/$binary" "$stage/root/usr/bin" "$stage/root/usr/share/applications" "$stage/root/usr/share/icons/hicolor/scalable/apps" "$stage/root/usr/share/licenses/$binary" "$stage/root/usr/share/mime/packages"
cp -a "$bundle/." "$stage/root/opt/$binary/"
cp LICENSE "$stage/root/opt/$binary/LICENSE"
cp assets/linux/markdown.xml "$stage/root/usr/share/mime/packages/$appid.xml"
cp LICENSE "$stage/root/usr/share/licenses/$binary/LICENSE"
cp assets/visor-markdown.svg "$stage/root/usr/share/icons/hicolor/scalable/apps/$appid.svg"
cat > "$stage/root/usr/bin/$binary" <<SCRIPT
#!/bin/sh
exec /opt/$binary/$binary "\$@"
SCRIPT
chmod +x "$stage/root/usr/bin/$binary"
cat > "$stage/root/usr/share/applications/$appid.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Comment=$description
Exec=$binary %F
TryExec=$binary
StartupNotify=true
Icon=$appid
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/markdown;text/x-markdown;text/plain;
DESKTOP
chmod -R go-w "$stage/root"
case "$(uname -m)" in x86_64) debarch=amd64; snaparch=amd64;; aarch64) debarch=arm64; snaparch=arm64;; *) echo 'Unsupported architecture' >&2; exit 1;; esac
case "$kind" in
  deb)
    need dpkg-deb
    mkdir -p "$stage/root/DEBIAN"
    cat > "$stage/root/DEBIAN/control" <<CONTROL
Package: $binary
Version: $native_version
Section: editors
Priority: optional
Architecture: $debarch
Maintainer: $author
Homepage: $repo
Depends: libgtk-3-0, libstdc++6, libsecret-1-0, desktop-file-utils, shared-mime-info
Description: $description
CONTROL
    cp tools/linux/update-file-associations.sh "$stage/root/DEBIAN/postinst"
    cp tools/linux/update-file-associations.sh "$stage/root/DEBIAN/postrm"
    chmod 755 "$stage/root/DEBIAN/postinst" "$stage/root/DEBIAN/postrm"
    dpkg-deb --root-owner-group --build "$stage/root" "$out/${binary}_${version}_${debarch}.deb"
    ;;
  rpm)
    need rpmbuild
    mkdir -p "$stage/rpm/"{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    tar -C "$stage/root" -czf "$stage/rpm/SOURCES/bundle.tar.gz" .
    cat > "$stage/rpm/SPECS/visor-markdown.spec" <<SPEC
Name: $binary
Version: $native_version
Release: 1
Summary: $description
License: $license
URL: $repo
Source0: bundle.tar.gz
Requires: gtk3, libstdc++, libsecret, desktop-file-utils, shared-mime-info
AutoReqProv: yes
%description
$description
%prep
%build
%install
mkdir -p %{buildroot}
tar -xzf %{SOURCE0} -C %{buildroot}
%post
update-mime-database /usr/share/mime || :
update-desktop-database -q /usr/share/applications || :
%postun
update-mime-database /usr/share/mime || :
update-desktop-database -q /usr/share/applications || :
%files
/opt/$binary
/usr/bin/$binary
/usr/share/applications/$appid.desktop
/usr/share/icons/hicolor/scalable/apps/$appid.svg
/usr/share/licenses/$binary
/usr/share/mime/packages/$appid.xml
SPEC
    rpmbuild --define "_topdir $stage/rpm" --define "_tmppath $stage" -bb "$stage/rpm/SPECS/visor-markdown.spec"
    find "$stage/rpm/RPMS" -name '*.rpm' -exec cp '{}' "$out/" \;
    ;;
  flatpak)
    need flatpak
    gnome_branch="${FLATPAK_RUNTIME_VERSION:-51}"
    case "$flutterarch" in
      x64) flatpak_arch=x86_64 ;;
      arm64) flatpak_arch=aarch64 ;;
    esac
    platform_ref="org.gnome.Platform/$flatpak_arch/$gnome_branch"
    if ! flatpak info "runtime/$platform_ref" >/dev/null 2>&1; then
        printf 'Flatpak packaging requires the GNOME runtime. Install it with:\n' >&2
        printf '  flatpak install flathub %s\n' "$platform_ref" >&2
        exit 1
    fi

    # Flutter has already built the app. Keep the executable beside data/ and lib/.
    app="$stage/flatpak"
    mkdir -p "$app/files/bin" "$app/files/lib" "$app/files/share"
    cp -a "$stage/root/opt/$binary" "$app/files/lib/"
    cp -a "$stage/root/usr/share/." "$app/files/share/"
    sed -i '/^TryExec=/d' "$app/files/share/applications/$appid.desktop"
    cat > "$app/files/bin/$binary" <<SCRIPT
#!/bin/sh
exec /app/lib/$binary/$binary "\$@"
SCRIPT
    chmod +x "$app/files/bin/$binary"
    printf '[Application]\nname=%s\nruntime=%s\n' "$appid" "$platform_ref" > "$app/metadata"
    flatpak build-finish --command="$binary" --share=ipc --share=network \
        --socket=fallback-x11 --socket=wayland --device=dri --filesystem=home:rw "$app"
    flatpak build-export --arch="$flatpak_arch" "$stage/repository" "$app" stable
    artifact="$appid-$version.flatpak"
    flatpak build-bundle --arch="$flatpak_arch" \
        --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
        "$stage/repository" "$stage/$artifact" "$appid" stable
    mv "$stage/$artifact" "$out/$artifact"
    ;;
  appimage)
    appimagetool="${APPIMAGETOOL:-appimagetool}"
    need "$appimagetool"
    appimage_arch="$(uname -m)"
    app="$stage/$binary.AppDir"
    mkdir -p "$app/usr/lib"
    cp -a "$stage/root/opt/$binary" "$app/usr/lib/"
    cp -a "$stage/root/usr/share" "$app/usr/"
    desktop="$app/usr/share/applications/$appid.desktop"
    sed -i '/^TryExec=/d' "$desktop"
    printf 'X-AppImage-Version=%s\nX-AppImage-Arch=%s\n' "$version" "$appimage_arch" >> "$desktop"
    ln -s "usr/share/applications/$appid.desktop" "$app/$appid.desktop"
    ln -s "usr/share/icons/hicolor/scalable/apps/$appid.svg" "$app/$appid.svg"
    cp assets/visor-markdown.png "$app/.DirIcon"
    cat > "$app/AppRun" <<SCRIPT
#!/bin/sh
appdir=\$(dirname -- "\$0")
exec "\$appdir/usr/lib/$binary/$binary" "\$@"
SCRIPT
    chmod 755 "$app/AppRun"
    artifact="${binary}-${version}-${appimage_arch}.AppImage"
    appimage_options=(--no-appstream)
    if [[ -n "${APPIMAGE_RUNTIME:-}" ]]; then
      appimage_options+=(--runtime-file "$APPIMAGE_RUNTIME")
    fi
    ARCH="$appimage_arch" APPIMAGE_EXTRACT_AND_RUN=1 \
        "$appimagetool" "${appimage_options[@]}" "$app" "$stage/$artifact"
    chmod +x "$stage/$artifact"
    mv "$stage/$artifact" "$out/$artifact"
    ;;
  snap)
    need snapcraft
    snap_grade=stable
    if [[ "$version" != "$native_version" ]]; then snap_grade=devel; fi
    mkdir -p "$stage/snap/snap/gui" "$stage/snap/bundle"
    cp -a "$bundle/." "$stage/snap/bundle/"
    cp LICENSE "$stage/snap/bundle/LICENSE"
    cp assets/visor-markdown.png "$stage/snap/snap/gui/$binary.png"
    sed -e "s|Icon=$appid|Icon=\${SNAP}/meta/gui/$binary.png|" -e '/^TryExec=/d'  "$stage/root/usr/share/applications/$appid.desktop" > "$stage/snap/snap/gui/$binary.desktop"
    snap_title="$(printf '%s' "$name" | sed "s/'/''/g")"
    snap_description="$(printf '%s' "$description" | sed "s/'/''/g")"
    cat > "$stage/snap/snap/snapcraft.yaml" <<SNAP
name: $binary
title: '$snap_title'
version: '$version'
icon: snap/gui/$binary.png
summary: '$snap_description'
description: '$snap_description'
base: core24
confinement: strict
grade: $snap_grade
license: $license
platforms:
  $snaparch:
apps:
  $binary:
    command: $binary
    common-id: $appid
    extensions: [gnome]
    plugs: [home, network, removable-media]
    slots: [dbus-service]
slots:
  dbus-service:
    interface: dbus
    bus: session
    name: $appid
parts:
  application:
    plugin: dump
    source: bundle
SNAP
    cp "$stage/snap/snap/snapcraft.yaml" "$out/snapcraft.yaml"
    # The managed build can write to the project mounted in its container.
    snap_file="${binary}_${version}_${snaparch}.snap"
    (cd "$stage/snap" && snapcraft pack --output "$snap_file")
    mv "$stage/snap/$snap_file" "$out/$snap_file"
    ;;
esac
printf 'Package output: %s\n' "$out"
