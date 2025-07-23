#!/bin/bash

# --- Configuration ---

readonly OUTPUT_FOLDER="${LINUX_SIMPLE_APP_LOGGER_LOGS_FOLDER:-.}"
readonly TODAY=$(date +"%Y-%m-%d")
readonly OUTPUT_FILE="$OUTPUT_FOLDER/$TODAY/LORI_Activity_$TODAY.csv"
readonly SLEEP_INTERVAL=1 # in seconds
readonly MIN_LOG_DURATION=2 # in seconds
readonly PROCESS_BLACKLIST_REGEX="" # Regex to match process names to ignore, e.g., "gnome-shell|plank"
readonly WINDOW_BLACKLIST_REGEX=""    # Regex to match window titles to ignore, e.g., "Brave"

# --- Functions ---

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
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        mkdir -p "$(dirname "$OUTPUT_FILE")"
        echo "\"App name\",\"Window Title\",\"Date\",\"Time\",\"Duration\"" >"$OUTPUT_FILE"
    fi
}

get_active_window_id() {
    xdotool getactivewindow 2>/dev/null
}

get_window_title() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        return 1
    fi
    xprop -id "$window_id" WM_NAME 2>/dev/null | cut -d '=' -f 2 | sed 's/"//g'
}

get_process_name() {
    local window_id="$1"
    if [[ -z "$window_id" ]]; then
        return 1
    fi
    xprop -id "$window_id" _NET_WM_PID 2>/dev/null | cut -d '=' -f 2 | xargs -I {} ps -p {} -o comm= | tr -d '\n' | tr -d '\r' | sed 's/,/ /g'
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

        if [[ $duration -gt $MIN_LOG_DURATION ]]; then
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

    date=$(date +"%Y-%m-%d")
    time=$(date +"%H:%M:%S")

    duration_formatted=$(format_duration "$duration_seconds")

    # Check if the output file exists, if not, create it with a header row
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        echo "\"App name\",\"Window Title\",\"Date\",\"Time\",\"Duration\"" >"$OUTPUT_FILE"
    fi

    echo "\"$app_name\",\"$window_title\",\"$date\",\"$time\",\"$duration_formatted\"" | tee -a "$OUTPUT_FILE"
}

cleanup() {
    echo -e "\nStopping window logger."
    # Log the duration of the last activity before exiting
    log_previous_activity
    exit 0
}

# --- Main Logic ---

main() {
    # Initialize with the current active window at script start
    previous_window_id=$(get_active_window_id)
    previous_window_title=$(get_window_title "$previous_window_id" | tr -d '\n' | tr -d '\r' | sed 's/,/ /g')
    previous_app_name=$(get_process_name "$previous_window_id")
    start_time=$(date +%s)

    check_output_folder

    check_file_exists_and_create

    echo "Starting window logger. Logging to $OUTPUT_FILE. Press Ctrl+C to stop."

    while true; do
        local current_window_id
        current_window_id=$(get_active_window_id)

        if [[ -n "$current_window_id" && "$current_window_id" != "$previous_window_id" ]]; then
            log_previous_activity

            previous_window_id="$current_window_id"
            previous_app_name=$(get_process_name "$current_window_id")
            previous_window_title=$(get_window_title "$current_window_id" | tr -d '\n' | tr -d '\r' | sed 's/,/ /g')
            start_time=$(date +%s)
        fi

        sleep "$SLEEP_INTERVAL"
    done
}

# --- Script Execution ---

trap cleanup SIGINT SIGTERM

# Global variables for cleanup handler
previous_window_id=""
previous_window_title=""
previous_app_name=""
start_time=0

check_dependencies

main
