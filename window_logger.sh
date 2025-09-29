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
    if [[ "$(playerctl status 2>/dev/null)" == "Playing" ]]; then
        local current_media_comment
        current_media_comment=$(fetch_media_title)

        if [[ "$current_media_comment" != "$previous_media_comment" ]]; then
            if [[ -n "$previous_media_comment" ]]; then
                if declare -f on_finished_activity > /dev/null; then
                    on_finished_activity "Media" "$previous_media_comment" 0
                fi
            fi

            if declare -f on_new_activity > /dev/null; then
                on_new_activity "Media" "$current_media_comment"
            fi
            previous_media_comment="$current_media_comment"
        fi
    else
        if [[ -n "$previous_media_comment" ]]; then
            if declare -f on_finished_activity > /dev/null; then
                on_finished_activity "Media" "$previous_media_comment" 0
            fi
        fi
        previous_media_comment=""
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
    # Produces a summary CSV in today's folder with overall and top-app stats
    local today folder summary_file
    today=$(date +"%Y-%m-%d")
    folder="$OUTPUT_FOLDER/$today"
    mkdir -p "$folder"
    summary_file="$folder/LORI_DailyUsage_$today.csv"

    # Totals (seconds)
    local total_today=0 total_7=0 total_30=0
    # Counts (activity switches / sessions)
    local count_today=0 count_7=0 count_30=0

    # Per-app (today only) associative arrays
    declare -A app_duration
    declare -A app_count

    # Helper: parse one CSV log file
    parse_log_file() {
        local file="$1" day_index="$2"
        # Skip if file missing
        [[ ! -f "$file" ]] && return 0
        # Read lines, skipping header. Use awk for robust CSV parsing.
        while IFS=';' read -r app_name duration_field; do
            # Basic validation
            if [[ -z "$app_name" || -z "$duration_field" ]]; then
                continue
            fi

            # Parse H:MM:SS or HH:MM:SS
            IFS=':' read -r dh dm ds <<<"$duration_field"
            # Basic validation
            [[ -z "$dh" || -z "$dm" || -z "$ds" ]] && continue
            # Remove possible leading/trailing spaces
            dh=${dh//[!0-9]/}; dm=${dm//[!0-9]/}; ds=${ds//[!0-9]/}
            local secs=$((10#$dh*3600 + 10#$dm*60 + 10#$ds))
            # Update period totals & counts
            if (( day_index == 0 )); then
                total_today=$((total_today + secs))
                count_today=$((count_today + 1))
                # Per-app only for today
                app_duration["$app_name"]=$(( ${app_duration["$app_name"]:-0} + secs ))
                app_count["$app_name"]=$(( ${app_count["$app_name"]:-0} + 1 ))
            fi
            if (( day_index < 7 )); then
                total_7=$((total_7 + secs))
                count_7=$((count_7 + 1))
            fi
            if (( day_index < 30 )); then
                total_30=$((total_30 + secs))
                count_30=$((count_30 + 1))
            fi
        done < <(awk -F'"' 'NR > 1 && NF >= 9 {
            app_name = $2
            duration = $10
            print app_name ";" duration
        }' "$file")
    }

    # Iterate over the last 30 days (0 = today)
    local i date_str file_path
    for i in $(seq 0 29); do
        date_str=$(date -d "-$i day" +"%Y-%m-%d" 2>/dev/null || date +"%Y-%m-%d")
        file_path="$OUTPUT_FOLDER/$date_str/LORI_Activity_$date_str.csv"
        parse_log_file "$file_path" "$i"
    done

    # Format durations for summary (no leading zero on hours)
    format_duration_summary() {
        local t=$1
        local h=$((t / 3600))
        local m=$(((t % 3600) / 60))
        local s=$((t % 60))
        printf "%d:%02d:%02d" "$h" "$m" "$s"
    }

    local today_hms seven_hms thirty_hms avg7_hms avg30_hms
    today_hms=$(format_duration_summary $total_today)
    seven_hms=$(format_duration_summary $total_7)
    thirty_hms=$(format_duration_summary $total_30)
    avg7_hms=$(format_duration_summary $(( total_7 / 7 )))
    avg30_hms=$(format_duration_summary $(( total_30 / 30 )))

    local avg7_count=$(( count_7 / 7 ))
    local avg30_count=$(( count_30 / 30 ))

    # Human-readable date M/D/YY (no leading zeros) for first summary line
    local human_today
    human_today=$(date +"%-m/%-d/%y" 2>/dev/null || date +"%m/%d/%y")
    # If % -m not supported (busybox), fall back & trim leading zeros
    human_today=${human_today#0}; human_today=${human_today/\/0/\/} # minimal cleanup

    # Build top apps list (today)
    local TOP_N=10
    local sorted_apps tmpfile
    tmpfile=$(mktemp)
    for app in "${!app_duration[@]}"; do
        echo -e "${app}\t${app_duration[$app]}\t${app_count[$app]}" >> "$tmpfile"
    done
    if [[ -s "$tmpfile" ]]; then
        sorted_apps=$(sort -t $'\t' -k2,2nr "$tmpfile" | head -n $TOP_N)
    else
        sorted_apps=""
    fi
    rm -f "$tmpfile"

    {
        echo '"Summary","Usage time","Access count"'
        echo "\"$human_today\",\"$today_hms\",\"$count_today\""
        echo '"Last 7 days","'$seven_hms'","'$count_7'"'
        echo '"Last 7 days (average)","'$avg7_hms'","'$avg7_count'"'
        echo '"Last 30 days","'$thirty_hms'","'$count_30'"'
        echo '"Last 30 days (average)","'$avg30_hms'","'$avg30_count'"'
        echo '""' # blank line (empty quoted field)
        echo '"Top apps","Usage time","","Access count"'
        if [[ -n "$sorted_apps" ]]; then
            while IFS=$'\t' read -r app secs cnt; do
                local hms
                hms=$(format_duration_summary "$secs")
                # Escape quotes in app name for CSV
                local app_csv=${app//'"'/'""'}
                echo "\"$app_csv\",\"$hms\",\"$cnt\""
            done <<< "$sorted_apps"
        fi
        echo '""' # final blank line for symmetry (optional)
    } > "$summary_file"
    echo "Summary statistics written to '$summary_file'."
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

check_dependencies

main "$@"
