#!/usr/bin/env bash
# cl: Claude Code profile manager. Profiles: ~/.claude (main) and ~/.claude-<name>.
# Bash 3.2 compatible (macOS). Needs jq, curl, claude.
set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cl"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/cl/config"
TTL=60
OS=$(uname)
FORCE=
RESERVED=" main ls auto new sync rm swap bypass help "

die() { echo "cl: $*" >&2; exit 1; }
command -v jq >/dev/null || die "jq missing (mac: brew install jq)"

usage() {
  cat <<'EOF'
cl                  menu
cl <name> [args]    open profile (main = ~/.claude), args go to claude
cl auto [args]      open the profile with most room left
cl ls [-r]          usage table (-r: skip 60 s cache)
cl new <name>       create ~/.claude-<name>, then open it to log in
cl sync [-n]        link missing shared files into every profile (-n: dry run)
cl rm <name>        move a profile to the trash
cl swap <a> <b>     exchange the logins of two profiles (Linux)
cl bypass [on|off]  show or set: launch claude with --dangerously-skip-permissions
EOF
}

valid() { [[ $1 == main || $1 =~ ^[a-z0-9_-]+$ ]] || die "bad profile name '$1'"; }

dir_of() { if [[ $1 == main ]]; then echo "$HOME/.claude"; else echo "$HOME/.claude-$1"; fi; }

profiles() {
  local d
  [[ -d $HOME/.claude ]] && echo main
  for d in "$HOME"/.claude-*; do
    # Only Claude Code config folders; other tools also use ~/.claude-* names.
    [[ -d $d && ! -L $d ]] || continue
    [[ -e $d/.claude.json || -e $d/.credentials.json || -e $d/.cl-profile ]] && echo "${d##*/.claude-}"
  done
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

# Prints the credentials JSON of profile $1.
creds() {
  local d svc="Claude Code-credentials"
  d=$(dir_of "$1")
  [[ -f $d/.credentials.json ]] && { cat "$d/.credentials.json"; return; }
  [[ $OS == Darwin ]] || return 1
  [[ $1 == main ]] && { security find-generic-password -s "$svc" -w 2>/dev/null; return; }
  # shortcut: keychain name for a custom CLAUDE_CONFIG_DIR is unverified; fix here if `cl ls` shows "no login" on a logged-in mac profile.
  security find-generic-password -s "$svc-$(printf '%s' "$d" | shasum -a 256 | cut -c1-8)" -w 2>/dev/null
}

# Refreshes the cached usage JSON of profile $1 when older than TTL.
fetch() {
  local f="$CACHE/$1.json" c tok exp code
  [[ -z $FORCE && -f $f ]] && (($(date +%s) - $(mtime "$f") < TTL)) && return
  c=$(creds "$1") || { echo '{"cl":"no login"}' >"$f"; return; }
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$c")
  exp=$(jq -r '.claudeAiOauth.expiresAt // 0' <<<"$c")
  [[ -n $tok ]] || { echo '{"cl":"no login"}' >"$f"; return; }
  if ((exp / 1000 < $(date +%s))); then
    # `claude auth status` renews an expired token and saves it; no model call.
    if [[ $1 == main ]]; then env -u CLAUDE_CONFIG_DIR claude auth status; else CLAUDE_CONFIG_DIR=$(dir_of "$1") claude auth status; fi >/dev/null 2>&1
    c=$(creds "$1") && tok=$(jq -r '.claudeAiOauth.accessToken // empty' <<<"$c") && exp=$(jq -r '.claudeAiOauth.expiresAt // 0' <<<"$c")
    ((exp / 1000 < $(date +%s))) && { echo '{"cl":"expired, open once"}' >"$f"; return; }
  fi
  # Token goes through stdin config so it never shows in `ps`.
  code=$(curl -s --max-time 15 -o "$f.tmp" -w '%{http_code}' -K - https://api.anthropic.com/api/oauth/usage <<EOF
header = "Authorization: Bearer $tok"
header = "anthropic-beta: oauth-2025-04-20"
EOF
  )
  if [[ $code == 200 ]]; then
    mv "$f.tmp" "$f"
  else
    rm -f "$f.tmp"
    # Keep the last good numbers; the unchanged mtime makes the next run retry.
    jq -e .five_hour "$f" >/dev/null 2>&1 || echo "{\"cl\":\"fetch failed (HTTP ${code:-none})\"}" >"$f"
  fi
}

# Sets err five week r5 rw ws fs for profile $1 from cache ("-" = none; r5/rw = time to reset, ws/fs = seconds to weekly/5-hour reset).
usage_of() {
  IFS='|' read -r err five week r5 rw ws fs < <(jq -r 'def secs: (.resets_at // "")[:19]
      | if . == "" then "-" else ((. + "Z" | fromdateiso8601) - now | floor) end;
    def left: secs | if . == "-" then . else (
      if . < 60 then "now" elif . < 3600 then "\(./60|floor)m" elif . < 86400 then "\(./3600|floor)h \(./60%60|floor)m"
        else "\(./86400|floor)d \(./3600%24|floor)h" end) end;
    def pct: .utilization | if type == "number" then floor else "-" end;
    [(.cl // "-"), (.five_hour | pct), (.seven_day | pct), (.five_hour | left), (.seven_day | left), (.seven_day | secs), (.five_hour | secs)]
    | map(tostring) | join("|")' "$CACHE/$1.json" 2>/dev/null || echo "bad cache|-|-|-|-|-|-")
}

B=$'\e[1m' D=$'\e[2m' R=$'\e[0m' RED=$'\e[31m' GRN=$'\e[32m' YEL=$'\e[33m' CYN=$'\e[36m' TRK=$'\e[38;5;238m' SEL=$'\e[48;5;236m'

# 12-cell bar plus percent, colored by level.
bar() {
  local n=$1 i f c=$GRN s=""
  ((n >= 70)) && c=$YEL
  ((n >= 90)) && c=$RED
  f=$(((n * 12 + 50) / 100))
  for ((i = 0; i < 12; i++)); do ((i == f)) && s+=$TRK; s+="━"; done
  printf '%s%s%s %s%3d%%%s' "$c" "$s" "$R" "$c" "$n" "$R"
}

fetch_all() {
  local p
  mkdir -p "$CACHE" && chmod 700 "$CACHE"
  for p in $(profiles); do fetch "$p" & done
  wait
}

# Prints the profile whose weekly usage would go to waste fastest, or nothing:
# highest (weekly % left) / (hours to weekly reset), among those with >= 5% weekly left.
# The 5-hour window only gates: skip when it is at 80% or more and resets in over 30 minutes.
pick_best() {
  local p pick="" score top=-1
  for p in $(profiles); do
    usage_of "$p"
    [[ $err == - && $five != - && $week != - && $ws != - ]] || continue
    ((100 - week < 5)) && continue
    [[ $fs != - ]] && ((five >= 80 && fs > 1800)) && continue
    ((ws < 60)) && ws=60
    # Integer math: % per hour x 100.
    score=$(((100 - week) * 360000 / ws))
    ((score > top)) && pick=$p top=$score
  done
  echo "$pick"
}

table() {
  local p e top
  fetch_all
  top=$(pick_best)
  printf '%s  %-6s %-28s %-27s %-27s%s\n' "$D" name account '5-hour' 'weekly' "$R"
  for p in $(profiles); do
    e=$(jq -r '.oauthAccount.emailAddress // "(no login)"' "$(cfg_of "$p")" 2>/dev/null || echo "(no login)")
    ((${#e} > 28)) && e="${e:0:26}.."
    printf '  %s%-6s%s %s%-28s%s ' "$CYN" "$p" "$R" "$B" "$e" "$R"
    usage_of "$p"
    if [[ $err != - || $five == - || $week == - ]]; then
      [[ $err == - ]] && err="no data"
      [[ $err == "no login" ]] && err=
      printf '%s%s%s\n' "$D" "$err" "$R"
      continue
    fi
    printf '%s %s%-8s%s  %s %s%-8s%s' "$(bar "$five")" "$D" "$r5" "$R" "$(bar "$week")" "$D" "$rw" "$R"
    if ((five >= 100 || week >= 100)); then
      printf '  %s● full%s' "$RED" "$R"
    elif [[ $p == "$top" ]]; then
      printf '  %s★ best%s' "$GRN" "$R"
    fi
    echo
  done
}

best() {
  local pick
  fetch_all
  pick=$(pick_best)
  [[ -n $pick ]] || die "no profile with room left"
  echo "$pick"
}

cfg_of() { if [[ $1 == main ]]; then echo "$HOME/.claude.json"; else echo "$(dir_of "$1")/.claude.json"; fi; }

# Prints "<profile> <pid>" for every running claude session.
running() {
  local pid line d
  for pid in $(pgrep -x claude); do
    line=$(ps eww -o command= -p "$pid" 2>/dev/null) || continue
    [[ $line == *--chrome-native-host* ]] && continue
    d=$(sed -n 's/.*CLAUDE_CONFIG_DIR=\([^ ]*\).*/\1/p' <<<"$line")
    d=${d%/}
    if [[ -z $d || $d == "$HOME/.claude" ]]; then d=main; else d=${d##*/.claude-}; fi
    echo "$d $pid"
  done
}

cwd_of() { readlink "/proc/$1/cwd" 2>/dev/null || lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; }

# Exchanges files $1 and $2; either may be missing.
xchg() {
  [[ -e $1 ]] && mv "$1" "$1.cl-swap"
  [[ -e $2 ]] && mv "$2" "$1"
  [[ -e $1.cl-swap ]] && mv "$1.cl-swap" "$2"
  return 0
}

swap() {
  local a=${1:-} b=${2:-} p busy ans ts t f
  # Account-tied keys in .claude.json; everything else (projects, settings) stays put.
  local acct='def acct: .key == "oauthAccount" or (.key | test("^cached|Cache$|^passes"));'
  [[ -n $a && -n $b && $a != "$b" ]] || die "usage: cl swap <a> <b>"
  valid "$a"
  valid "$b"
  for p in "$a" "$b"; do
    profiles | grep -Fxq "$p" || die "no profile '$p' (see: cl ls)"
  done
  [[ $OS == Darwin ]] && die "swap: macOS keeps logins in the Keychain; not supported yet"
  for p in "$a" "$b"; do
    [[ -f $(dir_of "$p")/.credentials.json ]] || die "'$p' has no login"
    [[ -f $(cfg_of "$p") ]] || die "'$p' has no $(cfg_of "$p")"
  done
  busy=$(running | awk -v a="$a" -v b="$b" '$1 == a || $1 == b')
  if [[ -n $busy ]]; then
    printf '%s! Open claude sessions on these profiles:%s\n' "$YEL" "$R"
    printf '  %-8s %-8s %-11s %s\n' profile pid uptime folder
    while read -r p f; do
      printf '  %-8s %-8s %-11s %s\n' "$p" "$f" "$(ps -o etime= -p "$f" | tr -d ' ')" "$(cwd_of "$f" | sed "s|^$HOME|~|")"
    done <<<"$busy"
    # A running session saves its own login when its token renews, which can undo or mix the swap.
    printf '%sThese keep their old account until restarted, and may write it back when their token renews.%s\n' "$YEL" "$R"
  fi
  read -rp "Swap logins of '$a' and '$b'? [y/N] " ans
  [[ $ans == [yY] ]] || die "cancelled"
  ts=$(date +%s)
  t=$(mktemp -d) || die "mktemp failed"
  for f in "$(dir_of "$a")/.credentials.json" "$(dir_of "$b")/.credentials.json" "$(cfg_of "$a")" "$(cfg_of "$b")"; do
    cp -p "$f" "$f.bak-cl-$ts" || die "backup failed: $f"
  done
  jq "$acct [to_entries[] | select(acct)] | from_entries" "$(cfg_of "$a")" >"$t/a" &&
    jq "$acct [to_entries[] | select(acct)] | from_entries" "$(cfg_of "$b")" >"$t/b" &&
    jq --slurpfile o "$t/b" "$acct with_entries(select(acct | not)) + \$o[0]" "$(cfg_of "$a")" >"$t/a.json" &&
    jq --slurpfile o "$t/a" "$acct with_entries(select(acct | not)) + \$o[0]" "$(cfg_of "$b")" >"$t/b.json" ||
    { rm -rf "$t"; die "reading .claude.json failed; nothing changed"; }
  # cat > keeps each file's mode and any symlink.
  cat "$t/a.json" >"$(cfg_of "$a")" && cat "$t/b.json" >"$(cfg_of "$b")" ||
    { rm -rf "$t"; die "writing .claude.json failed; logins not swapped; restore from *.bak-cl-$ts"; }
  rm -rf "$t"
  for f in .credentials.json policy-limits.json policy-limits.json.signature.json policy-limits.json.stamp.json \
    remote-settings.json remote-settings.json.synced-at; do
    xchg "$(dir_of "$a")/$f" "$(dir_of "$b")/$f"
  done
  rm -f "$CACHE/$a.json" "$CACHE/$b.json"
  for p in "$a" "$b"; do
    echo "$p: $(jq -r '.oauthAccount.emailAddress // "?"' "$(cfg_of "$p")")"
  done
  echo "backups: *.bak-cl-$ts; undo: cl swap $a $b"
}

# Per-account state each profile keeps for itself; everything else links to ~/.claude.
own() {
  case "$1" in
    .credentials.json* | .claude.json* | policy-limits.json* | remote-settings.json* | \
      stats-cache.json | backups | cache | chrome) return 0 ;;
  esac
  return 1
}

# Links every ~/.claude entry missing from profile dir $1. Never replaces an existing entry.
mirror() {
  local src="$HOME/.claude" dst=$1 path name
  for path in "$src"/* "$src"/.[!.]*; do
    [[ -e $path || -L $path ]] || continue
    name=${path##*/}
    own "$name" && continue
    [[ -e $dst/$name || -L $dst/$name ]] && continue
    echo "  link $name"
    [[ -n ${DRY:-} ]] || ln -s "$path" "$dst/$name" || return 1
  done
}

sync_all() {
  local p
  for p in $(profiles); do
    [[ $p == main ]] && continue
    echo "== $(dir_of "$p")"
    mirror "$(dir_of "$p")"
  done
}

bypass_on() { grep -qx 'bypass=on' "$CONF" 2>/dev/null; }

bypass() {
  case ${1:-} in
    on | off)
      mkdir -p "${CONF%/*}"
      { grep -v '^bypass=' "$CONF" 2>/dev/null; echo "bypass=$1"; } >"$CONF.tmp" && mv "$CONF.tmp" "$CONF" || die "writing $CONF failed"
      ;;
    '') ;;
    *) die "usage: cl bypass [on|off]" ;;
  esac
  if bypass_on; then echo "bypass: on"; else echo "bypass: off"; fi
}

launch() {
  local p=$1 d
  shift
  valid "$p"
  d=$(dir_of "$p")
  [[ -d $d ]] || die "no profile '$p' (see: cl ls)"
  if bypass_on; then
    local a flag=--dangerously-skip-permissions
    for a in "$@"; do [[ $a == "$flag" ]] && flag=; done
    [[ -n $flag ]] && set -- "$flag" "$@"
  fi
  if [[ $p == main ]]; then
    unset CLAUDE_CONFIG_DIR
    [[ -t 1 ]] && printf '\e[?25h'
    exec claude "$@"
  fi
  mirror "$d" >/dev/null || die "linking shared files into $d failed"
  [[ -t 1 ]] && printf '\e[?25h'
  CLAUDE_CONFIG_DIR=$d exec claude "$@"
}

new() {
  local p=${1:-} d
  [[ $p =~ ^[a-z0-9_-]+$ ]] || die "name: lowercase letters, digits, - or _"
  [[ $RESERVED == *" $p "* ]] && die "'$p' is reserved"
  d=$(dir_of "$p")
  [[ -e $d ]] && die "$d exists"
  mkdir -p "$d" && touch "$d/.cl-profile"
  echo "created $d; log in with /login"
  shift
  launch "$p" "$@"
}

remove() {
  local p=${1:-} d ans trash dest
  [[ -n $p && $p != main ]] || die "usage: cl rm <name> (main can't be removed)"
  valid "$p"
  d=$(dir_of "$p")
  [[ -d $d ]] || die "no profile '$p'"
  read -rp "Type '$p' to move $d to the trash: " ans
  [[ $ans == "$p" ]] || die "cancelled"
  if [[ $OS == Darwin ]]; then
    trash="$HOME/.Trash"
  else
    trash="$HOME/.local/share/Trash/files"
    mkdir -p "$HOME/.local/share/Trash/info"
  fi
  mkdir -p "$trash"
  dest=".claude-$p.$(date +%s)"
  mv "$d" "$trash/$dest" || die "move failed"
  [[ $OS == Darwin ]] || printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$d" "$(date +%Y-%m-%dT%H:%M:%S)" \
    >"$HOME/.local/share/Trash/info/$dest.trashinfo"
  rm -f "$CACHE/$p.json"
  echo "moved to $trash/$dest"
}

k() { printf '%s%s%s %s%s%s   ' "$B" "$1" "$R" "$D" "$2" "$R"; }

pause() { read -rsn1 -p " press a key"; }

menu() {
  local key rest n p ps l i sel=0 redo=1 lines=()
  # Hidden cursor while browsing; shown again on exit, launch and text prompts.
  printf '\e[?25l'
  trap 'printf "\e[?25h"' EXIT
  trap 'exit 130' INT TERM
  while :; do
    if ((redo)); then
      lines=()
      while IFS= read -r l; do lines+=("$l"); done < <(table)
      FORCE= redo=0
      ps=($(profiles))
      ((sel >= ${#ps[@]})) && sel=$((${#ps[@]} - 1))
    fi
    clear
    printf '\n %s◆ Claude profiles%s  %s%d profiles · %s%s' "$B$CYN" "$R" "$D" "${#ps[@]}" "$(date +%H:%M)" "$R"
    bypass_on && printf '   %s%sbypass on%s' "$B" "$RED" "$R"
    printf '\n\n'
    echo " ${lines[0]}"
    for ((i = 1; i < ${#lines[@]}; i++)); do
      l=${lines[i]}
      if ((i - 1 == sel)); then
        # Re-apply the background after each reset; \e[K fills it to the line end.
        printf '%s%s▌%s%s\e[K%s\n' "$SEL" "$CYN" "$R$SEL" "${l//$R/$R$SEL}" "$R"
      else
        echo " $l"
      fi
    done
    echo
    printf ' '; k '↑↓' move; k '⏎' open; k 1-9 open; k a auto; k b bypass; k n new; k x remove; k w swap; k s sync; k r refresh; k q quit
    read -rsn1 key
    # Arrow keys arrive as ESC [ A; bash 3.2 read -t takes whole seconds only.
    [[ $key == $'\e' ]] && { read -rsn2 -t 1 rest; key+=${rest:-}; }
    echo
    case $key in
      $'\e[A' | $'\eOA' | k) ((sel > 0)) && sel=$((sel - 1)) ;;
      $'\e[B' | $'\eOB' | j) ((sel < ${#ps[@]} - 1)) && sel=$((sel + 1)) ;;
      '') [[ -n ${ps[sel]:-} ]] && launch "${ps[sel]}" ;;
      [1-9])
        p=${ps[key - 1]:-}
        [[ -n $p ]] && launch "$p"
        ;;
      a) p=$(best) && launch "$p" || pause ;;
      b) if bypass_on; then bypass off; else bypass on; fi >/dev/null ;;
      n)
        printf '\e[?25h'
        read -rp " name: " n && (new "$n") || pause
        printf '\e[?25l'
        redo=1
        ;;
      s) sync_all; pause ;;
      w)
        printf '\e[?25h'
        read -rp " swap ${ps[sel]} with (name): " n
        (swap "${ps[sel]}" "$n")
        printf '\e[?25l'
        pause
        redo=1
        ;;
      r) FORCE=1 redo=1 ;;
      x)
        printf '\e[?25h'
        (remove "${ps[sel]:-}")
        printf '\e[?25l'
        pause
        redo=1
        ;;
      q | $'\e') exit 0 ;;
    esac
  done
}

case ${1:-} in
  '') menu ;;
  ls)
    [[ ${2:-} == -r ]] && FORCE=1
    table
    ;;
  auto)
    shift
    p=$(best) || exit 1
    launch "$p" "$@"
    ;;
  new) shift; new "$@" ;;
  sync)
    [[ ${2:-} == -n ]] && DRY=1
    sync_all
    ;;
  rm) remove "${2:-}" ;;
  swap) swap "${2:-}" "${3:-}" ;;
  bypass) bypass "${2:-}" ;;
  -h | --help | help) usage ;;
  *) launch "$@" ;;
esac
