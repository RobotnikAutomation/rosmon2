# bringup.sh snippet: launches a group with rosmon2 (mon2) or, if it does not apply, with ros2 launch.
#
# Where to put it: in bringup.sh, BEFORE the first time a group is launched (in the reference
# bringup, right before `if $ROBOT_RUN_SIMULATION`). It uses echo_warning, which bringup.sh
# already defines.
#
# Then replace every `screen -S <group> -d -m ros2 launch ...` line with
# `launch_group <group> <launch file>`. See README.md, section "Configure the bringup".

function launch_group() {
  local group="$1" launch_file="$2"
  local robot_id="${ROBOT_ID:-robot}"
  if [[ " $ROBOT_ROSMON2_GROUPS " == *" $group "* ]]; then
    if command -v mon2 > /dev/null 2>&1; then
      screen -S $group -d -m mon2 launch --session $group --strip-prefix $robot_id --ros --ros-namespace $robot_id $ROBOT_BRINGUP_PACKAGE $launch_file
      return
    fi
    echo_warning "--> $group: mon2 (rosmon2) not found, launching it with ros2 launch"
  fi
  screen -S $group -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE $launch_file
}
