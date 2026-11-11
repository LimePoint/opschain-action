#!/usr/bin/env bash
# Install a pinned OpsChain release into a directory: download the archive
# for this host's platform and the release's SHA256SUMS.txt, verify the
# digest, unpack the one binary. Idempotent: an installed binary reporting
# the requested version is kept.
#
#   install.sh <version> <dest-dir>
set -euo pipefail

version="${1:?version (e.g. v5.6.1)}"
dest="${2:?destination directory}"
case "${version}" in
  v*) ;;
  *) version="v${version}" ;;
esac

if [ -x "${dest}/opschain" ] && "${dest}/opschain" version 2>/dev/null | grep -q "opschain version ${version#v} "; then
  echo "opschain ${version} already installed in ${dest}"
  exit 0
fi

os="$(uname -s)"
case "${os}" in
  Linux) platform_os=linux ;;
  Darwin) platform_os=darwin ;;
  *) echo "::error::OpsChain's local lane runs on Linux and macOS runners; ${os} is not supported by this action" >&2; exit 2 ;;
esac
arch="$(uname -m)"
case "${arch}" in
  x86_64|amd64) platform_arch=amd64 ;;
  aarch64|arm64) platform_arch=arm64 ;;
  *) echo "::error::unsupported architecture ${arch}" >&2; exit 2 ;;
esac

archive="opschain-${version}-${platform_os}-${platform_arch}.tar.gz"
base="https://github.com/LimePoint/opschain-releases/releases/download/${version}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Releases are invitation-only while OpsChain is gated: with
# OPSCHAIN_RELEASES_TOKEN set (a GitHub token LimePoint issues with read
# access to the releases repository) the assets are fetched through the
# GitHub API; without it the public download URL is tried.
api="https://api.github.com/repos/LimePoint/opschain-releases"
fetch() {
  name="$1"; out="$2"
  if [ -n "${OPSCHAIN_RELEASES_TOKEN:-}" ]; then
    asset_id="$(curl -fsSL --retry 3 -H "Authorization: Bearer ${OPSCHAIN_RELEASES_TOKEN}" -H "Accept: application/vnd.github+json" \
      "${api}/releases/tags/${version}" | jq -r --arg n "${name}" '.assets[] | select(.name == $n) | .id')"
    if [ -z "${asset_id}" ]; then
      echo "::error::release ${version} has no asset ${name} (or the token cannot read LimePoint/opschain-releases)" >&2
      exit 1
    fi
    echo "downloading ${name} from release ${version} (gated)"
    curl -fsSL --retry 3 -H "Authorization: Bearer ${OPSCHAIN_RELEASES_TOKEN}" -H "Accept: application/octet-stream" \
      -o "${out}" "${api}/releases/assets/${asset_id}"
  else
    echo "downloading ${base}/${name}"
    if ! curl -fsSL --retry 3 -o "${out}" "${base}/${name}"; then
      echo "::error::could not download ${name}: OpsChain releases are invitation-only — set download-token (OPSCHAIN_RELEASES_TOKEN) to the token LimePoint issued you" >&2
      exit 1
    fi
  fi
}
fetch "${archive}" "${work}/${archive}"
fetch "SHA256SUMS.txt" "${work}/SHA256SUMS.txt"

if ! grep -q " ${archive}\$" "${work}/SHA256SUMS.txt"; then
  echo "::error::${archive} is not listed in the release's SHA256SUMS.txt" >&2
  exit 1
fi
(
  cd "${work}"
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum --ignore-missing -c SHA256SUMS.txt
  else
    shasum -a 256 --ignore-missing -c SHA256SUMS.txt
  fi
)

mkdir -p "${dest}"
tar -xzf "${work}/${archive}" -C "${work}" opschain
install -m 0755 "${work}/opschain" "${dest}/opschain"
"${dest}/opschain" version
