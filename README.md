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
- **Extensible with custom scripts:** Allows for custom actions on activity changes through user-defined functions.

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

By default, it will look for a `custom_scripts/my_custom_script.sh` file. You can specify a different custom script using the `-c` or `--custom-script` flag:

```bash
./window_logger.sh -c custom_scripts/android_automate_app_cloud_message_script.sh
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

If the custom script defines functions like `on_new_activity`, `on_finished_activity`, `on_loop_interval`, or `on_cleanup`, these functions will be called at the appropriate times.

- `on_new_activity` is called when a new window becomes active. It receives two arguments:
    - `app_name`: The name of the new application.
    - `window_title`: The title of the new window.
- `on_finished_activity` is called every time a new activity is logged. The function will receive three arguments:
    - `app_name`: The name of the application (e.g., "Brave").
    - `window_title`: The title of the window.
    - `duration`: The duration of the activity in seconds.
- `on_loop_interval` is called on each loop interval of the main script.
- `on_cleanup` is called when the script is about to exit.

#### Example Custom Script

There is an example custom script named `custom_script.sh` in the `custom_scripts` directory. You can use it as a starting point for your own customizations. Feel free to copy the file to `my_custom_script.sh` and modify it as needed. It is not included in the repository by default, so you will need to create it yourself, and it is ignored by Git.

You would run the main script like this:

```bash
./window_logger.sh -c /path/to/custom_scripts/custom_script.sh
```

### Advanced Custom Script Example: Android Automate Integration

The `custom_scripts/android_automate_app_cloud_message_script.sh` provides a more advanced example of what can be done with custom scripts. It integrates with the [Automate](https://llamalab.com/automate/) Android application to send real-time activity updates to your phone.

#### Features

-   **Real-time Notifications**: Sends `start` and `stop` messages to Automate when you switch activities on your desktop.
-   **Activity Mapping**: Translates application names and window titles into meaningful activities (e.g., "Code", "Read", "Email", "Meeting").
-   **YouTube Tracking**: Detects when you are watching a YouTube video (in a browser) and sends specific updates for it.

#### Dependencies

-   `playerctl`: Required for the YouTube tracking feature. You can install it on Debian/Ubuntu with `sudo apt-get install playerctl`.

#### Setup

1.  **Configure Automate**: You need an Automate flow that can receive cloud messages. The script sends a JSON payload that your flow can parse.
2.  **Set Environment Variables**: The script requires the following environment variables to be set. You can add them to your `~/.bashrc` or `~/.zshrc` file.
    -   `AUTOMATE_ANDROID_APP_SECRET`: Your Automate cloud message secret.
    -   `AUTOMATE_ANDROID_APP_TO`: The recipient of the message (usually your email).
    -   `AUTOMATE_ANDROID_APP_DEVICE`: The target device name in Automate.
3.  **Run the logger**:
    ```bash
    ./window_logger.sh -c custom_scripts/android_automate_app_cloud_message_script.sh
    ```

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
