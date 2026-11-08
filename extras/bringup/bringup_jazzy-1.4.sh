#!/bin/bash
# bringup.sh of robot_packages jazzy-1.4 with every group launched by rosmon2.
# Copy it to ~/bringup.sh (see the rosmon2 README). Only launch_group() and its calls differ.

# function to echo with color red [echo_error]
function echo_error() {
  echo -e "\e[31m$1\e[0m"
}
# function to echo with color green [echo_success]
function echo_success() {
  echo -e "\e[32m$1\e[0m"
}
# function to echo with color yellow [echo_warning]
function echo_warning() {
  echo -e "\e[33m$1\e[0m"
}
# function to echo with color blue and bold [echo_info]
function echo_info() {
  echo -e "\e[1;34m$1\e[0m"
}

ros_config="$HOME/ros_config.sh"


# Loads $ros_config file if exists.
if [ -f "$ros_config" ]; then
  echo_success "Loading ros_config from $ros_config"
  if [ "$?" != "0" ]; then
    echo_error "Error reading file!! $ros_config"
    exit
  fi
else
  # Loads ros_config using the path of the current script
  echo_warning "$ros_config doesn't exist. Loading config from robot_bringup/scripts/ros_config.sh"
  ros_config="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ros_config.sh"
  if [ -f "$ros_config" ]; then
    echo_success "Loading ros_config from $ros_config"
    if [ "$?" != "0" ]; then
      echo "Error reading file!! $ros_config"
      exit
    fi
  fi
fi

if ! source $ros_config; then
  echo_error "Error reading ros_config.sh"
  exit
else
  echo_success "Loaded ros_config"
fi

echo_success "This script is going to load the ros configuration located at $ros_config"
echo "This script is going to load and launch all the robot packages based on the environment variables configuration..."

# TODO: check if env vars is loaded and show a warning

echo "Closing all the running screens..."
killall screen -q
sleep 2;

if [[ -z "${ROBOT_RUN_SIMULATION}" ]]; then
  ROBOT_RUN_SIMULATION=false
fi
if [[ -z "${ROBOT_RUN_SLAM}" ]]; then
  ROBOT_RUN_SLAM=false
fi
if [[ -z "${ROBOT_RUN_NAVIGATION}" ]]; then
  ROBOT_RUN_NAVIGATION=false
fi
if [[ -z "${ROBOT_RUN_PERCEPTION}" ]]; then
  ROBOT_RUN_PERCEPTION=false
fi
if [[ -z "${ROBOT_RUN_BEHAVIOR}" ]]; then
  ROBOT_RUN_BEHAVIOR=false
fi
# if [[ -z "${ROBOT_RUN_RLC_ROSTFUL_SERVER}" ]]; then
#   ROBOT_RUN_RLC_ROSTFUL_SERVER=false
# fi
# if [[ -z "${ROBOT_RUN_HMI}" ]]; then
#   ROBOT_RUN_HMI=false
# fi
# if [[ -z "${ROBOT_RUN_UTILS}" ]]; then
#   ROBOT_RUN_UTILS=false
# fi
# if [[ -z "${ROBOT_RUN_COMMAND_MANAGER}" ]]; then
#   ROBOT_RUN_COMMAND_MANAGER=false
# fi
if [[ -z "${ROBOT_RUN_SENSORS}" ]]; then
  ROBOT_RUN_SENSORS=false
fi
if [[ -z "${ROBOT_RUN_MANIPULATION}" ]]; then
  ROBOT_RUN_MANIPULATION=false
fi
# if [[ -z "${ROBOT_RUN_NEW_HMI}" ]]; then
#   ROBOT_RUN_NEW_HMI=false
# fi
# if [[ -z "${ROBOT_RUN_ROSBAG_MANAGER}" ]]; then
#   ROBOT_RUN_ROSBAG_MANAGER=false
# fi
# if [[ -z "${ROBOT_RUN_INTERFACES}" ]]; then
#   ROBOT_RUN_INTERFACES=false
# fi
# if [[ -z "${ROBOT_RUN_SAFETY}" ]]; then
#   ROBOT_RUN_SAFETY=false
# fi
# if [[ -z "${ROBOT_RUN_EXTERNAL_MACHINE}" ]]; then
#   ROBOT_RUN_EXTERNAL_MACHINE=false
# fi

echo_info "ROBOT MODEL = $ROBOT_MODEL"
echo_info "ROBOT PACKAGES VERSION = $ROBOT_PACKAGES_VERSION"

echo "RUN SIM = $ROBOT_RUN_SIMULATION"
echo "RUN LOCALIZATION = $ROBOT_RUN_LOCALIZATION"
echo "RUN NAVIGATION = $ROBOT_RUN_NAVIGATION"
echo "RUN PERCEPTION = $ROBOT_RUN_PERCEPTION"
# echo "RUN HMI = $ROBOT_RUN_HMI"
# echo "RUN UTILS = $ROBOT_RUN_UTILS"
# echo "RUN COMMAND_MANAGER = $ROBOT_RUN_COMMAND_MANAGER"
echo "RUN DEVICES = $ROBOT_RUN_DEVICES"
echo "RUN MANIPULATION = $ROBOT_RUN_MANIPULATION"
echo "RUN BEHAVIOR = $ROBOT_RUN_BEHAVIOR"
# echo "RUN ROBOT_RUN_ROSBAG_MANAGER = $ROBOT_RUN_ROSBAG_MANAGER"
# echo "RUN ROBOT_RUN_INTERFACES = $ROBOT_RUN_INTERFACES"
# echo "RUN ROBOT_RUN_SAFETY = $ROBOT_RUN_SAFETY"
# echo "RUN ROBOT_RUN_EXTERNAL_MACHINE = $ROBOT_RUN_EXTERNAL_MACHINE"


rmw_known_values=("rmw_fastrtps_cpp" "rmw_cyclonedds_cpp" "rmw_zenoh_cpp")
if [[ ! " ${rmw_known_values[@]} " =~ " ${RMW_IMPLEMENTATION} " ]]; then
  echo_warning "RMW_IMPLEMENTATION is set to an unknown value: $RMW_IMPLEMENTATION"
fi

if [[ "$RMW_IMPLEMENTATION" == "rmw_zenoh_cpp" ]]; then
  echo_warning "RMW_IMPLEMENTATION is set to rmw_zenoh_cpp (experimental)"
  screen -dmS zenoh_router ros2 run rmw_zenoh_cpp rmw_zenohd
  sleep 2;
fi

# Launch a group in its screen session with rosmon2 (mon2: node states, start/stop/restart
# from the keyboard or the rosmon2_msgs services). Falls back to ros2 launch without mon2.
function launch_group() {
  local group="$1" launch_file="$2"
  local robot_id="${ROBOT_ID:-robot}"
  if command -v mon2 > /dev/null 2>&1; then
    screen -S "$group" -d -m mon2 launch --session "$group" --strip-prefix "$robot_id" \
      --ros --ros-namespace "$robot_id" "$ROBOT_BRINGUP_PACKAGE" "$launch_file"
  else
    echo_warning "--> $group: mon2 (rosmon2) not found, launching it with ros2 launch"
    screen -S "$group" -d -m ros2 launch "$ROBOT_BRINGUP_PACKAGE" "$launch_file"
  fi
}

if $ROBOT_RUN_SIMULATION
then
  if [[ -z "${ROBOT_BRINGUP_SIM_PACKAGE}" ]]; then
    echo_error "-> ERROR. The var ROBOT_BRINGUP_SIM_PACKAGE is not defined..."
    exit
  fi
  if [[ -z "${ROBOT_BRINGUP_SIM_LAUNCH}" ]]; then
    echo_error "-> ERROR. The var ROBOT_BRINGUP_SIM_LAUNCH is not defined..."
    exit
  fi
  echo_success "-> Launching robot simulation..."
  echo_info "--> robot xacro: $ROBOT_XACRO ; path: $ROBOT_BRINGUP_SIM_PACKAGE/$ROBOT_BRINGUP_SIM_LAUNCH"
  #screen -S bringup -d -m rosrun rosmon rosmon --name=rosmon_bringup $ROBOT_BRINGUP_SIM_PACKAGE $ROBOT_BRINGUP_SIM_LAUNCH;

else
  if [[ -z "${ROBOT_BRINGUP_PACKAGE}" ]]; then
    echo_error "-> ERROR. The var ROBOT_BRINGUP_PACKAGE is not defined..."
    exit
  fi
  if [[ -z "${ROBOT_BRINGUP_LAUNCH}" ]]; then
    echo_error "-> ERROR. The var ROBOT_BRINGUP_LAUNCH is not defined..."
    exit
  fi
  echo_success "Launching robot $ROBOT_BRINGUP_PACKAGE/$ROBOT_BRINGUP_LAUNCH..."
  launch_group base "$ROBOT_BRINGUP_LAUNCH"
fi

sleep 3;

if $ROBOT_RUN_DEVICES
then
  echo_success "Launching devices..."
  launch_group devices devices_complete.launch.py
  sleep 1;
fi


if $ROBOT_RUN_LOCALIZATION
then
  echo_success "Launching localization packages..."
  launch_group localization localization_complete.launch.py
  sleep 1;
fi


if $ROBOT_RUN_PERCEPTION
then
  echo_success "Launching perception packages..."
  launch_group perception perception_complete.launch.py
  sleep 1;
fi

if $ROBOT_RUN_NAVIGATION
then
  echo_success "Launching navigation packages..."
  launch_group navigation navigation_complete.launch.py
  sleep 1;
fi

# if $ROBOT_RUN_HMI
# then
#   echo_success "Launching hmi packages..."
#   screen -S hmi -d -m rosrun rosmon rosmon --name=rosmon_hmi $ROBOT_BRINGUP_PACKAGE hmi_complete.launch;
#   sleep 2;
# fi

# if $ROBOT_RUN_UTILS
# then
#   echo_success "Launching utils..."
#   screen -S utils -d -m rosrun rosmon rosmon --name=rosmon_utils $ROBOT_BRINGUP_PACKAGE utils_complete.launch;
# fi

# if $ROBOT_RUN_COMMAND_MANAGER
# then
#   echo_success "Launching command manager..."
#   screen -S command_manager -d -m rosrun rosmon rosmon --name=rosmon_command_manager $ROBOT_BRINGUP_PACKAGE command_manager_complete.launch;
# fi

if $ROBOT_RUN_MANIPULATION
then
  echo_success "Launching manipulation..."
  launch_group manipulation manipulation_complete.launch.py
  sleep 1;
fi

if $ROBOT_RUN_BEHAVIOR
then
  echo_success "Launching behavior packages..."
  launch_group behavior behavior_complete.launch.py
  sleep 1;
fi

# if $ROBOT_RUN_ROSBAG_MANAGER
# then
#   echo_success "Launching rosbag manager..."
#   screen -S rosbag_manager -d -m rosrun rosmon rosmon --name=rosmon_rosbag_manager $ROBOT_BRINGUP_PACKAGE rosbag_manager.launch;
# fi

# if $ROBOT_RUN_INTERFACES
# then
#   echo_success "Launching interfaces..."
#   screen -S interfaces -d -m rosrun rosmon rosmon --name=rosmon_interfaces $ROBOT_BRINGUP_PACKAGE interfaces_complete.launch;
# fi

# if $ROBOT_RUN_SAFETY
# then
#   echo_success "Launching safety..."
#   screen -S safety -d -m rosrun rosmon rosmon --name=rosmon_safety $ROBOT_BRINGUP_PACKAGE safety_complete.launch;
# fi

# if $ROBOT_RUN_EXTERNAL_MACHINE
# then
#   if [[ ${ROBOT_EXTERNAL_MACHINE_1_USER} != "none" ]]
#   then
#     echo_success "Launching external machine 1..."
#     if ssh $ROBOT_EXTERNAL_MACHINE_1_USER@$ROBOT_EXTERNAL_MACHINE_1_IP $ROBOT_EXTERNAL_MACHINE_1_COMMAND
#     then
#       echo_success "Command started in external machine 1";
#     else
#       echo_error "Error communicating with external machine 1";
#     fi
#   fi
#   if [[ ${ROBOT_EXTERNAL_MACHINE_2_USER} != "none" ]]
#   then
#     echo "Launching external machine 2..."
#     if ssh $ROBOT_EXTERNAL_MACHINE_2_USER@$ROBOT_EXTERNAL_MACHINE_2_IP $ROBOT_EXTERNAL_MACHINE_2_COMMAND
#     then
#       echo_success "Command started in external machine 2";
#     else
#       echo_error "Error communicating with external machine 2";
#     fi
#   fi
# fi