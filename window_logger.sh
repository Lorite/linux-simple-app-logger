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
    if declare -f on_finished_activity > /dev/null; then
        on_finished_activity "$previous_app_name" "$previous_window_title" "$duration" # user-defined external function call
    fi
    exit 0
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

    # These are now dynamic based on arguments
    readonly TODAY=$(date +"%Y-%m-%d")
    readonly OUTPUT_FILE="$OUTPUT_FOLDER/$TODAY/LORI_Activity_$TODAY.csv"

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
        local current_window_title
        current_window_title=$(get_window_title "$current_window_id" | tr -d '\n' | tr -d '\r' | sed 's/,/ /g')

        if [[ -n "$current_window_id" && ("$current_window_id" != "$previous_window_id" || "$current_window_title" != "$previous_window_title") ]]; then
            log_previous_activity
            if declare -f on_finished_activity > /dev/null; then
                on_finished_activity "$previous_app_name" "$previous_window_title" "$duration" # user-defined external function call
            fi

            previous_window_id="$current_window_id"
            previous_app_name=$(get_process_name "$current_window_id")
            previous_window_title=$current_window_title
            start_time=$(date +%s)
            if declare -f on_new_activity > /dev/null; then
                on_new_activity "$previous_app_name" "$previous_window_title" # user-defined external function call
            fi
        fi

        on_loop_interval # user-defined external function call

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

# Global variables for cleanup handler
previous_window_id=""
previous_window_title=""
previous_app_name=""
start_time=0

check_dependencies

main "$@"
