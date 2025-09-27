#!/bin/bash

# This is an example of a custom script that can be used with the window_logger.sh script.
# It is sourced by the main script and can be used to define custom functions that are called
# at different points in the main script's execution.

# --- Configuration ---
ACTIVITY_PERCENTAGE_THRESHOLD=50 # Stop activity if active for less than this percentage
declare -A running_activities

# --- Helper Functions ---

# get_activity_info
#
# This function determines the extra activity name and record comment based on the app name and window title.
# It returns two lines: the first is the activity name, and the second is the record comment.
#
# @param 1: The name of the application.
# @param 2: The title of the window.
#
get_activity_info() {
    local app_name="$1"
    local window_title="$2"
    local activity=""
    local comment=""

    case "$app_name" in
        "Media")
            activity="YouTube"
            comment="$window_title"
            ;;
        "firefox"|"chrome"|"brave")
            if [[ "$window_title" == *"YouTube - "* ]]; then
                activity=""
            elif [[ "$window_title" == *"Outlook - "* || "$window_title" == *"Gmail - "* ]]; then
                activity="Email"
            elif [[ "$window_title" == *"Google Docs"* ]]; then
                activity="Write"
            elif [[ "$window_title" == *"Google Meet"* ]] || [[ "$window_title" == *"Zoom"* ]] || [[ "$window_title" == *"Teams"* ]]; then
                activity="Meeting"
            elif [[ "$window_title" == *"Google Keep - "* ]]; then
                activity="Take notes"
            else
                activity="Read"
                comment="Websites"
            fi
            ;;
        "okular"|"zathura"|"evince"|"zotero"|"Zotero")
            activity="Read"
            comment="Research"
            ;;
        "zoom"|"teams"|"skype")
            activity="Meeting"
            ;;
        "code"|"code-insiders"|"jetbrains-idea"|"emacs"|"vim"|"sublime_text"|"ptyxis")
            activity="Code"
            case "$app_name" in
                "code"|"code-insiders")     
                    comment="$(echo "$window_title" | awk -F' - ' '{print $2}')"
                ;;
                "ptyxis")
                    comment="Ptyxis Terminal"
                ;;
            esac
            ;;
        "obsidian"|"logseq"|"simplenote")
            activity="Take notes"
            case "$app_name" in
                "obsidian")
                    comment="Obsidian"
                    ;;
            esac
            ;;
        "libreoffice-writer")
            activity="Write"
            ;;
        "spotify")
            activity="Music"
            comment="Spotify"
            ;;
    esac

    printf "%s\n%s" "$activity" "$comment"
}

build_add_record_json_payload() {
    local app_name="$1"
    local window_title="$2"
    local start_time="$3"
    local end_time="$4"

    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')
    local extra_record_comment
    extra_record_comment=$(echo "$activity_info" | sed -n '2p')

    # Format times as 'YYYY-MM-DD HH:MM:SS' (remove 'T' and timezone offset)
    local start_time_iso
    start_time_iso=$(date -d "@$start_time" +"%Y-%m-%d %H:%M:%S")
    local end_time_iso
    end_time_iso=$(date -d "@$end_time" +"%Y-%m-%d %H:%M:%S")

    local payload_json
    payload_json=$(printf '{"action": "add_record", "extra_activity_name": "%s", "extra_record_comment": "%s", "extra_record_time_started": "%s", "extra_record_time_ended": "%s"}' \
        "$extra_activity_name" "$extra_record_comment" "$start_time_iso" "$end_time_iso")

    build_notification_json "$payload_json"
}

build_notification_json() {
    local payload_json="$1"
    printf '{
      "secret": "%s",
      "to": "%s",
      "device": "%s",
      "priority": "normal",
      "payload": %s
    }' "$AUTOMATE_ANDROID_APP_SECRET" "$AUTOMATE_ANDROID_APP_TO" "$AUTOMATE_ANDROID_APP_DEVICE" "$payload_json"
}

# send_notification
#
# This function sends a notification with the given JSON payload.
#
# @param 1: The JSON payload.
#
send_notification() {
    local json_payload="$1"
    # echo "$json_payload" >&2

    curl -X POST -H "Content-Type: application/json" \
    -d "$json_payload" \
    https://llamalab.com/automate/cloud/message
}

# --- Custom Functions ---

# on_new_activity
#
# This function is called when a new activity is started.
#
# @param 1: The name of the new application.
# @param 2: The title of the new window.
#
on_new_activity() {
    local app_name="$1"
    local window_title="$2"
    echo "New activity: $app_name - $window_title"

    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')

    if [[ -z "$extra_activity_name" ]]; then
        return
    fi

    if [[ -z "${running_activities[$extra_activity_name]}" ]]; then
        echo "Starting new activity group: $extra_activity_name"
        # Store start time and initialize active duration
        local start_time
        start_time=$(date +%s)
        running_activities["$extra_activity_name"]="$start_time:0"
    fi
}

# on_finished_activity
#
# This function is called when an activity is finished.
#
# @param 1: The name of the application that was running.
# @param 2: The title of the window that was active.
# @param 3: The duration of the activity in seconds.
#
on_finished_activity() {
    local app_name="$1"
    local window_title="$2"
    local duration="$3"
    echo "Finished activity: $app_name - $window_title (duration: $duration seconds)"

    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')

    if [[ -z "$extra_activity_name" ]]; then
        return
    fi

    if [[ -n "${running_activities[$extra_activity_name]}" ]]; then
        local state_data="${running_activities[$extra_activity_name]}"
        local start_time="${state_data%%:*}"
        local active_duration="${state_data##*:}"
        
        local new_duration=$((active_duration + duration))
        running_activities["$extra_activity_name"]="$start_time:$new_duration"
    fi
}

stop_activity() {
    local activity_name="$1"
    local end_time="$2"

    local state_data="${running_activities[$activity_name]}"
    local start_time="${state_data%%:*}"
    
    # only build the json if more than 2 minutes and 30 seconds of activity
    local active_duration="${state_data##*:}"
    if (( active_duration < 150 )); then
        echo "Activity '$activity_name' active duration ($active_duration seconds) is less than threshold. Not logging."
        unset "running_activities[$activity_name]"
        return
    fi

    # Build the JSON payload and send the notification
    local json_payload
    json_payload=$(build_add_record_json_payload "" "" "$start_time" "$end_time")
    # Manually set the activity name in the payload
    json_payload=$(echo "$json_payload" | sed "s/\"extra_activity_name\": \"\"/\"extra_activity_name\": \"$activity_name\"/")

    send_notification "$json_payload"
    unset "running_activities[$activity_name]"
}

# on_loop_interval
#
# This function is called on each loop interval of the main script.
#
on_loop_interval() {
    local current_app_name="$1"
    local current_window_title="$2"
    local current_time
    current_time=$(date +%s)

    local current_activity_info
    current_activity_info=$(get_activity_info "$current_app_name" "$current_window_title")
    local current_extra_activity_name
    current_extra_activity_name=$(echo "$current_activity_info" | sed -n '1p')

    for activity_name in "${!running_activities[@]}"; do
        # If the activity is the current one, skip the check
        if [[ "$activity_name" == "$current_extra_activity_name" ]]; then
            continue
        fi

        local state_data="${running_activities[$activity_name]}"
        local start_time="${state_data%%:*}"
        local active_duration="${state_data##*:}"

        local total_elapsed_time=$((current_time - start_time))

        if (( total_elapsed_time > 0 )); then
            local active_percentage=$(( (active_duration * 100) / total_elapsed_time ))

            if (( active_percentage < ACTIVITY_PERCENTAGE_THRESHOLD )); then
                echo "Stopping activity '$activity_name' due to low activity percentage ($active_percentage%)."
                stop_activity "$activity_name" "$current_time"
            fi
        fi
    done
}

on_cleanup() {
    echo "Cleaning up and stopping all activities."
    local end_time
    end_time=$(date +%s)
    for activity_name in "${!running_activities[@]}"; do
        echo "Stopping activity '$activity_name' on cleanup."
        stop_activity "$activity_name" "$end_time"
    done
}
