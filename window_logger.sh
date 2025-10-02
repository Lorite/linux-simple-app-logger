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
    echo " --summarize                     Generate today's summary and exit."
    echo "  -h, --help                      Show this help message."
    exit 0
}

check_dependencies() {
    for cmd in xdotool xprop; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' not found. Please install it." >&2
            exit 1
        fi
    done
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
    xdotool getactivewindow 2>/dev/null
}

get_window_title() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        echo ""
        return
    fi
    xprop -id "$window_id" WM_NAME 2>/dev/null | cut -d '=' -f 2 | sed 's/"//g' | tr -d '\n\r'
}

get_process_name() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        echo ""
        return
    fi
    local pid
    pid=$(xprop -id "$window_id" _NET_WM_PID 2>/dev/null | cut -d '=' -f 2 | tr -d ' ')
    if [[ -n "$pid" && "$pid" -gt 0 ]]; then
        ps -p "$pid" -o comm= | tr -d '\n\r'
    else
        echo ""
    fi
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
        
        if [[ $duration -ge $MIN_LOG_DURATION ]]; then
            if ! is_blacklisted "$previous_app_name" "$previous_window_title"; then
                log_message "$previous_app_name" "$previous_window_title" "$duration"
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

        if [[ -z "$current_window_title" ]]; then
            sleep "$SLEEP_INTERVAL"
            continue
        fi

        if [[ "$current_window_id" != "$previous_window_id" || "$current_window_title" != "$previous_window_title" ]]; then
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
