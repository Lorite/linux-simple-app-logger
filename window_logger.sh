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
    echo " --summarize                     Generate today's summary and exit."
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
    local out val escaped gv_arg
    # Wrap as a GVariant string literal to satisfy gdbus parsing
    escaped=$(printf "%s" "$js" | sed "s/'/'\\''/g")
    gv_arg="'$escaped'"
    out=$(gdbus call --session \
          --dest org.gnome.Shell \
          --object-path /org/gnome/Shell \
          --method org.gnome.Shell.Eval \
          "$gv_arg" 2>/dev/null || true)
    # Expect format: (true, '...') or (false, '...')
    if echo "$out" | grep -q "^(true,"; then
        val=$(echo "$out" | awk -F", '" '{print $2}' | sed "s/')$//")
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

get_active_window_id() {
    # KDE Wayland/X11 via kdotool (returns KWin UUID)
    if is_kde_session && command -v kdotool &>/dev/null; then
        local kid
        kid=$(kdotool getactivewindow 2>/dev/null || true)
        if [[ -n "$kid" ]]; then
            echo "$kid"
            return
        fi
    fi
    # GNOME Wayland: prefer gdbus/AT-SPI, avoid stale XWayland IDs
    if [[ "${XDG_SESSION_TYPE}" == "wayland" ]] && is_gnome_session; then
        if command -v gdbus &>/dev/null; then
            local seq
            seq=$(gnome_shell_eval "(() => { let w = global.display.get_focus_window(); return w ? String(w.get_stable_sequence()) : ''; })()")
            if [[ -n "$seq" ]]; then
                echo "GWM-${seq}"
                return
            fi
        fi
        # AT-SPI synthesized ID
        local at_title at_app hash
        readarray -t __atspi_lines < <(gnome_atspi_get_title_app)
        at_title="${__atspi_lines[0]}"; at_app="${__atspi_lines[1]}"
        if [[ -n "$at_title$at_app" ]]; then
            hash=$(printf '%s' "$at_app|$at_title" | md5sum | awk '{print $1}')
            echo "GNA-${hash}"
            return
        fi
        echo ""
        return
    fi

    # X/XWayland fallback
    if command -v xdotool &>/dev/null; then
        local xid
        xid=$(xdotool getactivewindow 2>/dev/null || true)
        if [[ -n "$xid" ]]; then
            echo "$xid"
            return
        fi
    fi

    echo ""
}

get_window_title() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        echo ""
        return
    fi
    # GNOME Wayland: prefer AT-SPI, then gdbus
    if [[ "${XDG_SESSION_TYPE}" == "wayland" ]] && is_gnome_session; then
        local val
        # AT-SPI first
        readarray -t __atspi_lines < <(gnome_atspi_get_title_app)
        val="${__atspi_lines[0]}"
        if [[ -n "$val" ]]; then
            echo "$val" | tr -d '\n\r'
            return
        fi
        # gdbus as secondary
        if command -v gdbus &>/dev/null; then
            val=$(gnome_shell_eval "(() => { let w = global.display.get_focus_window(); return w ? w.get_title() : ''; })()")
            if [[ -n "$val" ]]; then
                echo "$val" | tr -d '\n\r'
                return
            fi
        fi
        # fall through to other paths
    fi
    # KDE Wayland/X11: prefer kdotool if window id is from KWin or we're in KDE
    if is_kde_session && command -v kdotool &>/dev/null; then
        local name_k
        name_k=$(kdotool getwindowname "$window_id" 2>/dev/null || true)
        if [[ -n "$name_k" ]]; then
            echo "$name_k" | tr -d '\n\r'
            return
        fi
    fi
    # Try xdotool next (better under X/XWayland setups)
    if command -v xdotool &>/dev/null; then
        local name
        name=$(xdotool getwindowname "$window_id" 2>/dev/null || true)
        if [[ -n "$name" ]]; then
            echo "$name" | tr -d '\n\r'
            return
        fi
    fi

    # Fallback to xprop. Filter out 'not found.' markers
    local raw
    raw=$(xprop -id "$window_id" WM_NAME 2>/dev/null)
    if echo "$raw" | grep -qi 'not found'; then
        raw=""
    fi
    if [[ -n "$raw" ]]; then
        echo "$raw" | cut -d '=' -f 2 | sed 's/"//g' | tr -d '\n\r'
        return
    fi

    echo ""
}

get_process_name() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        echo ""
        return
    fi
    local pid=""

    # GNOME Wayland: prefer AT-SPI, then gdbus
    if [[ "${XDG_SESSION_TYPE}" == "wayland" ]] && is_gnome_session; then
        local val
        # AT-SPI first
        readarray -t __atspi_lines < <(gnome_atspi_get_title_app)
        val="${__atspi_lines[1]}"
        if [[ -n "$val" ]]; then
            echo "$val" | tr -d '\n\r'
            return
        fi
        # gdbus secondary
        if command -v gdbus &>/dev/null; then
            val=$(gnome_shell_eval "(() => { const Shell = imports.gi.Shell; let w = global.display.get_focus_window(); if (!w) return ''; let wt = Shell.WindowTracker.get_default(); let app = wt.get_window_app(w); if (app) return app.get_name(); let c = w.get_wm_class && w.get_wm_class(); return c ? c : ''; })()")
            if [[ -n "$val" ]]; then
                echo "$val" | tr -d '\n\r'
                return
            fi
        fi
        # fall through
    fi

    # KDE Wayland/X11: prefer kdotool for PID if available
    if is_kde_session && command -v kdotool &>/dev/null; then
        pid=$(kdotool getwindowpid "$window_id" 2>/dev/null || true)
    fi

    # Try xdotool next (may still work under X/XWayland)
    if [[ -z "$pid" ]] && command -v xdotool &>/dev/null; then
        pid=$(xdotool getwindowpid "$window_id" 2>/dev/null || true)
    fi

    # Fallback to xprop and extract only digits
    if [[ -z "$pid" ]]; then
        pid=$(xprop -id "$window_id" _NET_WM_PID 2>/dev/null \
            | awk -F' = ' '/_NET_WM_PID/ {print $2}' \
            | tr -d ' ')
    fi

    # If PID is numeric and positive, resolve process name
    if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
        ps -p "$pid" -o comm= | tr -d '\n\r'
        return
    fi

    # As a next resort, use WM_CLASS (class part) as an app identifier
    local wm_class
    wm_class=$(xprop -id "$window_id" WM_CLASS 2>/dev/null)
    if [[ -n "$wm_class" ]] && ! echo "$wm_class" | grep -qi 'not found'; then
        # WM_CLASS(STRING) = "instance", "Class" -> take the Class token
        echo "$wm_class" | awk -F', ' '{print $NF}' | tr -d ' "\n\r'
        return
    fi

    echo ""
}

get_active_window_info() {
    local -n _window_id_ref=$1
    local -n _window_title_ref=$2
    local -n _app_name_ref=$3

    _window_id_ref=$(get_active_window_id)
    if [[ -z "$_window_id_ref" ]]; then
        _window_title_ref=""
        _app_name_ref=""
        return
    fi
    _window_title_ref=$(get_window_title "$_window_id_ref")
    _app_name_ref=$(get_process_name "$_window_id_ref")
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
            echo "[debug] id=$current_window_id title=$current_window_title app=$current_app_name"
        fi

        if [[ -z "$current_window_title" ]]; then
            sleep "$SLEEP_INTERVAL"
            continue
        fi

          # Detect changes by ID, title, or app name (Wayland can reuse/stabilize IDs)
          if [[ "$current_window_id" != "$previous_window_id" \
              || "$current_window_title" != "$previous_window_title" \
              || "$current_app_name" != "$previous_app_name" ]]; then
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

check_dependencies

main "$@"
