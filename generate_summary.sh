#!/bin/bash

# --- Configuration ---
OUTPUT_FOLDER="."

# --- Functions ---

usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -o, --output-folder FOLDER      Set the output folder where logs are stored. Default is '.'."
    echo "  -h, --help                      Show this help message."
    exit 0
}

check_output_folder() {
    if [[ ! -d "$OUTPUT_FOLDER" ]]; then
        echo "Error: Output folder '$OUTPUT_FOLDER' does not exist." >&2
        exit 1
    fi
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

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -o|--output-folder)
            OUTPUT_FOLDER="$2"
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

check_output_folder
calculate_todays_most_used_apps