# Window Activity Logger

A simple Bash script to monitor and log active window information on a Linux desktop environment. It records the application name, window title, and the duration each window is active, saving the data into a daily CSV file.

## Features

- Logs the process name of the active application.
- Logs the title of the active window.
- Calculates and records the duration of time spent on each window.
- Outputs data to a CSV file, organized by date.
- Configurable output directory via an environment variable.
- Blacklists specific processes to avoid logging them using a regex pattern.
- Blacklists specific window titles to avoid logging them using a regex pattern.
- Gracefully handles script termination (`Ctrl+C`) to log the final activity.

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

### Configuration

By default, the script saves the log files in a folder named after the current date within the same directory where the script is located.

You can customize the output folder by setting the `LINUX_SIMPLE_APP_LOGGER_LOGS_FOLDER` environment variable.
There are some other settings you can adjust in the script, such as `SLEEP_INTERVAL` and `MIN_LOG_DURATION`, which control how often the script checks for active windows and the minimum duration for logging an activity, respectively. I can make them adjustable via environment variables as well if you prefer.

```bash
export LINUX_SIMPLE_APP_LOGGER_LOGS_FOLDER="/home/user/my-activity-logs"
./window_logger.sh
```

## Output Format

The script generates a CSV file named `LORI_Activity_YYYY-MM-DD.csv` inside the output folder.

The CSV file has the following columns:

- `App name`: The name of the process that owns the window (e.g., `brave`, `code`, `gnome-terminal`).
- `Window Title`: The title of the active window.
- `Date`: The date of the log entry (`MM/DD/YY`).
- `Time`: The time the window became inactive (`HH:MM:SS`).
- `Duration`: The total time the window was active (`HH:MM:SS`).

### Example

###

```csv
"ptyxis"," ./window_logger.sh","07/23/25","00:06:26","00:00:05"
"brave"," linux show the current opened window binary name - Buscar con Google - Brave","07/23/25","00:06:41","00:00:15"
"nemo"," daily - /home/lori/git/lorite-obsidian-notes/_android-appusage/LaptopITU/daily","07/23/25","00:06:46","00:00:05"
"obsidian"," Linux App Logger with Automate and STT - lorite-obsidian-notes - Obsidian v1.8.10","07/23/25","00:07:06","00:00:20"
^C
Stopping window logger.
"ptyxis"," ./window_logger.sh","07/23/25","00:07:17","00:00:11"
```

which corresponds to the following table:

| App name | Window Title                                                                      | Date     | Time     | Duration |
| -------- | --------------------------------------------------------------------------------- | -------- | -------- | -------- |
| ptyxis   | ./window_logger.sh                                                                | 07/23/25 | 00:06:26 | 00:00:05 |
| brave    | linux show the current opened window binary name - Buscar con Google - Brave      | 07/23/25 | 00:06:41 | 00:00:15 |
| nemo     | daily - /home/lori/git/lorite-obsidian-notes/\_android-appusage/LaptopITU/daily   | 07/23/25 | 00:06:46 | 00:00:05 |
| obsidian | Linux App Logger with Automate and STT - lorite-obsidian-notes - Obsidian v1.8.10 | 07/23/25 | 00:07:06 | 00:00:20 |
| ptyxis   | ./window_logger.sh                                                                | 07/23/25 | 00:07:17 | 00:00:11 |
