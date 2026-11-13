#!/usr/bin/env bash
# Package a compiled bundle using the packagers available for the host OS.
set -euo pipefail
tools="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
usage() {
  cat <<'USAGE'
Usage: tools/package-all.sh [bundle-directory]

Linux: DEB, RPM, Flatpak, Snap and AppImage from a Linux release bundle.
Windows (Git Bash): EXE installer from a Windows release bundle.
The bundle path is optional and defaults to the platform's Flutter release output.
USAGE
}

if [[ "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 0
fi
if (( $# > 1 )); then
  usage >&2
  exit 2
fi

bundle=()
if (( $# == 1 )); then
  bundle=("$(cd -- "$1" && pwd -P)")
fi

case "$(uname -s)" in
  Linux)
    succeeded=()
    failed=()
    for format in deb rpm flatpak snap appimage; do
      printf '\n== %s ==\n' "$format"
      if "$tools/package.sh" "$format" "${bundle[@]}"; then
        succeeded+=("$format")
      else
        failed+=("$format")
      fi
    done
    printf '\nSucceeded: %s\n' "${succeeded[*]:-none}"
    if (( ${#failed[@]} > 0 )); then
      printf 'Failed: %s\n' "${failed[*]}" >&2
      exit 1
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    windows_bundle=()
    if (( ${#bundle[@]} > 0 )); then
      windows_bundle=(-BundleDir "$(cygpath -w "${bundle[0]}")")
    fi
    exec powershell.exe -NoProfile -File "$(cygpath -w "$tools/package-windows.ps1")" "${windows_bundle[@]}"
    ;;
  *)
    printf 'No packager configured for %s.\n' "$(uname -s)" >&2
    exit 2
    ;;
esac
