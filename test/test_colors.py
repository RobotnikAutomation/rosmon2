from rosmon2.terminal import COLOR_MODES, bg, detect_color_mode, fg, styles


def test_terminals_announcing_truecolor_get_truecolor():
    assert detect_color_mode({'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'}) == 'truecolor'
    assert detect_color_mode({'TERM': 'xterm', 'COLORTERM': '24bit'}) == 'truecolor'


def test_screen_never_gets_truecolor_even_if_it_inherits_colorterm():
    assert detect_color_mode(
        {'TERM': 'screen', 'COLORTERM': 'truecolor', 'STY': '123.devices'}) == '256'
    assert detect_color_mode(
        {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'STY': '1.x'}) == '256'
    assert detect_color_mode({'TERM': 'screen-256color', 'COLORTERM': 'truecolor'}) == '256'


def test_fallback_to_256_and_16_colors():
    assert detect_color_mode({'TERM': 'xterm-256color'}) == '256'
    assert detect_color_mode({'TERM': 'xterm'}) == '16'
    assert detect_color_mode({'TERM': 'linux'}) == '16'
    assert detect_color_mode({}) == '16'


def test_rosmon2_colors_overrides_the_detection():
    assert detect_color_mode(
        {'TERM': 'screen', 'STY': '1.x', 'ROSMON2_COLORS': 'truecolor'}) == 'truecolor'
    assert detect_color_mode(
        {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor', 'ROSMON2_COLORS': '16'}) == '16'
    assert detect_color_mode({'TERM': 'xterm', 'ROSMON2_COLORS': 'bogus'}) == '16'


def test_color_codes_for_each_mode():
    assert fg(24, 178, 24, 'truecolor') == '\x1b[38;2;24;178;24m'
    assert bg(24, 178, 24, 'truecolor') == '\x1b[48;2;24;178;24m'
    assert bg(0, 0, 0, '256') == '\x1b[48;5;16m'
    assert fg(255, 255, 255, '256') == '\x1b[38;5;231m'
    assert bg(0, 0, 0, '16') == '\x1b[40m'
    assert fg(255, 255, 255, '16') == '\x1b[97m'


def test_green_and_red_stay_green_and_red_in_reduced_palettes():
    assert bg(24, 178, 24, '256') == '\x1b[48;5;34m'
    assert bg(178, 24, 24, '256') == '\x1b[48;5;124m'
    assert bg(24, 178, 24, '16') == '\x1b[42m'
    assert bg(178, 24, 24, '16') == '\x1b[41m'


def test_reduced_palettes_never_emit_truecolor_sequences():
    for mode in ('256', '16'):
        assert all(';2;' not in value for value in styles(mode).values())
    assert all(';2;' in value for value in styles('truecolor').values())


def test_state_styles_stay_distinguishable_in_every_mode():
    for mode in COLOR_MODES:
        palette = styles(mode)
        assert len({palette[name] for name in ('RUNNING', 'CRASHED', 'PARTIAL', 'IDLE')}) == 4
