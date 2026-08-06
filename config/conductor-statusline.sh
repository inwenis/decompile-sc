#!/bin/bash
# Project statusline wrapper (task: context% in the UI pill, user go 2026-07-14;
# session-scoped writes + live effort/model, task 080).
# 1. Tees the Claude Code status payload's live truth -- context usage,
#    effort level, model display name -- into
#    work/messages/conductor/status.json, but ONLY for the REGISTERED
#    conductor session (task 080 diagnosis b: a 45s watch caught contextPct
#    flapping 14 -> 5 -> 14 -- leftover /resume sessions in the main
#    checkout run this same tee and were overwriting the real conductor's
#    ~14% with their own idle ~5%). Session identity comes from
#    work/scratch/conductor-session-id, kept current by
#    conductor-sessionstart.ps1 (register at start) and
#    conductor-status-heartbeat.ps1 (re-assert every tool call). No
#    registration file yet (fresh checkout, or before the conductor's next
#    session start) -> fall back to the original cwd-only rule.
# 2. Also tees effort + model (task 080 diagnosis a): status.json's
#    effort/model fields were only ever written by set-conductor-status.ps1
#    -Effort/-Model, hand-passed once and then stale for days ("max" shown
#    while the session ran xhigh). The statusline payload carries live
#    truth on every render -- .effort.level (e.g. "xhigh") and
#    .model.display_name (e.g. "Fable 5") -- so the tee writes those
#    instead. Note: "ultracode" runs show as plain "xhigh" -- it is xhigh +
#    workflow orchestration with no separate payload marker, so the raw
#    level is already the honest display; no special-casing needed.
# 3. Delegates display to the user's global combined statusline unchanged.

set -o pipefail

input=$(cat)

repo_root="C:/git/decompile-sc"
status_file="${CONDUCTOR_STATUS_FILE:-$repo_root/work/messages/conductor/status.json}"
session_file="${CONDUCTOR_SESSION_FILE:-$repo_root/work/scratch/conductor-session-id}"

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
# Normalize to forward slashes, case-insensitive drive compare.
cwd_norm=$(printf '%s' "$cwd" | tr '\\' '/' | tr '[:upper:]' '[:lower:]')
root_norm=$(printf '%s' "$repo_root" | tr '[:upper:]' '[:lower:]')

# Session gate: no registration file yet -> today's cwd-only rule (fresh
# checkout bootstrap). Registration file present -> this payload's
# session_id must match it exactly, else stay silent (a leftover session,
# not the conductor).
session_ok=1
if [[ -f "$session_file" ]]; then
    session_ok=0
    payload_sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
    registered_sid=$(cat "$session_file" 2>/dev/null)
    [[ -n "$payload_sid" && "$payload_sid" == "$registered_sid" ]] && session_ok=1
fi

if [[ "$cwd_norm" == "$root_norm" && -f "$status_file" && "$session_ok" == "1" ]]; then
    # current_usage arrives as an OBJECT of token counters in real payloads
    # (input/cache_read/cache_creation/output tokens) — sum its numbers; a
    # plain number (older shape / tests) passes through unchanged. This was
    # the silent-jq-error that kept contextPct out of the pill (2026-07-18).
    pct=$(printf '%s' "$input" | jq -r '
        (.context_window.current_usage // empty) as $cur
        | (if ($cur | type) == "object" then ([$cur[] | numbers] | add) else $cur end) as $curN
        | (.context_window.context_window_size // 200000) as $max
        | if $curN == null or $max == 0 then empty
          else (($curN / $max * 100) | floor)
          end' 2>/dev/null)
    effort=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
    model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

    if [[ -n "$pct$effort$model" ]]; then
        tmp="$status_file.tmp.$$"
        if jq --arg p "$pct" --arg e "$effort" --arg m "$model" '
            (if $p == "" then . else . + {contextPct: ($p | tonumber)} end)
            | (if $e == "" then . else . + {effort: $e} end)
            | (if $m == "" then . else . + {model: $m} end)
        ' "$status_file" > "$tmp" 2>/dev/null; then
            mv -f "$tmp" "$status_file"
        else
            rm -f "$tmp"
        fi
    fi
fi

# Display: unchanged global statusline.
printf '%s' "$input" | bash "$HOME/.claude/scripts/statusline-combined.sh"
