#!/bin/bash

# This is an example of a custom script that can be used with the window_logger.sh script.
# It is sourced by the main script and can be used to define custom functions that are called
# at different points in the main script's execution.

# --- Configuration ---
# Grace-period ("slack") configuration for when to stop an inactive activity.
# Slack grows sublinearly with the activity's active duration using:
#   slack_minutes = SLACK_COEFF * (active_minutes ^ SLACK_EXPONENT)
# Example targets: 5 min → ~2 min slack, 60 min → ~5 min slack when EXPONENT≈0.369 and COEFF≈1.0
SLACK_EXPONENT=${SLACK_EXPONENT:-0.369}
SLACK_COEFF=${SLACK_COEFF:-1.0}
# Clamp slack in seconds to avoid too small/large waits
SLACK_MIN_SECONDS=${SLACK_MIN_SECONDS:-60}   # floor: 1 minute
SLACK_MAX_SECONDS=${SLACK_MAX_SECONDS:-900}  # ceil: 15 minutes
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
        "YouTube"|"Media")
            activity="YouTube"
            comment="$window_title"
            ;;
        "firefox"|"chrome"|"brave")
            # if [[ "$window_title" == *"YouTube - "* ]]; then
            #     activity="YouTube"
            if [[ "$window_title" == *"Outlook - "* || "$window_title" == *"Gmail - "* ]]; then
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
                    # Do not include window title for VS Code
                    comment="VS Code"
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

build_start_json_payload() {
    local app_name="$1"
    local window_title="$2"
    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')
    local extra_record_comment
    extra_record_comment=$(echo "$activity_info" | sed -n '2p')

    local payload_json
    payload_json=$(printf '{"action": "start", "extra_activity_name": "%s", "extra_record_comment": "%s"}' \
        "$extra_activity_name" "$extra_record_comment")

    build_notification_json "$payload_json"
}

build_stop_json_payload() {
    local app_name="$1"
    local window_title="$2"

    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')
    local extra_record_comment
    extra_record_comment=$(echo "$activity_info" | sed -n '2p')

    local payload_json
    payload_json=$(printf '{"action": "stop", "extra_activity_name": "%s", "extra_record_comment": "%s"}' \
        "$extra_activity_name" "$extra_record_comment")

    build_notification_json "$payload_json"
}

build_add_record_json_payload() {
    local activity_name="$1"
    local window_title="$2"
    local start_time="$3"
    local end_time="$4"
    local app_name="$5"  # originating application name

    # Compute comment using the actual app and title
    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')
    local extra_record_comment
    extra_record_comment=$(echo "$activity_info" | sed -n '2p')

    # If comment is empty, avoid window title for VS Code/Obsidian, else use title
    if [[ -z "$extra_record_comment" ]]; then
        case "$app_name" in
            code|code-insiders)
                extra_record_comment="VS Code"
                ;;
            obsidian)
                extra_record_comment="Obsidian"
                ;;
            *)
                extra_record_comment="$window_title"
                ;;
        esac
    fi

    # Format times as 'YYYY-MM-DD HH:MM:SS'
    local start_time_iso
    start_time_iso=$(date -d "@$start_time" +"%Y-%m-%d %H:%M:%S")
    local end_time_iso
    end_time_iso=$(date -d "@$end_time" +"%Y-%m-%d %H:%M:%S")

    local payload_json
    payload_json=$(printf '{"action": "add_record", "extra_activity_name": "%s", "extra_record_comment": "%s", "extra_record_time_started": "%s", "extra_record_time_ended": "%s"}' \
        "$activity_name" "$extra_record_comment" "$start_time_iso" "$end_time_iso")

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

# slack_seconds_for_active_duration
#
# Compute slack (grace period) in seconds given an active duration in seconds.
# Formula (minutes domain): S(d) = SLACK_COEFF * d^SLACK_EXPONENT, then convert to seconds and clamp.
# Uses awk for exp()/log() to avoid extra dependencies.
slack_seconds_for_active_duration() {
    local active_sec="$1"
    local alpha="${SLACK_EXPONENT}"
    local coeff="${SLACK_COEFF}"
    local min_s="${SLACK_MIN_SECONDS}"
    local max_s="${SLACK_MAX_SECONDS}"

    # If duration is not positive, return minimum slack
    if [[ -z "$active_sec" || "$active_sec" -le 0 ]]; then
        echo "$min_s"
        return
    fi

    # Work in minutes for the power-law, then convert to seconds
    # slack_seconds = 60 * coeff * exp(alpha * ln(active_sec/60))
    local slack
    slack=$(awk -v s="${active_sec}" -v a="${alpha}" -v c="${coeff}" 'BEGIN {
        d = s/60.0; if (d <= 0) { print 0; exit }
        val = 60.0 * c * exp(a * log(d));
        print val;
    }')

    # Clamp and round to integer seconds
    local slack_int
    slack_int=$(awk -v x="${slack}" -v min="${min_s}" -v max="${max_s}" 'BEGIN {
        if (x < min) x = min; if (x > max) x = max; printf "%.0f", x;
    }')
    echo "$slack_int"
}

# send_notification
#
# This function sends a notification with the given JSON payload.
#
# @param 1: The JSON payload.
#
send_notification() {
    local json_payload="$1"
    # Queue file for offline messages (override with QUEUE_FILE env var if desired)
    local queue_file="${QUEUE_FILE:-/tmp/android_automate_queue.jsonl}"
    local lock_file="${queue_file}.lock"

    # Always queue the message first to preserve order
    local one_line_payload
    one_line_payload=$(echo "$json_payload" | tr '\n' ' ')
    echo "$one_line_payload" >> "$queue_file"
    echo "[offline-queue] Queued notification for sending: $queue_file (size: $(wc -l < "$queue_file"))" >&2

    # Check for lock file. If it exists, another sender is already running.
    if [ -f "$lock_file" ]; then
        echo "[background-sender] Sender process already running. Notification is queued."
        return 0
    fi

    # No lock file, so we can start a new background sender process.
    # The background process will handle the lock.
    _send_and_process_queue_background "$queue_file" "$lock_file" &
}

# _send_and_process_queue_background
#
# This is the background worker function that sends all queued notifications.
# It uses a lock file to ensure only one instance runs at a time.
#
# @param 1: The queue file path.
# @param 2: The lock file path.
#
_send_and_process_queue_background() {
    local queue_file="$1"
    local lock_file="$2"

    # Create the lock file
    touch "$lock_file"

    # Ensure the lock file is removed on exit
    trap 'rm -f "$lock_file"; echo "[background-sender] Sender process finished.";' EXIT

    echo "[background-sender] Starting to process notification queue."

    # Use a temp file to store any still-failing payloads
    local tmp_file
    tmp_file=$(mktemp "${queue_file}.XXXX") || return 1

    local line kept_any=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Attempt to send the current notification (with lightweight retry)
        local attempt max_attempts=3 backoff=2
        local sent_successfully=0
        for attempt in $(seq 1 $max_attempts); do
            curl -s -S -X POST -H "Content-Type: application/json" \
                -d "$line" \
                https://llamalab.com/automate/cloud/message
            local curl_exit_code=$?

            if [[ $curl_exit_code -eq 0 ]]; then
                # Success
                echo "[background-sender] Notification sent successfully."
                sent_successfully=1
                sleep 15 # Wait for 15 seconds after a successful send
                break # Exit retry loop
            elif [[ $curl_exit_code -eq 6 ]]; then
                echo "[background-sender] curl DNS resolution failed (exit 6) on attempt $attempt/$max_attempts. Will retry." >&2
            else
                echo "[background-sender] curl failed with exit code $curl_exit_code on attempt $attempt/$max_attempts" >&2
            fi

            # Backoff before next attempt (except after last)
            if [[ $attempt -lt $max_attempts ]]; then
                sleep $backoff
            fi
        done

        if [[ $sent_successfully -eq 0 ]]; then
            # If we reach here, sending failed after retries. Keep the payload.
            echo "$line" >> "$tmp_file"
            kept_any=1
            echo "[background-sender] Failed to send notification after retries. Keeping it in the queue." >&2
        fi
    done < "$queue_file"

    # Replace original queue file with the temp file if any payloads were kept
    if [[ $kept_any -eq 1 ]]; then
        mv "$tmp_file" "$queue_file"
    else
        # If all were sent, remove both the temp file and the original queue file
        rm -f "$tmp_file" "$queue_file"
    fi

    # The trap will handle removing the lock file
}

# flush_queued_notifications
#
# This function is kept for compatibility but is no longer the primary mechanism.
# The background sender `_send_and_process_queue_background` handles the queue.
#
# @param 1: queue file path
flush_queued_notifications() {
    local queue_file="$1"
    local lock_file="${queue_file}.lock"

    # If the script is started and there's a queue but no sender, this can kick it off.
    if [[ -f "$queue_file" && ! -f "$lock_file" ]]; then
        echo "[flush] Found a queue file without a running sender. Starting background process."
        _send_and_process_queue_background "$queue_file" "$lock_file" &
    fi
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

    # Special-case: Media/YouTube is handled per-track; do not group in running_activities
    if [[ "$extra_activity_name" == "YouTube" ]]; then
        # We rely on on_finished_activity to emit a record for the exact played segment
        return
    fi

    if [[ -z "${running_activities[$extra_activity_name]}" ]]; then
        echo "Starting new activity group: $extra_activity_name with title '$window_title'"
        # Store start time, initialize active duration, and store the window title
        local start_time
        start_time=$(date +%s)
        # Store: start_time:active_duration:last_window_title:last_app_name
        running_activities["$extra_activity_name"]="$start_time:0:$window_title:$app_name"
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

    # Special-case: Media/YouTube segments are logged immediately per track
    if [[ "$extra_activity_name" == "YouTube" ]]; then
        local end_time now start_time
        now=$(date +%s)
        end_time="$now"
        start_time=$((now - duration))

        local json_payload
        json_payload=$(build_add_record_json_payload "YouTube" "$window_title" "$start_time" "$end_time" "$app_name")
        # Ensure activity name is exactly "YouTube"
        json_payload=$(echo "$json_payload" | sed "s/\"extra_activity_name\": \"[^\"]*\"/\"extra_activity_name\": \"YouTube\"/")
        send_notification "$json_payload"
        return
    fi

    if [[ -n "${running_activities[$extra_activity_name]}" ]]; then
        local state_data="${running_activities[$extra_activity_name]}"
        local start_time="${state_data%%:*}"
        local rest_after_start="${state_data#*:}"
        local active_duration="${rest_after_start%%:*}"
        local _rest_after_duration="${rest_after_start#*:}"
        # Update duration; set the last window title and last app name to the most recent values
        local new_duration=$((active_duration + duration))
        running_activities["$extra_activity_name"]="$start_time:$new_duration:$window_title:$app_name"
    fi
}

stop_activity() {
    local activity_name="$1"
    local end_time_now="$2"

    local state_data="${running_activities[$activity_name]}"
    local start_time="${state_data%%:*}"
    local rest_after_start="${state_data#*:}"
    local active_duration="${rest_after_start%%:*}"
    local rest_after_duration="${rest_after_start#*:}"
    local last_window_title="${rest_after_duration%%:*}"
    local last_app_name="${rest_after_duration#*:}"
    
    # only build the json if more than 2 minutes and 30 seconds of activity
    if (( active_duration < 150 )); then
        echo "Activity '$activity_name' active duration ($active_duration seconds) is less than threshold. Window title: '$last_window_title'. Not logging."
        unset "running_activities[$activity_name]"
        return
    fi

    # Use the actual last-active time as the record end_time, not the time we send/decide
    # last_active_end_time = start_time + active_duration
    local last_active_end_time=$((start_time + active_duration))
    # Calculate the effective start time so that duration = active_duration and
    # the interval ends at the last moment of activity (not at decision/send time)
    local effective_start_time=$((last_active_end_time - active_duration))

    # Build the JSON payload and send the notification
    local json_payload
    # Pass the activity name, last known window title, and originating app name
    json_payload=$(build_add_record_json_payload "$activity_name" "$last_window_title" "$effective_start_time" "$last_active_end_time" "$last_app_name")
    # Manually set the activity name in the payload, as it might be different from what get_activity_info returns
    json_payload=$(echo "$json_payload" | sed "s/\"extra_activity_name\": \"[^\"]*\"/\"extra_activity_name\": \"$activity_name\"/")

    send_notification "$json_payload"
    unset "running_activities[$activity_name]"
}

update_youtube_activity_duration() {
    local player_status
    player_status=$(playerctl status 2>/dev/null)

    if [[ "$player_status" == "Playing" && -n "${running_activities["YouTube"]}" ]]; then
        local state_data="${running_activities["YouTube"]}"
        local start_time="${state_data%%:*}"
        local rest_after_start="${state_data#*:}"
        local active_duration="${rest_after_start%%:*}"
        local rest_after_duration="${rest_after_start#*:}"
        local last_window_title="${rest_after_duration%%:*}"
        local last_app_name="${rest_after_duration#*:}"

        # Increment the duration by the sleep interval from the main script
        local new_duration=$((active_duration + 1)) # Assuming sleep interval is 1
        running_activities["YouTube"]="$start_time:$new_duration:$last_window_title:$last_app_name"
    fi
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

    update_youtube_activity_duration

    local player_status
    player_status=$(playerctl status 2>/dev/null)

    local current_activity_info
    current_activity_info=$(get_activity_info "$current_app_name" "$current_window_title")
    local current_extra_activity_name
    current_extra_activity_name=$(echo "$current_activity_info" | sed -n '1p')

    for activity_name in "${!running_activities[@]}"; do
        # If media is playing and the activity is YouTube, don't stop it.
        if [[ "$player_status" == "Playing" && "$activity_name" == "YouTube" ]]; then
            continue
        fi

        # If the activity is the current one, skip the check
        if [[ "$activity_name" == "$current_extra_activity_name" ]]; then
            continue
        fi

        local state_data="${running_activities[$activity_name]}"
        local start_time="${state_data%%:*}"
        local active_duration_and_title="${state_data#*:}"
        local active_duration="${active_duration_and_title%%:*}"

        # Idle time since last observed activity end
        # last_active_end = start_time + active_duration
        local last_active_end=$((start_time + active_duration))
        local idle_time=$((current_time - last_active_end))

        if (( idle_time > 0 )); then
            # Compute allowed slack based on how long the activity was active
            local slack_seconds
            slack_seconds=$(slack_seconds_for_active_duration "$active_duration")

            if (( idle_time > slack_seconds )); then
                echo "Stopping activity '$activity_name' after idle ${idle_time}s (slack ${slack_seconds}s)."
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
