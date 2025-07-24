#!/bin/bash

# This is an example of a custom script that can be used with the window_logger.sh script.
# It is sourced by the main script and can be used to define custom functions that are called
# at different points in the main script's execution.

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
    echo "Custom script: New activity detected: $app_name - $window_title"
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
    echo "Custom script: Finished activity: $app_name - $window_title (duration: $duration seconds)"
}

# on_loop_interval
#
# This function is called on each loop interval of the main script.
#
# @param 1: The name of the current application.
# @param 2: The title of the current window.
#
on_loop_interval() {
    local current_app_name="$1"
    local current_window_title="$2"
    # This function is called on each loop interval.
    # You can add any custom logic here that you want to be executed periodically.
    # For example, you could check for idle time, send a notification, etc.
    echo "Custom script: Loop interval tick. Current window: $current_app_name - $current_window_title"
}

# on_cleanup
#
# This function is called when the script is about to exit.
#
on_cleanup() {
    echo "Custom script: Cleaning up before exit."
}
