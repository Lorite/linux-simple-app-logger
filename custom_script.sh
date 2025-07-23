#!/bin/bash

on_new_activity() {
    local app_name="$1"
    local window_title="$2"
    local duration="$3"

    notify-send "New Activity Logged" "App: $app_name\nTitle: $window_title\nDuration: $duration seconds"
}