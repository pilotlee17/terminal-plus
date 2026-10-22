#!/usr/bin/env python3
"""Isolated real tmux/PTY checks. Never touches the user's tmux server."""
import fcntl
import os
from pathlib import Path
import pty
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import uuid

tmux = shutil.which('tmux')
assert tmux, 'tmux is required'
socket = 'tiles-test-' + uuid.uuid4().hex
base = [tmux, '-L', socket, '-f', '/dev/null']
env = dict(os.environ, TERM='xterm-256color')
env.pop('TMUX', None)

def run(*args):
    return subprocess.check_output(base + list(args), env=env, stderr=subprocess.STDOUT, timeout=5).decode().strip()

def eventually(check):
    for _ in range(30):
        if check():
            return
        time.sleep(.1)
    raise AssertionError('condition timed out')

try:
    with tempfile.TemporaryDirectory(prefix='tiles-smoke-') as temp:
        folder = Path(temp) / "project 'quoted'; $(touch INJECTED) 中文"
        folder.mkdir()
        fixture = Path(temp) / "fake codex 'quoted'"
        fixture.write_text('#!/bin/sh\nprintf "PTY_READY 中文\\n"\nexec /bin/cat\n')
        fixture.chmod(0o755)
        run('new-session', '-d', '-s', 'one', '-c', str(folder), '-x', '100', '-y', '30', '/usr/bin/env', str(fixture))
        run('set-option', '-t', 'one', 'status', 'off')
        run('new-session', '-d', '-s', 'two', '-c', temp, '/bin/cat', '-u')
        eventually(lambda: 'PTY_READY 中文' in run('capture-pane', '-p', '-t', 'one'))
        actual = run('display-message', '-p', '-t', 'one', '#{pane_current_path}')
        assert Path(actual).resolve() == folder.resolve(), (actual, str(folder))
        assert not (folder / 'INJECTED').exists()
        print('PASS: real PTY, Unicode output, literal special-character cwd and executable')

        run('send-keys', '-t', 'one', '-l', 'ONLY_IN_ONE')
        run('send-keys', '-t', 'one', 'Enter')
        eventually(lambda: 'ONLY_IN_ONE' in run('capture-pane', '-p', '-t', 'one'))
        assert 'ONLY_IN_ONE' not in run('capture-pane', '-p', '-t', 'two')
        print('PASS: independent session input/output')

        pane_pid = run('display-message', '-p', '-t', 'one', '#{pane_pid}')
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        client = subprocess.Popen(base + ['attach-session', '-t', '=one'], stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        try:
            eventually(lambda: run('display-message', '-p', '-t', 'one', '#{pane_width}') == '80')
            client.terminate(); client.wait(timeout=5)
        finally:
            if client.poll() is None: client.kill(); client.wait()
            os.close(master); os.close(slave)
        assert run('display-message', '-p', '-t', 'one', '#{pane_pid}') == pane_pid
        assert 'ONLY_IN_ONE' in run('capture-pane', '-p', '-t', 'one')
        print('PASS: terminal resize, client exit preserves process and scrollback')

        run('kill-session', '-t', '=two')
        assert run('display-message', '-p', '-t', 'one', '#{pane_pid}') == pane_pid
        print('PASS: closing one session preserves the other')
finally:
    subprocess.run(base + ['kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
