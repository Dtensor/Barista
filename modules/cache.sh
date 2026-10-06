# =============================================================================
# Cache Module - How long the prompt cache stays warm
# =============================================================================
# Stolen from hamzafer/claude-code-mods token-weather (MIT, idea only).
# Reads the last assistant entry in the session transcript: its timestamp is
# when the cache was last touched, and its usage.cache_creation says which
# lifetime it wrote with (ephemeral_1h -> 60 min, ephemeral_5m -> 5 min).
# A pure cache hit writes nothing, so it keeps the last lifetime it saw.
# The status line only redraws on session events, so the number is "as of the
# last redraw", not a ticking clock.
# Configuration options:
#   CACHE_ICON  - Icon before the countdown (default: ❄)
#   CACHE_TTL   - auto | 5m | 1h  (default: auto)
# =============================================================================

module_cache() {
    local input="$2"
    local tpath
    tpath=$(echo "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -n "$tpath" ] && [ -f "$tpath" ] || return 0

    # Last assistant entry: epoch seconds + detected TTL ("1h", "5m" or "").
    local row
    row=$(tail -c 400000 "$tpath" 2>/dev/null | grep '"type":"assistant"' | tail -1 | jq -r '
        [ (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdate),
          (.message.usage.cache_creation // {} |
            if (.ephemeral_1h_input_tokens // 0) > 0 then "1h"
            elif (.ephemeral_5m_input_tokens // 0) > 0 then "5m"
            else "" end)
        ] | @tsv' 2>/dev/null)
    [ -n "$row" ] || return 0

    local since detected
    since=$(printf '%s' "$row" | cut -f1)
    detected=$(printf '%s' "$row" | cut -f2)

    # Remember the last detected lifetime per transcript, for pure cache hits.
    local memo_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/barista-cache-ttl"
    local memo="$memo_dir/$(basename "$tpath" .jsonl)"
    if [ -n "$detected" ]; then
        mkdir -p "$memo_dir" 2>/dev/null
        printf '%s' "$detected" > "$memo" 2>/dev/null
    elif [ -f "$memo" ]; then
        detected=$(cat "$memo" 2>/dev/null)
    fi

    local ttl="${CACHE_TTL:-auto}"
    [ "$ttl" = "auto" ] && ttl="${detected:-5m}"
    local ttl_s=300
    [ "$ttl" = "1h" ] && ttl_s=3600

    local left=$(( since + ttl_s - $(date +%s) ))
    local icon
    icon=$(get_icon "${CACHE_ICON:-❄}" "C:")

    if [ "$left" -le 0 ]; then
        echo "$icon cold"
    elif [ "$left" -lt 60 ]; then
        echo "$icon ${left}s!"
    else
        printf '%s %d:%02d/%s\n' "$icon" $((left / 60)) $((left % 60)) "$ttl"
    fi
}
