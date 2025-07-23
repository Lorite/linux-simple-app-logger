#!/bin/bash

on_finished_activity() {
    local app_name="$1"
    local window_title="$2"
    local duration="$3"

    # Example: Print a message to the console
    echo "Finished activity: $app_name - $window_title (Duration: $duration seconds)"

    # Example: Send a notification
    # notify-send "Finished activity" "$app_name - $window_title (Duration: $duration seconds)"
}