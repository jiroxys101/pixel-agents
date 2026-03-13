#!/usr/bin/env bash
# Claude Code status line script
# Reads JSON from stdin, caches expensive operations, outputs a rich single-line status.
#
# Claude Max 20x plan limits (weekly):
#   Sonnet hours: 240–480h   (we use 240 as conservative budget)
#   Opus hours:   24–40h     (we use 24 as conservative budget)
#   Messages/5h:  900+       (session rate limit, not tracked weekly)

# ── ANSI colors ──────────────────────────────────────────────────────────────
E=$'\e'
RED="${E}[31m"
GREEN="${E}[32m"
YELLOW="${E}[33m"
BLUE="${E}[34m"
MAGENTA="${E}[35m"
CYAN="${E}[36m"
WHITE="${E}[37m"
BOLD="${E}[1m"
DIM="${E}[2m"
RESET="${E}[0m"

# ── Configuration ────────────────────────────────────────────────────────────
CLAUDE_DIR="${HOME}/.claude"
CACHE_DIR="${CLAUDE_DIR}/statusline-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null
GIT_CACHE="${CACHE_DIR}/git.json"
USAGE_CACHE="${CACHE_DIR}/usage.json"
GIT_CACHE_AGE=30     # refresh git cache every 30 seconds
USAGE_CACHE_AGE=300  # refresh plan usage cache every 5 minutes

# Claude Max 20x weekly budgets (conservative low-end)
SONNET_WEEKLY_HOURS=240
OPUS_WEEKLY_HOURS=24

# ── Read JSON input once ─────────────────────────────────────────────────────
JS=$(cat)

# ── Extract all fields in a single jq call ───────────────────────────────────
eval "$(echo "$JS" | jq -r '
  @sh "MODEL=\(.model.display_name // "Claude")",
  @sh "MODEL_ID=\(.model.id // "")",
  @sh "CWD=\(.workspace.current_dir // .cwd // ".")",
  @sh "AGENT=\(.agent.name // "")",
  @sh "USED_PCT=\(.context_window.used_percentage // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "TOTAL_IN=\(.context_window.total_input_tokens // 0)",
  @sh "TOTAL_OUT=\(.context_window.total_output_tokens // 0)",
  @sh "CUR_IN=\(.context_window.current_usage.input_tokens // 0)",
  @sh "CUR_OUT=\(.context_window.current_usage.output_tokens // 0)",
  @sh "CACHE_CREATE=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "CACHE_READ=\(.context_window.current_usage.cache_read_input_tokens // 0)"
')"

# ── Format helpers ───────────────────────────────────────────────────────────
format_tokens() {
    local t=$1
    if [ "$t" -ge 1000000 ] 2>/dev/null; then
        echo "$(( t / 1000000 )).$(( (t % 1000000) / 100000 ))M"
    elif [ "$t" -ge 1000 ] 2>/dev/null; then
        echo "$(( t / 1000 )).$(( (t % 1000) / 100 ))k"
    else
        echo "$t"
    fi
}

make_bar() {
    local pct=$1 width=$2 bar="" i=0
    local filled=$(( pct * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( width - filled ))
    while [ "$i" -lt "$filled" ]; do bar="${bar}█"; (( i++ )); done
    i=0
    while [ "$i" -lt "$empty" ];  do bar="${bar}░"; (( i++ )); done
    echo "$bar"
}

is_cache_fresh() {
    local cache_file=$1 max_age=$2
    [ ! -f "$cache_file" ] && return 1
    local cached_at now_epoch age
    cached_at=$(jq -r '.cached_at // 0' "$cache_file" 2>/dev/null)
    now_epoch=$(date +%s)
    age=$(( now_epoch - cached_at ))
    [ "$age" -lt "$max_age" ]
}

# ── Model color + emoji ───────────────────────────────────────────────────────
# 🎵 Opus (musical opus) | 🎶 Sonnet (musical/poetic) | 🍃 Haiku (nature)
M_CLR="${BOLD}${WHITE}"; M_EMOJI="🤖"
case "$MODEL_ID" in
    *opus*)   M_CLR="${BOLD}${MAGENTA}"; M_EMOJI="🎵" ;;
    *sonnet*) M_CLR="${BOLD}${CYAN}";    M_EMOJI="🎶" ;;
    *haiku*)  M_CLR="${BOLD}${GREEN}";   M_EMOJI="🍃" ;;
esac

# ── Agent color coding ───────────────────────────────────────────────────────
AGENT_PART=""
if [ -n "$AGENT" ]; then
    A_CLR="${BOLD}${YELLOW}"
    case "$AGENT" in
        *[Pp]lan*)                       A_CLR="${BOLD}${BLUE}"    ;;
        *[Ee]xplore*)                    A_CLR="${BOLD}${CYAN}"    ;;
        *[Tt]est*)                       A_CLR="${BOLD}${GREEN}"   ;;
        *[Dd]ebug*)                      A_CLR="${BOLD}${RED}"     ;;
        *[Bb]uild*|*[Cc]ompile*)         A_CLR="${BOLD}${MAGENTA}" ;;
        *[Ss]ecur*|*[Rr]eview*)          A_CLR="${BOLD}${RED}"     ;;
        *[Cc]ode*|*[Gg]eneral*|*[Dd]ev*) A_CLR="${BOLD}${WHITE}"  ;;
    esac
    AGENT_PART=" ${DIM}|${RESET} 🤖 ${A_CLR}${AGENT}${RESET}"
fi

# ── Git status (cached) ─────────────────────────────────────────────────────
git config --global --add safe.directory "$CWD" 2>/dev/null

GIT_PART=""
if git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    if is_cache_fresh "$GIT_CACHE" "$GIT_CACHE_AGE"; then
        eval "$(jq -r '@sh "BRANCH=\(.branch)",@sh "S=\(.staged)",@sh "M=\(.modified)",@sh "U=\(.untracked)"' "$GIT_CACHE" 2>/dev/null)"
    else
        BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null \
              || git -C "$CWD" rev-parse --short HEAD 2>/dev/null)

        ST=$(git -C "$CWD" status --porcelain 2>/dev/null)
        S=0; M=0; U=0
        if [ -n "$ST" ]; then
            while IFS= read -r line; do
                X="${line:0:1}"; Y="${line:1:1}"
                case "$X$Y" in
                    '??') (( U++ )) ;;
                    *)
                        [[ "$X" =~ [MADRC] ]] && (( S++ ))
                        [[ "$Y" =~ [MD] ]]    && (( M++ ))
                        ;;
                esac
            done <<< "$ST"
        fi

        printf '{"cached_at":%d,"branch":"%s","staged":%d,"modified":%d,"untracked":%d}\n' \
            "$(date +%s)" "$BRANCH" "$S" "$M" "$U" > "$GIT_CACHE" 2>/dev/null
    fi

    GS=""
    [ "$S" -gt 0 ] && GS="${GS} ${GREEN}+${S}${RESET}"
    [ "$M" -gt 0 ] && GS="${GS} ${RED}~${M}${RESET}"
    [ "$U" -gt 0 ] && GS="${GS} ${YELLOW}?${U}${RESET}"
    [ -z "$GS" ]   && GS=" ${GREEN}✔${RESET}"

    GIT_PART=" ${DIM}|${RESET} 🌿 ${BLUE}${BRANCH}${RESET}${GS}"
else
    GIT_PART=" ${DIM}|${RESET} ${DIM}no repo${RESET}"
fi

# ── Context usage (🔋 total, ⚡ session) ────────────────────────────────────
TOTAL_INT=$(printf "%.0f" "$USED_PCT" 2>/dev/null || echo "0")
[ "$TOTAL_INT" -gt 100 ] 2>/dev/null && TOTAL_INT=100

SESSION_TOKENS=$(( CUR_IN + CUR_OUT + CACHE_CREATE + CACHE_READ ))
if [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
    SESSION_INT=$(( SESSION_TOKENS * 100 / CTX_SIZE ))
else
    SESSION_INT=0
fi
[ "$SESSION_INT" -gt 100 ] && SESSION_INT=100

CTX_BAR=$(make_bar "$TOTAL_INT" 10)

B_CLR="${GREEN}"
[ "$TOTAL_INT" -ge 50 ] && B_CLR="${YELLOW}"
[ "$TOTAL_INT" -ge 80 ] && B_CLR="${RED}"

TOK_DISP=$(format_tokens $(( TOTAL_IN + TOTAL_OUT )))

CTX_PART="📊 ${B_CLR}${CTX_BAR}${RESET} 🔋${BOLD}${TOTAL_INT}%${RESET} ⚡${SESSION_INT}% ${DIM}(${TOK_DISP})${RESET}"

# ── Weekly plan usage (💳) — messages + model hours from transcript logs ────
# Scans all project JSONL transcripts for this week.
# Tracks: messages sent (assistant responses) and active hours per model.
# "Hours" = wall-clock time from first to last message in each session.

get_weekly_usage() {
    if is_cache_fresh "$USAGE_CACHE" "$USAGE_CACHE_AGE"; then
        cat "$USAGE_CACHE"
        return
    fi

    local now_epoch dow days_since_mon week_start_iso
    now_epoch=$(date +%s)
    # date +%u: 1=Mon … 7=Sun; fall back to %w (0=Sun) if needed
    dow=$(date -u +%u 2>/dev/null)
    # If %u is unsupported it may return the literal '%u'; fall back via %w
    if [[ "$dow" != [1-7] ]]; then
        dow=$(date -u +%w)          # 0=Sun
        [ "$dow" -eq 0 ] && dow=7  # make Sunday = 7 so Mon=1..Sun=7
    fi
    days_since_mon=$(( dow - 1 ))
    # Compute week-start ISO string purely with awk (portable, no GNU date -d needed)
    week_start_iso=$(awk -v now="$now_epoch" -v dsm="$days_since_mon" '
        BEGIN {
            sow = now - dsm * 86400
            # Format as YYYY-MM-DDTHH:MM:SS using gmtime
            t = sow
            sec  = t % 60;  t = int(t/60)
            min  = t % 60;  t = int(t/60)
            hour = t % 24;  t = int(t/24)
            # Rata Die algorithm to get year/month/day from days since Unix epoch
            z = t + 719468
            era = int((z >= 0 ? z : z - 146096) / 146097)
            doe = z - era * 146097
            yoe = int((doe - int(doe/1460) + int(doe/36524) - int(doe/146096)) / 365)
            y   = yoe + era * 400
            doy = doe - (365*yoe + int(yoe/4) - int(yoe/100))
            mp  = int((5*doy + 2) / 153)
            d   = doy - int((153*mp + 2)/5) + 1
            m   = mp + (mp < 10 ? 3 : -9)
            if (m <= 2) y++
            printf "%04d-%02d-%02dT00:00:00\n", y, m, d
        }' /dev/null)

    # Extract: sessionId, model, timestamp for each assistant message this week
    local raw
    raw=$(find "${CLAUDE_DIR}/projects/" -name "*.jsonl" 2>/dev/null | while IFS= read -r f; do
        jq -r '
            select(.type == "assistant" and .timestamp != null) |
            "\(.sessionId // "unknown") \(.message.model // "unknown") \(.timestamp)"
        ' "$f" 2>/dev/null
    done)

    # Compute messages + session hours per model using awk
    local result
    result=$(echo "$raw" | awk -v ws="$week_start_iso" '
    BEGIN {
        sonnet_msgs = 0; opus_msgs = 0; haiku_msgs = 0; other_msgs = 0
        total_msgs = 0
    }
    {
        sid = $1; model = $2; ts = $3
        if (ts < ws) next
        total_msgs++

        if (model ~ /opus/)       opus_msgs++
        else if (model ~ /haiku/) haiku_msgs++
        else if (model ~ /sonnet/) sonnet_msgs++
        else                      other_msgs++

        # Track first/last timestamp per session+model
        key = sid SUBSEP model
        if (!(key in first_ts) || ts < first_ts[key]) first_ts[key] = ts
        if (!(key in last_ts)  || ts > last_ts[key])  last_ts[key] = ts
    }
    END {
        # Sum session durations per model (in seconds via ISO timestamp diff)
        # Since awk cannot parse ISO dates natively, we estimate:
        # Extract HH:MM:SS from timestamps and compute diff in seconds
        sonnet_secs = 0; opus_secs = 0; haiku_secs = 0
        for (key in first_ts) {
            split(key, parts, SUBSEP)
            model = parts[2]
            ft = first_ts[key]; lt = last_ts[key]

            # Parse "YYYY-MM-DDTHH:MM:SS.mmmZ" → day + seconds
            split(ft, fa, "T"); split(fa[2], fb, ":")
            split(lt, la, "T"); split(la[2], lb, ":")

            # Day difference (crude: just use DD)
            split(fa[1], fd, "-"); split(la[1], ld, "-")
            day_diff = (ld[3]+0) - (fd[3]+0)

            f_sec = (fb[1]+0)*3600 + (fb[2]+0)*60 + int(fb[3]+0)
            l_sec = (lb[1]+0)*3600 + (lb[2]+0)*60 + int(lb[3]+0)
            dur = l_sec - f_sec + day_diff * 86400
            if (dur < 0) dur = 0

            if (model ~ /opus/)       opus_secs += dur
            else if (model ~ /sonnet/) sonnet_secs += dur
            else if (model ~ /haiku/) haiku_secs += dur
        }

        # Convert to hours (x10 for one decimal place in integer math)
        sonnet_h10 = int(sonnet_secs * 10 / 3600)
        opus_h10   = int(opus_secs * 10 / 3600)
        haiku_h10  = int(haiku_secs * 10 / 3600)

        printf "%d %d %d %d %d %d %d %d\n", \
            total_msgs, sonnet_msgs, opus_msgs, haiku_msgs, \
            sonnet_h10, opus_h10, haiku_h10, other_msgs
    }')

    local total_msgs sonnet_msgs opus_msgs haiku_msgs sonnet_h10 opus_h10 haiku_h10 other_msgs
    read -r total_msgs sonnet_msgs opus_msgs haiku_msgs sonnet_h10 opus_h10 haiku_h10 other_msgs <<< "$result"

    # Write cache with all fields
    printf '{"cached_at":%d,"week_start":"%s","total_msgs":%d,"sonnet_msgs":%d,"opus_msgs":%d,"haiku_msgs":%d,"other_msgs":%d,"sonnet_h10":%d,"opus_h10":%d,"haiku_h10":%d}\n' \
        "$now_epoch" "$week_start_iso" \
        "${total_msgs:-0}" "${sonnet_msgs:-0}" "${opus_msgs:-0}" "${haiku_msgs:-0}" "${other_msgs:-0}" \
        "${sonnet_h10:-0}" "${opus_h10:-0}" "${haiku_h10:-0}" \
        > "$USAGE_CACHE" 2>/dev/null

    cat "$USAGE_CACHE"
}

PLAN_JSON=$(get_weekly_usage)
PLAN_TOTAL_MSGS=$(echo "$PLAN_JSON" | jq -r '.total_msgs // 0')
PLAN_SONNET_H10=$(echo "$PLAN_JSON" | jq -r '.sonnet_h10 // 0')
PLAN_OPUS_H10=$(echo "$PLAN_JSON" | jq -r '.opus_h10 // 0')
PLAN_SONNET_MSGS=$(echo "$PLAN_JSON" | jq -r '.sonnet_msgs // 0')
PLAN_OPUS_MSGS=$(echo "$PLAN_JSON" | jq -r '.opus_msgs // 0')

# Calculate percentages against weekly budgets
SONNET_PCT=0
if [ "$SONNET_WEEKLY_HOURS" -gt 0 ]; then
    SONNET_PCT=$(( PLAN_SONNET_H10 * 100 / (SONNET_WEEKLY_HOURS * 10) ))
fi
[ "$SONNET_PCT" -gt 100 ] && SONNET_PCT=100

OPUS_PCT=0
if [ "$OPUS_WEEKLY_HOURS" -gt 0 ]; then
    OPUS_PCT=$(( PLAN_OPUS_H10 * 100 / (OPUS_WEEKLY_HOURS * 10) ))
fi
[ "$OPUS_PCT" -gt 100 ] && OPUS_PCT=100

# Format hours: e.g. 125 (h*10) → "12.5h"
fmt_hours() {
    local h10=$1
    echo "$(( h10 / 10 )).$(( h10 % 10 ))h"
}

# Build plan part — show whichever model is active, plus total messages
# Sonnet section
S_CLR="${GREEN}"
[ "$SONNET_PCT" -ge 50 ] && S_CLR="${YELLOW}"
[ "$SONNET_PCT" -ge 80 ] && S_CLR="${RED}"
S_BAR=$(make_bar "$SONNET_PCT" 5)
S_HRS=$(fmt_hours "$PLAN_SONNET_H10")

# Opus section
O_CLR="${GREEN}"
[ "$OPUS_PCT" -ge 50 ] && O_CLR="${YELLOW}"
[ "$OPUS_PCT" -ge 80 ] && O_CLR="${RED}"
O_BAR=$(make_bar "$OPUS_PCT" 5)
O_HRS=$(fmt_hours "$PLAN_OPUS_H10")

PLAN_PART=" ${DIM}|${RESET} 💳 🎶${S_CLR}${S_BAR}${RESET}${DIM}${S_HRS}${RESET} 🎵${O_CLR}${O_BAR}${RESET}${DIM}${O_HRS}${RESET} 💬${DIM}${PLAN_TOTAL_MSGS}${RESET}"

# ── Directory (show last component only) ─────────────────────────────────────
# Handle both forward-slash (POSIX/MSYS) and backslash (Windows) separators
_cwd_normalized="${CWD//\\//}"          # replace all \ with /
DIR_NAME="${_cwd_normalized##*/}"       # strip everything up to last /
[ -z "$DIR_NAME" ] && DIR_NAME="$CWD"  # fallback: use full path if empty

# ── Output single line ───────────────────────────────────────────────────────
echo -e "${M_EMOJI}${AGENT_PART} ${DIM}|${RESET} 📁 ${DIR_NAME}${GIT_PART} ${DIM}|${RESET} ${CTX_PART}${PLAN_PART}"
