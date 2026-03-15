#!/bin/bash
# =============================================================================
# make-release.sh — Build a ubuntu-hardening release tarball
#
# Usage:
#   ./make-release.sh [--version VERSION]
#
# Output:
#   dist/ubuntu-hardening-v{VERSION}.tar.gz
#   dist/ubuntu-hardening-v{VERSION}.sha256
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(grep '^# Version ' "${SCRIPT_DIR}/install_hardening.sh" | head -1 | sed 's/^# Version //')"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

RELEASE_NAME="ubuntu-hardening-v${VERSION}"
DIST_DIR="${SCRIPT_DIR}/dist"
TARBALL="${DIST_DIR}/${RELEASE_NAME}.tar.gz"
CHECKSUM="${DIST_DIR}/${RELEASE_NAME}.sha256"

echo "=== ubuntu-hardening Release Builder ==="
echo "  Version: ${VERSION}"
echo "  Output:  ${TARBALL}"
echo ""

mkdir -p "${DIST_DIR}"

tar -czf "${TARBALL}" \
    --transform "s|^|${RELEASE_NAME}/|" \
    --exclude-vcs \
    -C "${SCRIPT_DIR}" \
    install_hardening.sh \
    README.md \
    LICENSE.md

TARBALL_SIZE=$(du -sh "${TARBALL}" | cut -f1)
echo "Created: ${TARBALL} (${TARBALL_SIZE})"

if command -v sha256sum &>/dev/null; then
    (cd "${DIST_DIR}" && sha256sum "$(basename "${TARBALL}")") > "${CHECKSUM}"
elif command -v shasum &>/dev/null; then
    (cd "${DIST_DIR}" && shasum -a 256 "$(basename "${TARBALL}")") > "${CHECKSUM}"
else
    echo "WARNING: sha256sum/shasum not found, skipping checksum"
fi
echo "Checksum: ${CHECKSUM}"

echo ""
echo "=== Release Complete ==="
