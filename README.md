# rosmon2 · Robotnik fork

**A node launcher and monitor for ROS 2 Jazzy, in the style of [rosmon](https://github.com/xqms/rosmon) (ROS 1).**
Every node with its state in color, and stop, start, restart and mute nodes from the keyboard, from another terminal or from a ROS 2 service.

![rosmon2 in a terminal](docs/rosmon2-terminal.png)

## What you get

- Launches **any launch file** (`.launch.py`, XML, YAML) with the native `ros2 launch` engine: **no launch file, node or parameter has to change**.
- One node per line, **colored by state**, with keys to act on it.
- Control from another terminal (`mon2 stop|start|restart ...`) and from ROS 2 (`ros2 service call ...`), like in rosmon 1.
- Plugs into `bringup.sh` with one variable and one function: any group can move to rosmon2, or back to `ros2 launch`, by editing a list.
- No external Python dependencies, and no internet access needed on the robot.

<details>
<summary><b>What differs from the original rosmon2</b></summary>

The fork starts from commit `578ea91` (2026-07-24), which is **before** an embedded AI agent was added, and adds:

| Change | Why |
| --- | --- |
| MCP server (`rosmon2-mcp`) removed | Not needed in a bringup, and it avoids an external control path |
| Adaptive colors (24-bit, 256 or 16 colors) | Inside `screen` 4.x, the one shipped by Ubuntu, the original showed everything in gray |
| `--strip-prefix` | Hides the `/robot/` prefix, only in the text of the screen |
| ROS 2 interface (`--ros`) and the `rosmon2_msgs` package | A `start_stop` service and a `state` topic, like `rosmon_msgs` in ROS 1 |

</details>

## Packages

| Repository | Package | What it is |
| --- | --- | --- |
| [`rosmon2`](https://github.com/RobotnikAutomation/rosmon2) | `rosmon2` (`ament_python`) | The monitor: the `mon2` and `rosmon2` commands |
| [`rosmon2_msgs`](https://github.com/RobotnikAutomation/rosmon2_msgs) | `rosmon2_msgs` (`ament_cmake`) | The `StartStop` service and the `State` message |

Install **both, as sibling folders** in the `src/` of your workspace.

## Installation

Tested on **Ubuntu 24.04 · ROS 2 Jazzy · GNU screen 4.09**. You need `colcon` and `screen`; `rosidl_default_generators` usually comes with ROS.

```bash
# 1. Clone next to your packages
cd ~/robot_ws/src
git clone https://github.com/RobotnikAutomation/rosmon2.git
git clone https://github.com/RobotnikAutomation/rosmon2_msgs.git

# 2. Build only these two packages (the rest of the workspace is not touched)
cd ~/robot_ws
source /opt/ros/jazzy/setup.bash
colcon build --symlink-install --packages-select rosmon2_msgs rosmon2
source install/setup.bash

# 3. Check
mon2 --help
ros2 interface show rosmon2_msgs/srv/StartStop
```

## Configure the bringup

Two files change, and no launch file is modified. Back both up first.

### 1. `bringup.env`: which groups use rosmon2

Add one variable ([`extras/bringup/bringup.env.snippet`](extras/bringup/bringup.env.snippet)). The groups in the list are launched with rosmon2; the others with `ros2 launch`, as always.

```bash
export ROBOT_ROSMON2_GROUPS="base devices localization perception navigation manipulation behavior hmi"
```

> All the groups of the reference bringup have been tested with rosmon2. If your bringup differs, add groups one by one and **leave `base` (motors) for last**. To turn it all off, leave the string empty (`""`).

### 2. `bringup.sh`: one function, and replace the group lines

**a)** Paste the function from [`extras/bringup/launch_group.sh`](extras/bringup/launch_group.sh) **before the first time a group is launched** (in the reference bringup, right before `if $ROBOT_RUN_SIMULATION`).

**b)** Replace every `screen -S <group> ... ros2 launch ...` line with a call to the function. The rest of each block (`echo_success`, `sleep`) does not change:

```diff
-  screen -S base -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE $ROBOT_BRINGUP_LAUNCH;
+  launch_group base $ROBOT_BRINGUP_LAUNCH
-  screen -S devices -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE devices_complete.launch.py;
+  launch_group devices devices_complete.launch.py
-  screen -S localization -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE localization_complete.launch.py;
+  launch_group localization localization_complete.launch.py
-  screen -S perception -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE perception_complete.launch.py;
+  launch_group perception perception_complete.launch.py
-  screen -S navigation -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE navigation_complete.launch.py;
+  launch_group navigation navigation_complete.launch.py
-  screen -S manipulation -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE manipulation_complete.launch.py;
+  launch_group manipulation manipulation_complete.launch.py
-  screen -S behavior -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE behavior_complete.launch.py;
+  launch_group behavior behavior_complete.launch.py
-  screen -S hmi -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE hmi_complete.launch.py;
+  launch_group hmi hmi_complete.launch.py
```

A group that is not in `ROBOT_ROSMON2_GROUPS` behaves **exactly** as before, so it is safe to replace all of them even if rosmon2 is only used for some. The initial `killall screen` needs no change: when a screen is closed, `mon2` and its nodes go with it, leaving no orphans.

The function uses the `ROBOT_ID` variable (default `robot`) for the prefix it hides and for the namespace of the ROS interface. If in your bringup the namespace comes from another variable, change the `local robot_id=...` line.

## Usage

### View a group

```bash
screen -r navigation      # to leave WITHOUT stopping it: Ctrl-A, then D
```

> **`Ctrl-C` inside the screen stops the whole group.**

Pick a node with its letter and press a key:

| Key | Action | | Key | Action |
| --- | --- | --- | --- | --- |
| `s` | start | | `/` | search by name |
| `k` | stop | | `F5` | group by namespace |
| `m` / `u` | mute / unmute | | `F6` / `F7` | start / stop all |
| `d` | start under `gdb` | | `Ctrl-C` | stop the group |

Colors: **green** running · **red** exited with an error · **orange** starting · **black** stopped.

### From another terminal

```bash
mon2 status  --session navigation
mon2 stop    --session navigation --node controller_server
mon2 restart --session navigation --node /robot/controller_server   # short or full name
mon2 logs    --session navigation --node planner_server --severity ERROR
```

### From ROS 2

Every group offers `/<robot>/rosmon2_<group>/start_stop` and the topic `/<robot>/rosmon2_<group>/state`.

```bash
# action: 1 start · 2 stop · 3 restart · 4 mute · 5 unmute
ros2 service call /robot/rosmon2_navigation/start_stop rosmon2_msgs/srv/StartStop \
  "node: 'controller_server'
ns: ''
action: 3"
```

`node` accepts the name shown on the screen or the full one (`/robot/controller_server`). If it is empty, `ns` selects every node under a namespace.

### Readable tab completion (optional)

When you press TAB on a service, ROS 2 escapes the request with backslashes. [`extras/ros2_yaml_completion.bash`](extras/ros2_yaml_completion.bash) makes it come out as a multi-line, quoted and closed YAML. How to install it, per robot or for a whole fleet, in the [guide](docs/GUIA_INSTALACION.md#4-autocompletado-del-request-con-comillas-opcional) (in Spanish).

## Validation status

| Validated | Still to test |
| --- | --- |
| Every group the reference bringup runs (`base`, `devices`, `localization`, `perception`, `navigation`, `behavior`, `hmi`) on a real RBVogui (Jazzy, `rmw_zenoh_cpp`) | The `manipulation` group (not run by the reference robot) |
| `navigation`: ROS 2 service, state topic and `mon2` commands checked in detail | FastDDS with a Discovery Server |
| Closing the screen leaves no orphan processes | |

**Known limitations**

- The ROS 2 interface has **no authentication**: any node in the same domain can stop nodes. Remove `--ros` from the function if that is a problem.
- Stopping critical `base` nodes (for example `ros2_control_node`) has the same effect as killing them by hand.
- A node stopped by hand shows in black, not red, and there is no "not launched" state yet.

## Documentation

- [`docs/GUIA_INSTALACION.md`](docs/GUIA_INSTALACION.md): what to add to `bringup.sh` and `bringup.env`, how to install the tab completion and what else to install, in Spanish.
- [`extras/`](extras): bringup snippets and the tab completion.

## Credits and license

Based on *rosmon2* by Gibson Hu, under the **BSD-3-Clause** license (see [`LICENSE`](LICENSE), which must be kept when redistributing). Inspired by [rosmon](https://github.com/xqms/rosmon) for ROS 1.

Maintainer: ocopa@robotnik.es · GitHub: [@ocopmur](https://github.com/ocopmur)
