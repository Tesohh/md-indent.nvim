#!/usr/bin/env bash
# Runs the tests with the nvim on PATH, or with NVIM_BIN. Needs Nvim 0.10+.
set -eu
nvim="${NVIM_BIN:-nvim}"
cd "$(dirname "$0")/.."
status=0
"$nvim" --headless --noplugins -c "set runtimepath^=$PWD" -c "luafile tests/run.lua" || status=1

# Fold lines show foldtext, so the fold check needs a real terminal rendering.
if command -v script >/dev/null 2>&1; then
  # The screen dump carries ANSI escape sequences, so strip them before matching.
  esc=$(printf '\033')
  plain() { sed -E "s/${esc}[^a-zA-Z]*[a-zA-Z]//g" "$1"; }
  sample="$(mktemp "${TMPDIR:-/tmp}/md-indent.XXXXXX.md")"
  out="$(mktemp)"
  printf '# H\n## Sub\naa\nbb\ncc\n## Sub2\ndd\n' >"$sample"
  cmd="$nvim --cmd \"set rtp^=$PWD\" --cmd \"set shiftwidth=4\" --cmd \"set foldmethod=manual\" $sample -c \"2,5fold\" -c \"redraw\" -c \"q!\""
  timeout_cmd='' # 'timeout' is absent on macOS
  command -v timeout >/dev/null 2>&1 && timeout_cmd='timeout 30'
  $timeout_cmd script -q -c "$cmd" "$out" >/dev/null 2>&1 || true
  # A level 2 heading nests under the level 1 text, so the pad is 2 spaces.
  if plain "$out" | grep -a '  +--  4 lines: ## Sub'; then
    echo 'ok   fold line keeps the heading indent'
  else
    echo 'FAIL fold line lost the heading indent'
    status=1
  fi

  # A foldtext set by another plugin must keep its own fold text.
  cmd="$nvim --cmd \"set rtp^=$PWD\" --cmd \"set shiftwidth=4\" --cmd \"set foldmethod=manual\" $sample -c \"luafile tests/fold-foreign.lua\""
  $timeout_cmd script -q -c "$cmd" "$out" >/dev/null 2>&1 || true
  if grep -a 'ufo' "$out"; then
    echo 'ok   foldtext from another plugin keeps its fold text'
  else
    echo 'FAIL foldtext from another plugin lost its fold text'
    status=1
  fi
  rm -f "$sample" "$out"
fi

exit "$status"
