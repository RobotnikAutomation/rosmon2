# Guía: qué añadir al bringup y al autocompletado

Esta guía cubre **solo lo que hay que modificar en el robot** para usar rosmon2. Para clonar y compilar los paquetes, el uso diario (teclas, comandos `mon2`, servicio ROS 2), los colores y las limitaciones, ver el [README](../README.md).

Se toca esto, y nada más:

| Dónde | Qué |
| --- | --- |
| Sistema | Unos pocos paquetes `apt` (sección 1) |
| `bringup.env` | 1 variable (sección 2) |
| `bringup.sh` | 1 función y 8 líneas sustituidas (sección 3) |
| `~/.bashrc` o `ros_config.sh` | 1 línea para el autocompletado con comillas (sección 4, opcional) |
| Launch files, nodos, parámetros | **Nada** |

Antes de empezar, una copia de seguridad de los dos ficheros:

```bash
cp ~/bringup.sh                           ~/bringup.sh.bak
cp ~/robot_settings/robot_params/bringup.env ~/robot_settings/robot_params/bringup.env.bak
```

---

## 1. Qué instalar además de los dos paquetes

Los paquetes `rosmon2` y `rosmon2_msgs` se clonan y se compilan como indica el README. Para que funcionen hace falta, además:

```bash
sudo apt install screen python3-colcon-common-extensions ros-jazzy-rosidl-default-generators
```

| Paquete | Para qué |
| --- | --- |
| `screen` | El bringup lanza cada grupo dentro de una screen. Se ha probado con GNU screen 4.09 |
| `python3-colcon-common-extensions` | Compilar los paquetes |
| `ros-jazzy-rosidl-default-generators` | Compilar `rosmon2_msgs`. Suele venir con `ros-jazzy-desktop` |
| `python3-argcomplete` | Solo para el autocompletado (sección 4). Lo trae `ros2cli`, así que ya suele estar |

No hace falta `pip`, ni ninguna dependencia externa de Python, ni internet en el robot.

### El entorno del bringup tiene que cargar el workspace

`bringup.sh` lanza `mon2`, así que **el entorno con el que se ejecuta debe incluir el workspace donde se compilaron los paquetes**. En el bringup de referencia ya ocurre, porque `ros_config.sh` carga `<workspace>/install/setup.bash`. Se comprueba así:

```bash
source ~/ros_config.sh
command -v mon2                                       # debe imprimir una ruta
ros2 interface show rosmon2_msgs/srv/StartStop        # debe mostrar los campos del servicio
```

Si tu bringup no usa `ros_config.sh`, añade `source <workspace>/install/setup.bash` antes de lanzar los grupos. Sin `rosmon2_msgs` en el entorno, el grupo **sigue arrancando**, pero sin el servicio ni el topic de ROS 2 (la pantalla avisa con `ROS interface disabled`).

---

## 2. `bringup.env`: una variable

**Fichero:** `~/robot_settings/robot_params/bringup.env`, el que carga `ros_config.sh`.

**Dónde:** en cualquier punto, junto a las variables `ROBOT_RUN_*`. Por ejemplo, justo después de `export ROBOT_RUN_BEHAVIOR=true`.

**Qué añadir** (está también en `extras/bringup/bringup.env.snippet`):

```bash
# String. Groups launched with rosmon2 (mon2 launch) instead of ros2 launch, separated by spaces. Empty: none.
# Each group has its own screen (screen -r <group>) showing its nodes without the /$ROBOT_ID prefix, and its
# nodes can be stopped/started/restarted with:
#   mon2 stop|start|restart --session <group> --node controller_server
#   ros2 service call /$ROBOT_ID/rosmon2_<group>/start_stop rosmon2_msgs/srv/StartStop "{node: controller_server, action: 3}"
# A group that is not in the list is launched with ros2 launch, as usual.
# Available: base devices localization perception navigation manipulation behavior hmi
export ROBOT_ROSMON2_GROUPS="base devices localization perception navigation manipulation behavior hmi"
```

**Valores:**

| Valor | Efecto |
| --- | --- |
| `"base devices localization perception navigation manipulation behavior hmi"` | Todos los grupos del bringup de referencia |
| `"hmi perception navigation"` | Solo algunos, separados por espacios |
| `"navigation"` | Solo uno |
| `""` | Ninguno: todo vuelve a `ros2 launch`, sin tocar nada más |

Todos los grupos del bringup de referencia se han probado con rosmon2. Si vuestro bringup es distinto, añadid grupos de uno en uno y dejad **`base` (motores) para el final**.

---

## 3. `bringup.sh`: una función y sustituir las líneas de los grupos

**Fichero:** `~/bringup.sh`. Son dos cambios.

### 3.1. Añadir la función `launch_group`

**Dónde:** **antes de la primera vez que se lanza un grupo**. En el bringup de referencia, justo después de los bloques que arrancan el `zenoh_router` y el `discovery_server`, y **antes de** `if $ROBOT_RUN_SIMULATION`:

```bash
if $ROBOT_RUN_SIMULATION      # <-- la función va inmediatamente ANTES de esta línea
then
```

La función usa `echo_warning`, que `bringup.sh` ya define al principio. Está también lista para copiar en `extras/bringup/launch_group.sh`.

```bash
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
```

Comportamiento:

- Grupo **fuera** de `ROBOT_ROSMON2_GROUPS`: el mismo `ros2 launch` de siempre.
- Grupo en la lista pero `mon2` **no instalado**: aviso y `ros2 launch`. El robot arranca igualmente.
- Grupo en la lista y `mon2` disponible: `mon2 launch`, ocultando el prefijo del robot en la pantalla y ofreciendo el servicio y el topic de ROS 2.

El prefijo y el namespace salen de **`ROBOT_ID`** (por defecto `robot`). Si en vuestro bringup el namespace del robot viene de otra variable, cambiad la línea `local robot_id=...`.

### 3.2. Sustituir la línea de cada grupo

**Dónde:** en los bloques `if $ROBOT_RUN_<GRUPO>` que ya existen. Para localizar las líneas:

```bash
grep -n "screen -S" ~/bringup.sh
```

Se **sustituye** la línea `screen -S ... ros2 launch ...` por la llamada a la función. El resto del bloque (`echo_success`, `sleep`) no cambia.

| Grupo | Línea actual (a sustituir) | Línea nueva |
| --- | --- | --- |
| base | `screen -S base -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE $ROBOT_BRINGUP_LAUNCH;` | `launch_group base $ROBOT_BRINGUP_LAUNCH` |
| devices | `screen -S devices -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE devices_complete.launch.py;` | `launch_group devices devices_complete.launch.py` |
| localization | `screen -S localization -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE localization_complete.launch.py;` | `launch_group localization localization_complete.launch.py` |
| perception | `screen -S perception -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE perception_complete.launch.py;` | `launch_group perception perception_complete.launch.py` |
| navigation | `screen -S navigation -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE navigation_complete.launch.py;` | `launch_group navigation navigation_complete.launch.py` |
| manipulation | `screen -S manipulation -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE manipulation_complete.launch.py;` | `launch_group manipulation manipulation_complete.launch.py` |
| behavior | `screen -S behavior -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE behavior_complete.launch.py;` | `launch_group behavior behavior_complete.launch.py` |
| hmi | `screen -S hmi -d -m ros2 launch $ROBOT_BRINGUP_PACKAGE hmi_complete.launch.py;` | `launch_group hmi hmi_complete.launch.py` |

Ejemplo, el bloque de navegación después del cambio:

```bash
if $ROBOT_RUN_NAVIGATION
then
  echo_success "Launching navigation packages..."
  launch_group navigation navigation_complete.launch.py
  sleep 1;
fi
```

Se pueden sustituir **todos** los grupos aunque solo uno use rosmon2: los que no estén en la lista se comportan igual que antes. La línea de `base` está dentro del bloque `else` de la comprobación de simulación (`ROBOT_RUN_SIMULATION`).

### 3.3. Lo que no hay que tocar

El `killall screen -q` del principio de `bringup.sh` sigue funcionando: al cerrarse la screen se cierran `mon2` y todos sus nodos.

---

## 4. Autocompletado del request con comillas (opcional)

Por defecto, al pulsar TAB tras el tipo de un servicio, ROS 2 escapa el request en una línea con barras invertidas:

```text
ros2 service call /robot/rosmon2_devices/start_stop rosmon2_msgs/srv/StartStop node:\ \'\'\
ns:\ \'\'\
action:\ 0\
```

Con el fichero `extras/ros2_yaml_completion.bash` sale un YAML en varias líneas, entre comillas y ya cerrado:

```text
ros2 service call /robot/rosmon2_devices/start_stop rosmon2_msgs/srv/StartStop "node: ''
ns: ''
action: 0"
```

Es un cambio de **ROS 2 en general**, no de rosmon2: funciona con cualquier servicio y con `ros2 action send_goal`. `ros2 topic pub` no se toca, porque ya trae sus propias comillas.

**Requisitos:** `bash`, una terminal interactiva, `python3-argcomplete`, y que ROS se cargue **antes** que este fichero, porque el `setup.bash` de ROS es lo que registra el completado original.

### Opción A. En un usuario o robot concreto

```bash
cp extras/ros2_yaml_completion.bash ~/.ros2_yaml_completion.bash
```

Añadir **al final de `~/.bashrc`**, después de las líneas que cargan ROS (`source /opt/ros/jazzy/setup.bash` y, si existe, `source ~/ros_config.sh`):

```bash
[ -f ~/.ros2_yaml_completion.bash ] && . ~/.ros2_yaml_completion.bash
```

Y cargarlo en la terminal actual (en las nuevas ya estará):

```bash
source ~/.bashrc
```

### Opción B. Para toda la flota (recomendada en producción)

Se despliega con los scripts que ya usáis, sin editar ningún `.bashrc` a mano. Son tres cambios en `robot_packages`, en `packages/robot_bringup/scripts/`:

**1.** Añadir el fichero `ros2_yaml_completion.bash` a esa carpeta (es el de `extras/`).

**2.** Al **final de `ros_config.sh`**, después del `source_file $workspace/install/setup.bash`. Solo actúa en terminales interactivas, así que no afecta a `bringup.sh` ni al servicio de systemd:

```bash
# Readable tab completion of the YAML of ros2 service call / action send_goal (interactive bash only).
# It goes after the ROS setup above, which is what registers the ros2 completion.
if [[ $- == *i* ]] && [ -f "$(dirname "${BASH_SOURCE[0]}")/ros2_yaml_completion.bash" ]; then
  source "$(dirname "${BASH_SOURCE[0]}")/ros2_yaml_completion.bash"
fi
```

**3.** En **`configure_bringup.sh`**, justo debajo de la línea que copia `ros_config.sh` a `~`:

```bash
run_cmd cp $(abspath $this_script_dir/../scripts/ros2_yaml_completion.bash) ~/ros2_yaml_completion.bash
```

Si también usáis las imágenes Docker, una línea `COPY` más junto a la de `ros_config.sh` en `scripts/build/Dockerfile.modules`:

```dockerfile
COPY ./packages/robot_bringup/scripts/ros2_yaml_completion.bash /usr/local/bin/ros2_yaml_completion.bash
```

> Usad **A o B, no las dos**. Ejecutar `configure_bringup.sh` **sobrescribe** `~/bringup.sh` y `~/ros_config.sh` con los del repo: para que los cambios de las secciones 2 y 3 sobrevivan, hay que llevarlos también a `scripts/bringup.sh` y a `settings/robot_params/bringup.env` del repo.

### Comprobar y deshacer

```bash
complete -p ros2      # debe mostrar:  ... -F _ros2_yaml_quote ros2
```

Y probar: `ros2 service call /robot/rosmon2_devices/start_stop rosmon2_msgs/srv/StartStop ` seguido de TAB. Si se vuelve a cargar el entorno ROS en la misma terminal, el completado original se restablece: repetid `source ~/.ros2_yaml_completion.bash`. Para deshacerlo, quitad la línea de `~/.bashrc` (o los cambios 2 y 3 de la opción B) y abrid una terminal nueva.

---

## 5. Comprobación final

Con el bringup relanzado:

```bash
screen -ls                                   # una screen por grupo
screen -r navigation                         # nodos con color y sin el prefijo del robot (salir: Ctrl-A, D)
mon2 status --session navigation             # responde con el estado de los nodos
ros2 node info /robot/rosmon2_navigation     # muestra el servicio start_stop y el topic state
```

Al arrancar, si algún grupo de la lista no puede usar rosmon2, aparece el aviso `mon2 (rosmon2) not found` y ese grupo se lanza con `ros2 launch`: el entorno del bringup no carga el workspace (sección 1). Sin ese aviso, el grupo corre con rosmon2, y `screen -r <grupo>` lo confirma.
