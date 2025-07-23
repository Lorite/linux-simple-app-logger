#!/bin/bash

# This is an example of a custom script that can be used with the window_logger.sh script.
# It is sourced by the main script and can be used to define custom functions that are called
# at different points in the main script's execution.

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
        "firefox"|"chrome"|"brave")
            if [[ "$window_title" == *"YouTube"* ]]; then
                activity="YouTube"
            elif [[ "$window_title" == *"Outlook"* || "$window_title" == *"Gmail"* ]]; then
                activity="Email"
            elif [[ "$window_title" == *"Google Docs"* ]]; then
                activity="Write"
            elif [[ "$window_title" == *"Google Meet"* ]] || [[ "$window_title" == *"Zoom"* ]] || [[ "$window_title" == *"Teams"* ]]; then
                activity="Meeting"
            elif [[ "$window_title" == *"Google Keep"* ]]; then
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

    # echo "Found activity: $activity and comment: $comment for app: $app_name and window: $window_title" >&2
    printf "%s\n%s" "$activity" "$comment"
}

# build_json_payload
#
# This function builds the JSON payload for the notification.
#
# @param 1: The action (e.g., "start", "finish").
# @param 2: The name of the application.
# @param 3: The title of the window.
# @param 4: The duration of the activity in seconds (optional).
#
build_json_payload() {
    local action="$1"
    local app_name="$2"
    local window_title="$3"
    # echo "Building JSON payload for action: $action, app: $app_name, window: $window_title" >&2

    local activity_info
    activity_info=$(get_activity_info "$app_name" "$window_title")
    local extra_activity_name
    extra_activity_name=$(echo "$activity_info" | sed -n '1p')
    local extra_record_comment
    extra_record_comment=$(echo "$activity_info" | sed -n '2p')

    local payload_json
    payload_json=$(printf '{"action": "%s", "extra_activity_name": "%s", "extra_record_comment": "%s"}' "$action" "$extra_activity_name" "$extra_record_comment")

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

    # curl -X POST -H "Content-Type: application/json" \
    # -d "$json_payload" \
    # https://llamalab.com/automate/cloud/message
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

    local json_payload
    json_payload="$(build_json_payload "start" "$app_name" "$window_title")"
    echo "$json_payload" >&2

    send_notification "$json_payload"
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

    local json_payload
    json_payload=$(build_json_payload "stop" "$app_name" "$window_title")

    send_notification "$json_payload"
}
