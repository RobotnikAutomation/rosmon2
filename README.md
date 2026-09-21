# rosmon2

`rosmon2` is a rosmon-style launcher and terminal process monitor for ROS 2.
It runs launch files through the native ROS 2 `launch` engine, so existing
Python, XML, and YAML launch files keep their normal arguments, substitutions,
and includes.

`rosmon2` is inspired by [xqms/rosmon](https://github.com/xqms/rosmon), but is
an independent ROS 2 implementation and does not require ROS 1.


## Screenshot

![rosmon2 terminal process monitor](docs/rosmon2-terminal.png)


## Installation and quick start

Add this repository to a ROS 2 workspace, install its dependencies, and build
it with `colcon`:

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
git clone https://github.com/GibsonHu/rosmon2.git

cd ~/ros2_ws
source /opt/ros/${ROS_DISTRO}/setup.bash
rosdep install --from-paths src --ignore-src -r -y
colcon build --packages-select rosmon2
source install/setup.bash
```

Then launch the included talker/listener demo:

```bash
mon2 launch rosmon2 demo.launch.py
```

Launch arguments use the standard ROS 2 `name:=value` syntax:

```bash
mon2 launch rosmon2 demo.launch.py namespace:=demo
```

You can launch a file by package and filename, as above, or by path:

```bash
mon2 launch path/to/system.launch.py use_sim_time:=true
```

The `rosmon2` executable is an alias for `mon2`, so this is equivalent:

```bash
rosmon2 launch rosmon2 demo.launch.py
```

## Terminal controls

While a launch is running, the status bar shows each process and its state.
Select a process with its displayed key (`a-z`, `A-Z`, or `0-9`), then press:

| Key | Action |
| --- | --- |
| `s` | Start the selected process |
| `k` | Stop the selected process |
| `m` | Mute the selected process |
| `u` | Unmute the selected process |
| `d` | Start the selected process under `gdb` |

Global controls are available without selecting a process:

| Key | Action |
| --- | --- |
| `F5` | Toggle namespace mode |
| `F6` | Start all processes |
| `F7` | Stop all processes |
| `F8` | Toggle WARN-and-higher output |
| `F9` | Mute all process output |
| `F10` | Unmute all process output |
| `/` | Search nodes by full name |
| `Ctrl-C` | Gracefully stop the complete launch |

Node search matches substrings against full names, including namespaces. Type
`/` to start searching, use `Tab` or the arrow keys to select a match, and
press `Enter` to open its node actions. Press `Escape` to cancel the search.

Namespace mode groups processes by their top-level ROS namespace, including
nodes in child namespaces. Each namespace displays `[alive:dead]` process
counts. Its background is green when all processes are alive, yellow when only
some are alive, and red when all are dead.

Select a namespace with its displayed key, then press:

| Key | Namespace action |
| --- | --- |
| `s` | Start every process in the namespace |
| `k` | Stop every process in the namespace |
| `m` | Mute output from the namespace |
| `u` | Unmute output from the namespace |
| `i` | Inspect and control the individual processes |
| `Backspace` | Return from inspection to the namespace list |

<details>
<summary><strong>Advanced usage</strong></summary>

### Hiding a namespace prefix

`mon2 launch --strip-prefix robot ...` (or `ROSMON2_STRIP_PREFIX=robot`) shows
`/robot/controller_server` as `controller_server` in the terminal UI. It only changes what the
UI shows: the nodes keep their names, nodes outside the prefix are shown with their full name,
and control commands accept both forms (`--node controller_server` or
`--node /robot/controller_server`). If a shortened name would look like another process, the
full name is shown instead.

### ROS 2 interface

`mon2 launch --ros [--ros-namespace NS] ...` (needs the `rosmon2_msgs` package) offers what
rosmon 1 had. A session named `devices` in namespace `/robot` gets:

| Name | Type | Purpose |
| --- | --- | --- |
| `/robot/rosmon2_devices/start_stop` | `rosmon2_msgs/srv/StartStop` | start, stop, restart, mute or unmute |
| `/robot/rosmon2_devices/state` | `rosmon2_msgs/msg/State` | state of every node, on every change and once per second |

```bash
ros2 service call /robot/rosmon2_devices/start_stop rosmon2_msgs/srv/StartStop \
  "{node: controller_server, action: 3}"     # 1 start, 2 stop, 3 restart, 4 mute, 5 unmute
ros2 topic echo /robot/rosmon2_devices/state
```

`node` accepts the full name or the name shown in the UI; if it is empty, `ns` selects every
node under a namespace prefix. One of them is required. The requests run in the launch event
loop, the same code path as the terminal keys and the `mon2` commands.

### Terminal colors

The UI detects how many colors the terminal can show: 24-bit true color, the
256-color palette, or the 16 basic ANSI colors. Inside GNU screen (4.x, which
can not show 24-bit colors) or tmux, and with `TERM=screen*`, the 256-color
palette is used. Set `ROSMON2_COLORS=truecolor`, `256`, or `16` to force a mode.

### Command-line options

Run without the interactive terminal UI:

```bash
mon2 launch --disable-ui rosmon2 demo.launch.py
```

List the arguments declared by a launch file:

```bash
mon2 launch --list-args rosmon2 demo.launch.py
```

Load a launch description and exit, which is useful for benchmarking launch
file parsing:

```bash
mon2 launch --benchmark rosmon2 demo.launch.py
```

Discover processes without leaving them running:

```bash
mon2 launch --no-start rosmon2 demo.launch.py
```

Write combined stdout and stderr to a chosen file:

```bash
mon2 launch --log ./system.log --flush-log my_package system.launch.py
```

By default, process output is also written to a timestamped file under
`/tmp/rosmon2_*.log`. Use `mon2 launch --help` to see every option.

### Session control and JSON output

Every launch creates a private local Unix-socket session. Name the session so
another terminal or a script can inspect and control the same supervisor:

```bash
# Terminal 1
mon2 launch --session hardware rs_launch hardware.launch.py

# Terminal 2
mon2 status --session hardware --json
mon2 logs --session hardware --namespace /ur10e \
  --severity ERROR --since 120 --json
mon2 restart --session hardware \
  --node /ur10e/ur_ros_rtde/command_server --json
mon2 wait --session hardware --namespace /ur10e \
  --state running --timeout 60 --json
```

The available control commands are:

| Command | Purpose |
| --- | --- |
| `status` | Return node, namespace, PID, state, exit-code, and mute information |
| `logs` | Query the in-memory structured process log |
| `events` | Stream live JSON events from the supervisor |
| `start`, `stop`, `restart` | Control a node, namespace, or every process |
| `mute`, `unmute` | Control process output without stopping it |
| `wait` | Wait deterministically for matching processes to reach a state |

Mutating commands require exactly one explicit target:
`--node FULL_NAME`, `--namespace NAMESPACE`, or `--all`. Session names map to
sockets under `$XDG_RUNTIME_DIR/rosmon2`, or `/tmp/rosmon2-$UID` when no XDG
runtime directory is available. The directory and socket are accessible only
to the current user.

The socket API uses protocol version 1: one UTF-8 JSON request and response per
line. For example, sending
`{"command":"restart","node":"/ur10e/command_server"}` performs the same action
as the `mon2 restart` command. An `events` request first returns a subscription
acknowledgement and then streams event objects until disconnected. The CLI is
the supported client and avoids requiring callers to handle socket paths or
protocol framing themselves.

For a continuous, machine-readable launch stream, use:

```bash
mon2 launch --session hardware --json-events \
  rs_launch hardware.launch.py
```

`--json-events` disables the interactive TUI and writes one JSON object per
line. Events include session startup/shutdown, process starts/exits, control
actions, and structured log records. `mon2 events --session hardware` can
subscribe to the same stream from another process. Use `--no-control` only
when no external session socket is wanted.

The TUI and the JSON CLI use the same supervisor:

```text
ROS 2 launch processes
          |
    rosmon2 supervisor
        /       \
     TUI      JSON CLI
```

</details>

## Building from source

`rosmon2` is an `ament_python` package. If the repository is your workspace
root, build it from that directory. If it is inside a workspace's `src/`
directory, run `colcon build` from the workspace root:

```bash
source /opt/ros/${ROS_DISTRO}/setup.bash
colcon build --packages-select rosmon2
source install/setup.bash
```

To run the tests:

```bash
colcon test --packages-select rosmon2
colcon test-result --verbose
```

If packages installed in `~/.local` override your ROS 2 or workspace build
tools, repeat the build with `PYTHONNOUSERSITE=1` in the environment.

## License

`rosmon2` is licensed under the [BSD 3-Clause License](LICENSE).
