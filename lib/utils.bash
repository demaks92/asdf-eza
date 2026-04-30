#!/usr/bin/env bash

set -euo pipefail

declare -r GH_REPO='https://github.com/eza-community/eza'
declare -r GH_API_REPO='https://api.github.com/repos/eza-community/eza'
declare -r TOOL_NAME='eza'
declare -r TOOL_TEST="${TOOL_NAME} --version"
declare -r MINIMAL_GLIBC_VER='2.18'

fail() {
  printf 'asdf-%s: %s\n' "$TOOL_NAME" "$*" >&2
  exit 1
}

declare -a curl_opts=(-fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2)

if [[ -n "${GITHUB_API_TOKEN:-}" ]]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

# fetch_asset_sha256 <release_tag> <browser_download_url>
# Prints the lowercase hex SHA-256 digest reported by the GitHub Releases API
# for the asset whose browser_download_url matches the requested one.
# Uses jq when available, falling back to python3, then to a pure-awk parser.
fetch_asset_sha256() {
  local -r release_tag="$1"
  local -r asset_url="$2"

  command -v curl >/dev/null 2>&1 || fail 'curl is required to fetch release metadata'

  local payload
  payload="$(
    curl "${curl_opts[@]}" -H 'Accept: application/vnd.github+json' \
      "${GH_API_REPO}/releases/tags/${release_tag}"
  )" || fail "Could not query GitHub API for release ${release_tag}"

  local digest=''
  if command -v jq >/dev/null 2>&1; then
    digest="$(
      printf '%s' "$payload" |
        jq -r --arg url "$asset_url" \
          '.assets[] | select(.browser_download_url == $url) | .digest // empty'
    )"
  elif command -v python3 >/dev/null 2>&1; then
    digest="$(
      ASSET_URL="$asset_url" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
url = os.environ["ASSET_URL"]
for asset in data.get("assets", []):
    if asset.get("browser_download_url") == url:
        print(asset.get("digest") or "")
        break
' <<<"$payload"
    )"
  else
    # Last-resort dependency-free parser: normalize JSON whitespace, split on
    # asset object boundaries, then locate the object whose
    # browser_download_url matches and pull its digest field.
    digest="$(
      printf '%s' "$payload" |
        awk -v url="$asset_url" '
          { doc = doc " " $0 }
          END {
            gsub(/[[:space:]]+/, " ", doc)
            gsub(/" *: */, "\":", doc)
            gsub(/, */, ",", doc)
            gsub(/{ */, "{", doc)
            gsub(/ *}/, "}", doc)
            n = split(doc, parts, /},{/)
            for (i = 1; i <= n; i++) {
              if (index(parts[i], "\"browser_download_url\":\"" url "\"") > 0) {
                if (match(parts[i], /"digest":"[^"]+"/)) {
                  print substr(parts[i], RSTART + 10, RLENGTH - 11)
                  exit
                }
              }
            }
          }
        '
    )"
  fi

  # Older releases (published before GitHub added per-asset digests in
  # February 2025) have no digest field. Warn and return empty so the caller
  # can decide to skip verification.
  if [[ -z "$digest" ]]; then
    printf 'asdf-%s: warning: GitHub API reports no SHA256 digest for %s (release %s); skipping checksum verification\n' \
      "$TOOL_NAME" "${asset_url##*/}" "$release_tag" >&2
    return 0
  fi

  [[ "$digest" == sha256:* ]] ||
    fail "Unexpected digest algorithm for ${asset_url}: ${digest}"

  printf '%s' "${digest#sha256:}"
}

# verify_sha256 <file> <expected_hex>
verify_sha256() {
  local -r file="$1"
  local -r expected="$2"

  [[ -n "$expected" ]] || fail "Empty expected SHA256 for $file"

  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    fail 'Neither sha256sum nor shasum is available for SHA256 verification'
  fi

  if [[ "${actual,,}" != "${expected,,}" ]]; then
    fail "SHA256 mismatch for $file: expected $expected, got $actual"
  fi

  printf '* SHA256 verified (%s)\n' "$actual"
}
