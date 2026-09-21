"""Pin the color mode so the style assertions do not depend on the terminal running pytest."""

import os

os.environ['ROSMON2_COLORS'] = 'truecolor'
