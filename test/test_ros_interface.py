import pytest

from rosmon2.ros_interface import (
    ACTIONS, control_request, node_state_fields, ros_node_name, RosInterface, SERVICE_NAME,
    STATE_CODES, TOPIC_NAME)
from rosmon2.model import ProcessRecord, State
from rosmon2.supervisor import Supervisor


def test_ros_node_name_is_valid_for_any_session_name():
    assert ros_node_name('devices') == 'rosmon2_devices'
    assert ros_node_name('my-robot.base') == 'rosmon2_my_robot_base'


def test_service_actions_map_to_control_commands():
    assert ACTIONS == {1: 'start', 2: 'stop', 3: 'restart', 4: 'mute', 5: 'unmute'}
    assert control_request('controller_server', '', 3) == {
        'command': 'restart', 'node': 'controller_server'}
    assert control_request('', 'front_laser', 2) == {
        'command': 'stop', 'namespace': 'front_laser'}
    # A node wins over a namespace, like in the control socket.
    assert control_request('a', 'b', 1) == {'command': 'start', 'node': 'a'}


def test_service_needs_a_target_and_a_known_action():
    with pytest.raises(ValueError, match='node or ns'):
        control_request('', '', 2)
    with pytest.raises(ValueError, match='unknown action'):
        control_request('a', '', 9)


def test_state_codes_match_the_message_constants():
    assert STATE_CODES == {'idle': 0, 'running': 1, 'crashed': 2, 'waiting': 3}
    assert {state.value for state in State} <= set(STATE_CODES)


def test_node_state_fields_from_a_status_node():
    supervisor = Supervisor('', [], ui=False, control=False, strip_prefixes=['robot'])
    record = ProcessRecord(key=0, display_name='controller_server',
                           full_name='robot/controller_server', state=State.CRASHED,
                           pid=None, restart_count=2, return_code=1, muted=True)
    supervisor.records.append(record)

    assert node_state_fields(supervisor.snapshot()[0]) == {
        'name': '/robot/controller_server',
        'label': 'controller_server',
        'ns': 'robot',
        'state': 2,
        'muted': True,
        'pid': 0,
        'restart_count': 2,
        'return_code': 1,
        'has_return_code': True,
    }


def test_running_node_has_no_return_code():
    supervisor = Supervisor('', [], ui=False, control=False)
    supervisor.records.append(
        ProcessRecord(key=0, display_name='talker', state=State.RUNNING, pid=42))

    fields = node_state_fields(supervisor.snapshot()[0])
    assert fields['pid'] == 42
    assert fields['has_return_code'] is False


def test_interface_names_follow_the_namespace():
    assert RosInterface(None, None, 'devices', 'robot').service_name == (
        '/robot/rosmon2_devices/start_stop')
    assert RosInterface(None, None, 'devices', '/robot/').topic_name == (
        '/robot/rosmon2_devices/state')
    assert RosInterface(None, None, 'devices').service_name == '/rosmon2_devices/start_stop'


def test_ros_names_are_private_to_the_node():
    # A relative name would resolve against the namespace (/robot/start_stop) and two
    # sessions in the same namespace would clash; ~/ hangs them from the node.
    assert SERVICE_NAME == '~/start_stop'
    assert TOPIC_NAME == '~/state'
