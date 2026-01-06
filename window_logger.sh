#!/bin/bash

# --- Configuration ---

# Default values
OUTPUT_FOLDER="."
SLEEP_INTERVAL=1 # in seconds
MIN_LOG_DURATION=2 # in seconds
PROCESS_BLACKLIST_REGEX="" # Regex to match process names to ignore, e.g., "gnome-shell|plank"
WINDOW_BLACKLIST_REGEX=""    # Regex to match window titles to ignore, e.g., "Brave"
CUSTOM_SCRIPT_FILE="custom_scripts/my_custom_script.sh"        # Path to a custom script file to source.

# --- Functions ---

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -o, --output-folder FOLDER      Set the output folder for logs. Default is '.'."
    echo "  -s, --sleep-interval SECONDS    Set the sleep interval in seconds. Default is 1."
    echo "  -m, --min-log-duration SECONDS  Set the minimum duration for an activity to be logged. Default is 2."
    echo "  -p, --process-blacklist REGEX   Regex to match process names to ignore. Default is empty."
    echo "  -w, --window-blacklist REGEX    Regex to match window titles to ignore. Default is empty."
    echo "  -c, --custom-script SCRIPT_PATH Path to a custom script file to source. Default is 'custom_scripts/my_custom_script.sh'."
    echo "  --debug                         Print debug info (id/title/app each loop)."
    echo "  --summarize                     Generate today's summary and exit."
    echo "  -h, --help                      Show this help message."
    exit 0
}

check_dependencies() {
    # Require xprop
    if ! command -v xprop &>/dev/null; then
        echo "Error: Required command 'xprop' not found. Please install it." >&2
        exit 1
    fi
    # Require at least one of xdotool or kdotool
    if ! command -v xdotool &>/dev/null && ! command -v kdotool &>/dev/null; then
        echo "Error: Neither 'xdotool' nor 'kdotool' found. Install one of them." >&2
        exit 1
    fi
    # Optional: gdbus/AT-SPI for Wayland+GNOME fallback (do not fail if missing)
    if [[ "${XDG_SESSION_TYPE}" == "wayland" ]] && pgrep -x gnome-shell >/dev/null 2>&1; then
        local has_gdbus=1 has_atspi=1
        if command -v gdbus &>/dev/null; then has_gdbus=0; fi
        if python3 -c 'import pyatspi' 2>/dev/null; then has_atspi=0; fi
        if (( has_gdbus != 0 )); then
            echo "Note: 'gdbus' not found. GNOME Wayland gdbus path disabled." >&2
        fi
        if (( has_atspi != 0 )); then
            echo "Note: 'python3-pyatspi' not found. GNOME Wayland AT-SPI path disabled." >&2
        fi
        if (( has_gdbus != 0 && has_atspi != 0 )); then
            echo "Warning: On GNOME Wayland with neither gdbus nor AT-SPI, title/app may be empty. Install: sudo apt install -y libglib2.0-bin python3-pyatspi at-spi2-core python3-gi" >&2
        fi
    fi
}

# Cache environment/session/tool flags to avoid repeated checks
init_env_flags() {
    IS_WAYLAND=0; [[ "${XDG_SESSION_TYPE}" == "wayland" ]] && IS_WAYLAND=1
    IS_KDE=0; IS_GNOME=0
    if pgrep -x kwin_wayland >/dev/null 2>&1 || pgrep -x kwin_x11 >/dev/null 2>&1 || [[ -n "$KDE_FULL_SESSION" || "$XDG_CURRENT_DESKTOP" =~ KDE|PLASMA ]]; then
        IS_KDE=1
    fi
    if pgrep -x gnome-shell >/dev/null 2>&1 || [[ "$XDG_CURRENT_DESKTOP" =~ GNOME ]]; then
        IS_GNOME=1
    fi
    HAVE_XPROP=0; command -v xprop &>/dev/null && HAVE_XPROP=1
    HAVE_XDOTOOL=0; command -v xdotool &>/dev/null && HAVE_XDOTOOL=1
    HAVE_KDOTOOL=0; command -v kdotool &>/dev/null && HAVE_KDOTOOL=1
    HAVE_GDBUS=0; command -v gdbus &>/dev/null && HAVE_GDBUS=1
    # Detect AT-SPI (pyatspi) properly via output, not exit code
    HAVE_ATSPI=$(python3 - <<'PY' 2>/dev/null
try:
    import pyatspi
    print('1')
except Exception:
    print('0')
PY
    )
}

is_kde_session() {
    if pgrep -x kwin_wayland >/dev/null 2>&1 || pgrep -x kwin_x11 >/dev/null 2>&1; then
        return 0
    fi
    if [[ -n "$KDE_FULL_SESSION" || "$XDG_CURRENT_DESKTOP" =~ KDE|PLASMA ]]; then
        return 0
    fi
    return 1
}

is_gnome_session() {
    if pgrep -x gnome-shell >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$XDG_CURRENT_DESKTOP" =~ GNOME ]]; then
        return 0
    fi
    return 1
}

# Evaluate JavaScript in GNOME Shell via DBus and return the string result
# Only returns output if Eval succeeded (true); otherwise prints nothing
gnome_shell_eval() {
    local js="$1"
    local out val escaped
    # Escape single quotes for GVariant
    escaped="${js//\'/\'\\\'\'}"
    out=$(gdbus call --session \
          --dest org.gnome.Shell \
          --object-path /org/gnome/Shell \
          --method org.gnome.Shell.Eval \
          "'$escaped'" 2>/dev/null || true)
    # Expect format: (true, '...') or (false, '...')
    if [[ "$out" == "(true,"* ]]; then
        # Extract value between (true, ' and ')
        val="${out#*\'}"
        val="${val%\')*}"
        printf "%s" "$val"
    fi
}

# GNOME Wayland: read focused window title and app via AT-SPI (python3-pyatspi)
# Prints two lines: title then app name. Prints nothing on failure.
gnome_atspi_get_title_app() {
    python3 - "$@" 2>/dev/null <<'PY'
import sys
try:
    import pyatspi
except Exception:
    pyatspi = None
title = ''
appname = ''
try:
    if pyatspi is not None:
        desktop = pyatspi.Registry.getDesktop(0)
        focus = None
        try:
            focus = desktop.getFocus()
        except Exception:
            focus = None
        # Fallback: search for ACTIVE/FOCUSED frame
        if focus is None:
            try:
                for i in range(desktop.childCount):
                    app = desktop.getChildAtIndex(i)
                    for j in range(getattr(app, 'childCount', 0)):
                        w = app.getChildAtIndex(j)
                        try:
                            st = w.getState()
                            # Prefer focused, else active
                            if st.contains(pyatspi.STATE_FOCUSED) or st.contains(pyatspi.STATE_ACTIVE):
                                focus = w
                                raise StopIteration
                        except Exception:
                            pass
            except StopIteration:
                pass
            except Exception:
                pass
        if focus is not None:
            try:
                title = focus.name or ''
            except Exception:
                title = ''
            try:
                app = focus.getApplication() if hasattr(focus, 'getApplication') else None
                appname = (app.name if app and hasattr(app, 'name') else '') or ''
            except Exception:
                appname = ''
except Exception:
    pass
print(title)
print(appname)
PY
}

check_output_folder() {
    if [[ ! -d "$OUTPUT_FOLDER" ]]; then
        echo "Error: Output folder '$OUTPUT_FOLDER' does not exist." >&2
        exit 1
    fi

    if [[ ! -w "$OUTPUT_FOLDER" ]]; then
        echo "Error: No write permission for output folder '$OUTPUT_FOLDER'." >&2
        exit 1
    fi
}

check_file_exists_and_create() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        mkdir -p "$(dirname "$file_path")"
        echo "\"App name\",\"Window Title\",\"Date\",\"Time\",\"Duration\"" >"$file_path"
    fi
}

get_output_file_for_today() {
    local today
    today=$(date +"%Y-%m-%d")
    echo "$OUTPUT_FOLDER/$today/LORI_Activity_$today.csv"
}

proc_name_from_pid() {
    local pid="$1"
    if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
        ps -p "$pid" -o comm= | tr -d '\n\r'
    fi
}

# Bash-native simple hash (for id generation)
bash_hash() {
    local str="$1" h=0 i c
    for (( i=0; i<${#str}; i++ )); do
        c="${str:$i:1}"
        printf -v c '%d' "'$c"
        h=$(( (h * 31 + c) & 0x7FFFFFFF ))
    done
    printf '%x' "$h"
}

# Unified active window info: echoes 3 lines (id, title, app)
get_active_info() {
    local id="" title="" app="" hash seq
    local now=$(( $(date +%s) ))

    # GNOME Wayland path - heavily optimized to minimize subprocess calls
    if (( IS_WAYLAND == 1 && IS_GNOME == 1 )); then
        if (( HAVE_GDBUS == 1 )); then
            # Only query gdbus every 2 seconds OR if we suspect a change
            if (( now - LAST_GDBUS_CHECK >= 2 )) || [[ -z "$CACHED_GNOME_SEQ" ]]; then
                seq=$(gnome_shell_eval "(() => { let w = global.display.get_focus_window(); return w ? String(w.get_stable_sequence()) : ''; })()")
                LAST_GDBUS_CHECK=$now
                if [[ -n "$seq" && "$seq" != "$CACHED_GNOME_SEQ" ]]; then
                    CACHED_GNOME_SEQ="$seq"
                    # Sequence changed - fetch title/app via AT-SPI
                    if (( HAVE_ATSPI == 1 )); then
                        readarray -t __atspi_lines < <(gnome_atspi_get_title_app)
                        CACHED_GNOME_TITLE="${__atspi_lines[0]:-}"
                        CACHED_GNOME_APP="${__atspi_lines[1]:-}"
                    fi
                fi
            fi
            # Use cached values
            if [[ -n "$CACHED_GNOME_SEQ" ]]; then
                id="GWM-${CACHED_GNOME_SEQ}"
                title="$CACHED_GNOME_TITLE"
                app="$CACHED_GNOME_APP"
            fi
        fi
        # Fallback: AT-SPI without gdbus (only if no ID from gdbus)
        if [[ -z "$id" ]] && (( HAVE_ATSPI == 1 )); then
            # Only refresh AT-SPI every 2 seconds
            if (( now - LAST_ATSPI_CHECK >= 2 )) || [[ -z "$CACHED_GNOME_TITLE" && -z "$CACHED_GNOME_APP" ]]; then
                readarray -t __atspi_lines < <(gnome_atspi_get_title_app)
                CACHED_GNOME_TITLE="${__atspi_lines[0]:-}"
                CACHED_GNOME_APP="${__atspi_lines[1]:-}"
                LAST_ATSPI_CHECK=$now
            fi
            title="$CACHED_GNOME_TITLE"
            app="$CACHED_GNOME_APP"
            if [[ -n "$title$app" ]]; then
                hash=$(bash_hash "$app|$title")
                id="GNA-${hash}"
            fi
        fi
        echo "$id"; echo "$title"; echo "$app"
        return
    fi

    # KDE path via kdotool
    if (( IS_KDE == 1 && HAVE_KDOTOOL == 1 )); then
        id=$(kdotool getactivewindow 2>/dev/null || true)
        title=$(kdotool getwindowname "$id" 2>/dev/null || true)
        local pid=""; pid=$(kdotool getwindowpid "$id" 2>/dev/null || true)
        app=$(proc_name_from_pid "$pid")
        # Fallback to WM_CLASS if app empty
        if [[ -z "$app" && $HAVE_XPROP -eq 1 && -n "$id" ]]; then
            local wm_class
            wm_class=$(xprop -id "$id" WM_CLASS 2>/dev/null)
            if [[ -n "$wm_class" ]] && ! echo "$wm_class" | grep -qi 'not found'; then
                app=$(echo "$wm_class" | awk -F', ' '{print $NF}' | tr -d ' "\n\r')
            fi
        fi
        echo "$id"; echo "$title"; echo "$app"
        return
    fi

    # X11/XWayland path via xdotool/xprop
    if (( HAVE_XDOTOOL == 1 )); then
        id=$(xdotool getactivewindow 2>/dev/null || true)
        title=$(xdotool getwindowname "$id" 2>/dev/null || true)
        local pid=""
        pid=$(xdotool getwindowpid "$id" 2>/dev/null || true)
        if [[ -z "$pid" && $HAVE_XPROP -eq 1 ]]; then
            pid=$(xprop -id "$id" _NET_WM_PID 2>/dev/null | awk -F' = ' '/_NET_WM_PID/ {print $2}' | tr -d ' ')
        fi
        app=$(proc_name_from_pid "$pid")
        if [[ -z "$app" && $HAVE_XPROP -eq 1 && -n "$id" ]]; then
            local wm_class
            wm_class=$(xprop -id "$id" WM_CLASS 2>/dev/null)
            if [[ -n "$wm_class" ]] && ! echo "$wm_class" | grep -qi 'not found'; then
                app=$(echo "$wm_class" | awk -F', ' '{print $NF}' | tr -d ' "\n\r')
            fi
        fi
        # Last resort title via xprop
        if [[ -z "$title" && $HAVE_XPROP -eq 1 && -n "$id" ]]; then
            local raw
            raw=$(xprop -id "$id" WM_NAME 2>/dev/null)
            if ! echo "$raw" | grep -qi 'not found'; then
                title=$(echo "$raw" | cut -d '=' -f 2 | sed 's/"//g' | tr -d '\n\r')
            fi
        fi
        echo "$id"; echo "$title"; echo "$app"
        return
    fi

    # Default empty
    echo ""; echo ""; echo ""
}

## Legacy per-field getters removed in favor of get_active_info()

get_active_window_info() {
    local -n _window_id_ref=$1
    local -n _window_title_ref=$2
    local -n _app_name_ref=$3
    readarray -t __info < <(get_active_info)
    _window_id_ref="${__info[0]}"
    _window_title_ref="${__info[1]}"
    _app_name_ref="${__info[2]}"
}

fetch_media_title() {
    if command -v playerctl &> /dev/null; then
        local video_title
        local channel_name
        video_title=$(playerctl metadata title 2>/dev/null)
        channel_name=$(playerctl metadata xesam:artist 2>/dev/null)
        if [[ -n "$video_title" && -n "$channel_name" ]]; then
            echo "$channel_name — $video_title"
        elif [[ -n "$video_title" ]]; then
            echo "$video_title"
        else
            echo ""
        fi
    else
        echo ""
    fi
}

handle_media_activity() {
    # Only check playerctl every 3 seconds to reduce CPU usage
    local now=$(date +%s)
    if (( now - LAST_MEDIA_CHECK < 3 )); then
        return
    fi
    LAST_MEDIA_CHECK=$now
    
    local player_status
    player_status=$(playerctl status 2>/dev/null)
    
    if [[ "$player_status" == "Playing" ]]; then
        local current_media_comment
        current_media_comment=$(fetch_media_title)

        if [[ "$current_media_comment" != "$previous_media_comment" ]]; then
            # Finish previous media activity if there was one
            if [[ -n "$previous_media_comment" && "$media_start_time" -ne 0 ]]; then
                local end_time duration
                end_time=$(date +%s)
                duration=$((end_time - media_start_time))
                if declare -f on_finished_activity > /dev/null; then
                    on_finished_activity "Media" "$previous_media_comment" "$duration"
                fi
            fi

            # Start new media activity
            if [[ -n "$current_media_comment" ]]; then
                if declare -f on_new_activity > /dev/null; then
                    on_new_activity "Media" "$current_media_comment"
                fi
                previous_media_comment="$current_media_comment"
                media_start_time=$(date +%s)
            fi
        elif [[ -z "$previous_media_comment" && -n "$current_media_comment" ]]; then
            # Resuming playback of the same media
            if declare -f on_new_activity > /dev/null; then
                on_new_activity "Media" "$current_media_comment"
            fi
            previous_media_comment="$current_media_comment"
            media_start_time=$(date +%s)
        fi
    else # Paused or Stopped
        if [[ -n "$previous_media_comment" && "$media_start_time" -ne 0 ]]; then
            local end_time duration
            end_time=$(date +%s)
            duration=$((end_time - media_start_time))
            if declare -f on_finished_activity > /dev/null; then
                on_finished_activity "Media" "$previous_media_comment" "$duration"
            fi
            previous_media_comment=""
            media_start_time=0
        fi
    fi
}

is_blacklisted() {
    local app_name="$1"
    local window_title="$2"

    # Built-in: ignore GNOME Shell overview (Main stage)
    local _app_lc _title_lc
    _app_lc="${app_name,,}"
    _title_lc="${window_title,,}"
    if [[ "$_app_lc" == "gnome-shell" && "$_title_lc" == "main stage" ]]; then
        return 0
    fi

    if [[ -n "$PROCESS_BLACKLIST_REGEX" ]] && [[ "$app_name" =~ $PROCESS_BLACKLIST_REGEX ]]; then
        return 0
    fi

    if [[ -n "$WINDOW_BLACKLIST_REGEX" ]] && [[ "$window_title" =~ $WINDOW_BLACKLIST_REGEX ]]; then
        return 0
    fi

    return 1
}

log_previous_activity() {
    if [[ -n "$previous_window_title" ]]; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        if declare -f on_finished_activity > /dev/null; then
            on_finished_activity "$previous_app_name" "$previous_window_title" "$duration" # user-defined external function call
        fi
        
        # Only log if we have sensible identifiers (avoid WM_CLASS/WM_NAME not found noise)
        if [[ $duration -ge $MIN_LOG_DURATION ]]; then
            if [[ -n "$previous_app_name" && -n "$previous_window_title" ]] \
               && [[ ! "$previous_app_name" =~ ^WM_CLASS:notfound\.$ ]] \
               && [[ ! "$previous_window_title" =~ ^WM_NAME:\ +not\ found\.$ ]]; then
                if ! is_blacklisted "$previous_app_name" "$previous_window_title"; then
                    log_message "$previous_app_name" "$previous_window_title" "$duration"
                fi
            fi
        fi
    fi
}

format_duration() {
    local duration_seconds="$1"
    local h m s
    h=$((duration_seconds / 3600))
    m=$(((duration_seconds % 3600) / 60))
    s=$((duration_seconds % 60))
    printf "%02d:%02d:%02d" "$h" "$m" "$s"
}

log_message() {
    local app_name="$1"
    local window_title="$2"
    local duration_seconds="$3"
    local date
    local time
    local duration_formatted
    local output_file

    date=$(date +"%Y-%m-%d")
    time=$(date +"%H:%M:%S")
    output_file=$(get_output_file_for_today)
    check_file_exists_and_create "$output_file"

    duration_formatted=$(format_duration "$duration_seconds")

    # Escape double quotes in app_name and window_title for CSV
    app_name_csv=$(echo "$app_name" | sed 's/"/""/g')
    window_title_csv=$(echo "$window_title" | sed 's/"/""/g')

    echo "\"$app_name_csv\",\"$window_title_csv\",\"$date\",\"$time\",\"$duration_formatted\"" | tee -a "$output_file"
}

cleanup() {
    echo -e "\nStopping window logger."
    # Log the duration of the last activity before exiting
    log_previous_activity
    # Generate summary statistics before custom cleanup
    calculate_todays_most_used_apps
    if declare -f on_cleanup > /dev/null; then
        on_cleanup
    fi
    exit 0
}

calculate_todays_most_used_apps() {
    bash "$(dirname "$0")/generate_summary.sh" -o "$OUTPUT_FOLDER"
}

# --- Main Logic ---

main() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -o|--output-folder)
                OUTPUT_FOLDER="$2"
                shift 2
                ;;
            -s|--sleep-interval)
                SLEEP_INTERVAL="$2"
                shift 2
                ;;
            -m|--min-log-duration)
                MIN_LOG_DURATION="$2"
                shift 2
                ;;
            -p|--process-blacklist)
                PROCESS_BLACKLIST_REGEX="$2"
                shift 2
                ;;
            -w|--window-blacklist)
                WINDOW_BLACKLIST_REGEX="$2"
                shift 2
                ;;
            -c|--custom-script)
                CUSTOM_SCRIPT_FILE="$2"
                shift 2
                ;;
            --summarize)
                check_output_folder
                calculate_todays_most_used_apps
                exit 0
                ;;
            --debug)
                DEBUG=1
                shift 1
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                ;;
        esac
    done

    if [[ -n "$CUSTOM_SCRIPT_FILE" ]]; then
        if [[ -f "$CUSTOM_SCRIPT_FILE" ]]; then
            # shellcheck source=/dev/null
            source "$CUSTOM_SCRIPT_FILE"
        else
            echo "Error: Custom script file '$CUSTOM_SCRIPT_FILE' not found." >&2
            exit 1
        fi
    fi

    check_output_folder

    # Start listening for screen lock events in the background
    handle_lock_events &

    # Initialize with the current active window at script start
    get_active_window_info previous_window_id previous_window_title previous_app_name
    start_time=$(date +%s)

    local output_file
    output_file=$(get_output_file_for_today)
    check_file_exists_and_create "$output_file"

    echo "Starting window logger. Press Ctrl+C to stop."

    while true; do
        local current_window_id
        local current_window_title
        local current_app_name
        get_active_window_info current_window_id current_window_title current_app_name

        if [[ -n "$DEBUG" ]]; then
            local backend_src="none"
            if [[ "$current_window_id" == GWM-* ]]; then
                backend_src="gnome-gdbus"
            elif [[ "$current_window_id" == GNA-* ]]; then
                backend_src="gnome-atspi"
            elif [[ "$current_window_id" =~ ^[0-9]+$ ]]; then
                backend_src="xdotool"
            elif [[ -n "$current_window_id" ]]; then
                backend_src="kdotool"
            fi
            echo "[debug] id=$current_window_id title=$current_window_title app=$current_app_name src=$backend_src"
        fi

        if [[ -z "$current_window_title" ]]; then
            sleep "$SLEEP_INTERVAL"
            continue
        fi

        # Skip blacklisted overlays (e.g., GNOME Shell Main stage) without ending previous activity
        if is_blacklisted "$current_app_name" "$current_window_title"; then
            sleep "$SLEEP_INTERVAL"
            continue
        fi

          # Detect changes by ID or title (Wayland can reuse/stabilize IDs)
          if [[ "$current_window_id" != "$previous_window_id" \
              || "$current_window_title" != "$previous_window_title" ]]; then
            log_previous_activity

            previous_window_id="$current_window_id"
            previous_app_name="$current_app_name"
            previous_window_title="$current_window_title"

            start_time=$(date +%s)
            if declare -f on_new_activity > /dev/null; then
                on_new_activity "$previous_app_name" "$previous_window_title" # user-defined external function call
            fi
        fi

        if declare -f on_loop_interval > /dev/null; then
            on_loop_interval "$current_app_name" "$current_window_title" # user-defined external function call
        fi

        handle_media_activity

        sleep "$SLEEP_INTERVAL"
    done
}

# --- Script Execution ---

_logger_completions() {
    local cur_word prev_word
    cur_word="${COMP_WORDS[COMP_CWORD]}"
    prev_word="${COMP_WORDS[COMP_CWORD-1]}"
    local opts="--output-folder --sleep-interval --min-log-duration --process-blacklist --window-blacklist --custom-script --help"

    if [[ ${cur_word} == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur_word}) )
        return 0
    fi
}

complete -F _logger_completions window_logger.sh

trap cleanup SIGINT SIGTERM

# --- Functions for handling screen lock ---
handle_lock_events() {
    dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver',member='ActiveChanged'" |
    while read -r line; do
        if echo "$line" | grep -q "boolean true"; then
            echo "Screen locked, running on_lock handler..."
            on_lock
        fi
    done
}

on_lock() {
    if declare -f on_cleanup > /dev/null; then
        on_cleanup
    fi
}


# Global variables for cleanup handler
previous_window_id=""
previous_window_title=""
previous_app_name=""
start_time=0
previous_media_comment=""
media_start_time=0

# Cache for GNOME Wayland to reduce Python subprocess calls
CACHED_GNOME_SEQ=""
CACHED_GNOME_TITLE=""
CACHED_GNOME_APP=""
LAST_GDBUS_CHECK=0
LAST_ATSPI_CHECK=0
LAST_MEDIA_CHECK=0

check_dependencies
init_env_flags

main "$@"
