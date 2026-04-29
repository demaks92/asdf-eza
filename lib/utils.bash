#!/usr/bin/env bash

set -euo pipefail

declare -r GH_REPO='https://github.com/eza-community/eza'
declare -r GH_REPO_CBIN='https://github.com/cargo-bins/cargo-quickinstall'
declare -r TOOL_NAME='eza'
declare -r TOOL_TEST='eza --version'
declare -r MINIMAL_GLIBC_VER='2.18'

fail() {
  printf 'asdf-%s: %s\n' "$TOOL_NAME" "$*"
  exit 1
}

declare -a curl_opts=(-fsSL --proto '=https' --tlsv1.2 --retry 3 --retry-delay 2)

if [[ -n "${GITHUB_API_TOKEN:-}" ]]; then
  curl_opts=("${curl_opts[@]}" -H "Authorization: token $GITHUB_API_TOKEN")
fi

verify_sha256() {
  local -r file="$1"
  local -r expected="${ASDF_EZA_SHA256:-}"

  if [[ -z "$expected" ]]; then
    printf '* Skipping SHA256 verification (set ASDF_EZA_SHA256 to enable)\n'
    return
  fi

  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    fail "Neither sha256sum nor shasum is available for SHA256 verification"
  fi

  if [[ "$actual" != "$expected" ]]; then
    fail "SHA256 mismatch for $file: expected $expected, got $actual"
  fi

  printf '* SHA256 verified\n'
}
