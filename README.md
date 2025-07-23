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

### Configuration

You can configure the script's behavior using command-line arguments.

| Argument                | Description                                                              | Default |
| ----------------------- | ------------------------------------------------------------------------ | ------- |
| `-o`, `--output-folder`   | Set the output folder for logs.                                          | `.`     |
| `-s`, `--sleep-interval`  | Set the sleep interval in seconds.                                       | `1`     |
| `-m`, `--min-log-duration`| Set the minimum duration for an activity to be logged.                   | `2`     |
| `-p`, `--process-blacklist`| Regex to match process names to ignore.                                  | `""`    |
| `-w`, `--window-blacklist`| Regex to match window titles to ignore.                                  | `""`    |
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
