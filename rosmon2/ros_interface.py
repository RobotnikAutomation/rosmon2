"""ROS 2 interface of a rosmon2 session, like rosmon 1's start/stop service and state topic.

The supervisor is not a ROS node. When asked to (``mon2 launch --ros``) it runs a small
rclpy node in a thread of its own that offers:

* ``<ns>/rosmon2_<session>/start_stop`` (rosmon2_msgs/srv/StartStop)
* ``<ns>/rosmon2_<session>/state`` (rosmon2_msgs/msg/State)

Everything that touches the supervisor state runs in the launch event loop: requests are
handed over to it and the state is read from it, never from the ROS thread.
"""

import asyncio
import re
import threading
import time
from typing import Dict, List, Optional

from .control import ControlError

# rosmon2_msgs/srv/StartStop action constants.
ACTIONS = {1: 'start', 2: 'stop', 3: 'restart', 4: 'mute', 5: 'unmute'}
# rosmon2_msgs/msg/NodeState state constants; states without one show as IDLE.
STATE_CODES = {'idle': 0, 'running': 1, 'crashed': 2, 'waiting': 3}

# Private names (~/): they hang from the node (/<ns>/rosmon2_<session>/...) instead of from its
# namespace, so several sessions in the same namespace do not clash.
SERVICE_NAME = '~/start_stop'
TOPIC_NAME = '~/state'

CALL_TIMEOUT = 15.0
SNAPSHOT_TIMEOUT = 2.0
TICK_PERIOD = 0.2
STATE_PERIOD = 1.0


def ros_node_name(session: str) -> str:
    """Return a valid ROS node name for a session name."""
    return 'rosmon2_' + re.sub(r'[^A-Za-z0-9_]', '_', session)


def control_request(node: str, ns: str, action: int) -> Dict:
    """Translate a StartStop request into a supervisor control request."""
    command = ACTIONS.get(action)
    if command is None:
        raise ValueError(f'unknown action {action}; expected one of {sorted(ACTIONS)}')
    if node:
        return {'command': command, 'node': node}
    if ns:
        return {'command': command, 'namespace': ns}
    raise ValueError('specify node or ns')


def node_state_fields(node: Dict) -> Dict:
    """Map one status node (Supervisor.snapshot) to the fields of NodeState."""
    return {
        'name': node['name'],
        'label': node.get('label', node['name'].lstrip('/')),
        'ns': node['namespace'],
        'state': STATE_CODES.get(node['state'], 0),
        'muted': bool(node['muted']),
        'pid': int(node['pid'] or 0),
        'restart_count': int(node['restart_count']),
        'return_code': int(node['return_code'] or 0),
        'has_return_code': node['return_code'] is not None,
    }


class RosInterface:
    """Serve the start/stop service and publish the state of a supervisor."""

    def __init__(self, supervisor, loop: asyncio.AbstractEventLoop, session: str,
                 namespace: str = ''):
        self._supervisor = supervisor
        self._loop = loop
        self.session = session
        stripped = namespace.strip('/')
        self.namespace = '/' + stripped if stripped else '/'
        self.node_name = ros_node_name(session)
        self.error: Optional[str] = None
        self._changed = threading.Event()
        self._stop_requested = threading.Event()
        self._ready = threading.Event()
        self._thread: Optional[threading.Thread] = None

    @property
    def service_name(self) -> str:
        return f'{self.namespace.rstrip("/")}/{self.node_name}/{SERVICE_NAME[2:]}'

    @property
    def topic_name(self) -> str:
        return f'{self.namespace.rstrip("/")}/{self.node_name}/{TOPIC_NAME[2:]}'

    def start(self, timeout: float = 10.0) -> bool:
        """Start the ROS thread; return False (see ``error``) if the interface is unavailable."""
        self._thread = threading.Thread(target=self._run, name='rosmon2-ros', daemon=True)
        self._thread.start()
        if not self._ready.wait(timeout):
            self.error = self.error or 'timed out while starting the ROS node'
        return self.error is None

    def notify_change(self) -> None:
        """Ask for the state to be published soon; safe to call from any thread."""
        self._changed.set()

    def stop(self, timeout: float = 3.0) -> None:
        self._stop_requested.set()
        if self._thread is not None:
            self._thread.join(timeout)

    def _call(self, coroutine, timeout: float):
        """Run a coroutine in the launch event loop and wait for its result."""
        return asyncio.run_coroutine_threadsafe(coroutine, self._loop).result(timeout)

    async def _snapshot(self) -> List[Dict]:
        return self._supervisor.snapshot()

    def _run(self) -> None:
        try:
            import rclpy
            from rclpy.context import Context
            from rclpy.executors import SingleThreadedExecutor
            from rclpy.qos import DurabilityPolicy, QoSProfile, ReliabilityPolicy
            from rosmon2_msgs.msg import NodeState, State
            from rosmon2_msgs.srv import StartStop
        except ImportError as exc:
            self.error = f'{exc.name or exc} is not available'
            self._ready.set()
            return

        context = Context()
        node = None
        executor = None
        try:
            rclpy.init(context=context)
            node = rclpy.create_node(self.node_name, namespace=self.namespace, context=context)

            def handle(request, response):
                try:
                    result = self._call(
                        self._supervisor.control_request(
                            control_request(request.node, request.ns, request.action)),
                        CALL_TIMEOUT)
                    response.success = True
                    response.matched = int(result.get('matched', 0))
                    response.message = ''
                except (ValueError, ControlError) as exc:
                    response.success = False
                    response.message = str(exc)
                except Exception as exc:  # e.g. a timeout waiting for the launch loop
                    response.success = False
                    response.message = f'{type(exc).__name__}: {exc}'
                return response

            node.create_service(StartStop, SERVICE_NAME, handle)
            publisher = node.create_publisher(State, TOPIC_NAME, QoSProfile(
                depth=1,
                reliability=ReliabilityPolicy.RELIABLE,
                durability=DurabilityPolicy.TRANSIENT_LOCAL))
            last_published = [0.0]

            def tick():
                now = time.monotonic()
                if not (self._changed.is_set() or now - last_published[0] >= STATE_PERIOD):
                    return
                self._changed.clear()
                last_published[0] = now
                try:
                    nodes = self._call(self._snapshot(), SNAPSHOT_TIMEOUT)
                except Exception:
                    return
                message = State()
                message.header.stamp = node.get_clock().now().to_msg()
                message.session = self.session
                message.nodes = [NodeState(**node_state_fields(item)) for item in nodes]
                publisher.publish(message)

            node.create_timer(TICK_PERIOD, tick)
            executor = SingleThreadedExecutor(context=context)
            executor.add_node(node)
            self._ready.set()
            while not self._stop_requested.is_set():
                executor.spin_once(timeout_sec=0.1)
        except Exception as exc:
            self.error = self.error or f'{type(exc).__name__}: {exc}'
            self._ready.set()
        finally:
            if executor is not None:
                executor.shutdown()
            if node is not None:
                node.destroy_node()
            if context.ok():
                rclpy.shutdown(context=context)
