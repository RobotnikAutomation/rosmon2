# Tab completion of the YAML argument of ros2 commands, in a readable form.
#
# Out of the box, pressing TAB after the type of a service gives a backslash-escaped one-liner:
#
#   ros2 service call /x pkg/srv/Type node:\ \'\'\
#   ns:\ \'\'\
#   action:\ 0\
#
# With this file it gives a double-quoted, multi-line YAML, closed and ready to edit:
#
#   ros2 service call /x pkg/srv/Type "node: ''
#   ns: ''
#   action: 0"
#
# It applies to `ros2 service call` and `ros2 action send_goal`, for any service or action.
# Everything else is completed exactly as before (`ros2 topic pub` already quotes its value).
#
# Source it AFTER the ROS setup, which is what registers the ros2 completion (for example at
# the end of ~/.bashrc):   [ -f ~/.ros2_yaml_completion.bash ] && . ~/.ros2_yaml_completion.bash

_ros2_yaml_quote() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local kind=""
  case "${COMP_WORDS[1]} ${COMP_WORDS[2]}" in
    "service call") kind="srv" ;;
    "action send_goal") kind="action" ;;
  esac

  # Only where the YAML of the request goes: right after the type (pkg/srv/Type), still empty
  # or already starting with a double quote.
  if [[ -n $kind && $prev == */$kind/* && ( -z $cur || $cur == \"* ) ]]; then
    local saved_line=$COMP_LINE saved_point=$COMP_POINT
    if [[ -z $cur ]]; then
      # Complete as if the opening quote had been typed: argcomplete then returns the value
      # escaped for a double-quoted string, which keeps the line breaks.
      COMP_LINE="${COMP_LINE:0:COMP_POINT}\""
      COMP_POINT=$((COMP_POINT + 1))
    fi
    _python_argcomplete "$@"
    COMP_LINE=$saved_line
    COMP_POINT=$saved_point
    if [[ ${#COMPREPLY[@]} -eq 1 ]]; then
      local reply="${COMPREPLY[0]}"
      [[ -z $cur ]] && reply="\"$reply"
      [[ $reply == *\" ]] || reply="$reply\""
      COMPREPLY=("$reply")
    fi
    return
  fi

  _python_argcomplete "$@"
}

# Only when the standard ros2 completion is there.
if declare -F _python_argcomplete > /dev/null 2>&1; then
  complete -o bashdefault -o default -o nospace -F _ros2_yaml_quote ros2
fi
