# Window Activity Logger

A simple Bash script to monitor and log active window information on a Linux desktop environment. It records the application name, window title, and the duration each window is active, saving the data into a daily CSV file.

## Features

- Logs the process name of the active application.
- Logs the title of the active window.
- Calculates and records the duration of time spent on each window.
- Outputs data to a CSV file, organized by date.
- Configuration via command-line arguments.
- Blacklists specific processes and/or window titles to avoid logging them using a regex pattern.
- Gracefully handles script termination (`Ctrl+C`) to log the final activity.
- Tab completion for command-line arguments.

## Dependencies

This script relies on two command-line utilities that interact with the X11 windowing system.

- `xdotool`: To get the ID of the active window.
- `xprop`: To get window properties like title and process ID (PID).

## Installation

1.  **Install Dependencies:**
    You need to install `xdotool` and `xprop`. `xprop` is usually included in the `x11-utils` package.

    - On Debian/Ubuntu-based systems:
      ```bash
      sudo apt-get update
      sudo apt-get install xdotool x11-utils
      ```
    - On Fedora/CentOS/RHEL-based systems:
      ```bash
      sudo dnf install xdotool xprop
      ```
    - On Arch Linux-based systems:
      ```bash
      sudo pacman -S xdotool xorg-xprop
      ```

2.  **Make the script executable:**
    ```bash
    chmod +x window_logger.sh
    ```

## Usage

To start logging your window activity, simply run the script from your terminal:

```bash
./window_logger.sh
```

The script will print a message indicating that it has started and where it is logging the data.

To stop the logger, press `Ctrl+C` in the terminal where the script is running.

For a full list of options, you can use the `--help` flag:

```bash
./window_logger.sh --help
```

### Running on Startup

To have the logger start automatically when you log in to your desktop, you can add it to your system's startup applications. The exact steps may vary depending on your desktop environment, but here is a general guide that works for most environments.

**1. Create a `.desktop` file**

Create a file named `window-logger.desktop` in `~/.config/autostart/` with the following content. Make sure to replace `/path/to/window_logger.sh` with the absolute path to the `window_logger.sh` script.

```ini
[Desktop Entry]
Name=Window Activity Logger
Comment=Log active window information
Exec=/path/to/window_logger.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
```

You can also add any command-line arguments to the `Exec` line. For example:

```ini
Exec=/path/to/window_logger.sh -o /home/user/activity-logs -s 5
```

**2. Make the `.desktop` file executable**

Some systems may require the `.desktop` file to be executable:

```bash
chmod +x ~/.config/autostart/window-logger.desktop
```

Now, the script should start automatically the next time you log in.

**GNOME Desktop Environment**

If you are using GNOME, you can also use the "Startup Applications" tool:
1.  Open "Startup Applications" (you can search for it in the Activities overview).
2.  Click "Add".
3.  Fill in the details:
    -   **Name:** Window Activity Logger
    -   **Command:** `/path/to/window_logger.sh` (with any arguments you need)
    -   **Comment:** Log active window information
4.  Click "Add".

### Configuration

You can configure the script's behavior using command-line arguments.

| Argument                | Description                                                              | Default |
| ----------------------- | ------------------------------------------------------------------------ | ------- |
| `-o`, `--output-folder`   | Set the output folder for logs.                                          | `.`     |
| `-s`, `--sleep-interval`  | Set the sleep interval in seconds.                                       | `1`     |
| `-m`, `--min-log-duration`| Set the minimum duration for an activity to be logged.                   | `2`     |
| `-p`, `--process-blacklist`| Regex to match process names to ignore.                                  | `""`    |
| `-w`, `--window-blacklist`| Regex to match window titles to ignore.                                  | `""`    |
| `-c`, `--custom-script`   | Path to a custom script file to source.                                  | `""`    |
| `-h`, `--help`            | Show the help message.                                                   |         |

#### Example

Here is an example of how to run the script with custom settings:

```bash
./window_logger.sh -o ~/activity-logs -s 5 -m 10 -p "gnome-shell|plank" -w "Brave"
```

This command will:
- Save logs to the `~/activity-logs` directory.
- Check for the active window every `5` seconds.
- Only log activities that last longer than `10` seconds.
- Ignore any activity from processes named `gnome-shell` or `plank`.
- Ignore any window with "Brave" in its title.

### Custom Script

You can extend the logger's functionality by providing a custom script file using the `-c` or `--custom-script` argument. This script will be sourced at startup.

If the custom script defines a function named `on_finished_activity`, this function will be called every time a new activity is logged. The function will receive three arguments:

*   `app_name`: The name of the application (e.g., "Brave").
*   `window_title`: The title of the window.
*   `duration`: The duration of the activity in seconds.

#### Example Custom Script

Here is an example of a `custom_script.sh` that sends a notification whenever a new activity is logged:

```bash
#!/bin/bash

on_finished_activity() {
    local app_name="$1"
    local window_title="$2"
    local duration="$3"

    notify-send "New Activity Logged" "App: $app_name\nTitle: $window_title\nDuration: $duration seconds"
}
```

You would run the main script like this:

```bash
./window_logger.sh -c /path/to/custom_script.sh
```

Feel free to copy the example custom script above into your own file and modify it to suit your needs. I git ignored "my_custom_script.sh" so you can create your own without worrying about it being tracked by Git.

## Output Format

The script generates a CSV file named `LORI_Activity_YYYY-MM-DD.csv` inside the output folder.

The CSV file has the following columns:

- `App name`: The name of the process that owns the window (e.g., `brave`, `code`, `gnome-terminal`).
- `Window Title`: The title of the active window.
- `Date`: The date of the log entry (`YYYY-MM-DD`).
- `Time`: The time the window became inactive (`HH:MM:SS`).
- `Duration`: The total time the window was active (`HH:MM:SS`).

### Example

```csv
"ptyxis"," ./window_logger.sh","2025-07-23","00:06:26","00:00:05"
"brave"," linux show the current opened window binary name - Buscar con Google - Brave","2025-07-23","00:06:41","00:00:15"
"nemo"," daily - /home/lori/git/lorite-obsidian-notes/_android-appusage/LaptopITU/daily","2025-07-23","00:06:46","00:00:05"
"obsidian"," Linux App Logger with Automate and STT - lorite-obsidian-notes - Obsidian v1.8.10","2025-07-23","00:07:06","00:00:20"
^C
Stopping window logger.
"ptyxis"," ./window_logger.sh","2025-07-23","00:07:17","00:00:11"
```

which corresponds to the following table:

| App name | Window Title                                                                      | Date       | Time     | Duration |
| -------- | --------------------------------------------------------------------------------- | ---------- | -------- | -------- |
| ptyxis   | ./window_logger.sh                                                                | 2025-07-23 | 00:06:26 | 00:00:05 |
| brave    | linux show the current opened window binary name - Buscar con Google - Brave      | 2025-07-23 | 00:06:41 | 00:00:15 |
| nemo     | daily - /home/lori/git/lorite-obsidian-notes/_android-appusage/LaptopITU/daily      | 2025-07-23 | 00:06:46 | 00:00:05 |
| obsidian | Linux App Logger with Automate and STT - lorite-obsidian-notes - Obsidian v1.8.10 | 2025-07-23 | 00:07:06 | 00:00:20 |
| ptyxis   | ./window_logger.sh                                                                | 2025-07-23 | 00:07:17 | 00:00:11 |
