#!/usr/bin/python3

# joystick. py - joystick "driver" for switch-scan.el
# based conceptually on https://www.emacswiki.org/emacs/joystick.el
# produces elisp sexps on standard output to communicate with the Emacs master
# in response to joystick button events
# command: joystick.py M N
# M=joystick number N=button number

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


import time
import ctypes
import sys
import platform

joy_id = int(sys.argv[1])
btn_id = int(sys.argv[2])


def error(s):
    sys.stdout.write('(progn (message "%s") (setq sscan-thread-flag nil))\n' % s)
    sys.stdout.flush()
    sys.exit(1)

    
def msg(s):
    sys.stdout.write("(message \"%s\")\n" % s)
    sys.stdout.flush()    

    
def pressed():
    sys.stdout.write("(setq sscan-pressed-flag t)\n")
    sys.stdout.flush()    

    
def unpressed():
    sys.stdout.write("(setq sscan-unpressed-flag t)\n")
    sys.stdout.flush()    

    
if platform.system() == "Windows":
    # source https://gist.github.com/rdb/8883307
    # Released by rdb under the Unlicense (unlicense.org)
    # Further reading about the WinMM Joystick API:
    # http://msdn.microsoft.com/en-us/library/windows/desktop/dd757116(v=vs.85).aspx
    from ctypes.wintypes import DWORD

    JOY_RETURNBUTTONS = 0x80

    # Fetch function pointers
    joyGetNumDevs = ctypes.windll.winmm.joyGetNumDevs
    joyGetPosEx = ctypes.windll.winmm.joyGetPosEx

    class JOYINFOEX(ctypes.Structure):
        _fields_ = [
            ("dwSize", DWORD),
            ("dwFlags", DWORD),
            ("dwXpos", DWORD),
            ("dwYpos", DWORD),
            ("dwZpos", DWORD),
            ("dwRpos", DWORD),
            ("dwUpos", DWORD),
            ("dwVpos", DWORD),
            ("dwButtons", DWORD),
            ("dwButtonNumber", DWORD),
            ("dwPOV", DWORD),
            ("dwReserved1", DWORD),
            ("dwReserved2", DWORD),
        ]

    # Get the number of supported devices (usually 16).
    num_devs = joyGetNumDevs()
    if num_devs == 0:
        error("Joystick driver not loaded.")
    msg("Windows joystick")

    # Initialise the JOYINFOEX structure.
    info = JOYINFOEX()
    info.dwSize = ctypes.sizeof(JOYINFOEX)
    info.dwFlags = JOY_RETURNBUTTONS
    p_info = ctypes.pointer(info)

    prev_pressed = 0
    while True:
        if joyGetPosEx(joy_id, p_info) != 0:
            error("joystick %d not available" % joy_id)
        npressed = 0 != (1 << btn_id) & info.dwButtons
        if npressed and not prev_pressed:
            pressed()
        elif prev_pressed and not npressed:
            unpressed()
        prev_pressed = npressed
        time.sleep(0.01)

elif platform.system() == "Linux":
    # source https://gist.github.com/rdb/8864666
    # Released by rdb under the Unlicense (unlicense.org)
    # Based on information from:
    # https://www.kernel.org/doc/Documentation/input/joystick-api.txt

    import struct
    import array
    from fcntl import ioctl

    try:
        # Open the joystick device.
        fn = "/dev/input/js%d" % joy_id
        jsdev = open(fn, "rb")
        msg("Linux joystick")

        # Get number of buttons
        buf = array.array("B", [0])
        ioctl(jsdev, 0x80016A12, buf)  # JSIOCGBUTTONS
        num_buttons = buf[0]

        # Get the button map.
        buf = array.array("H", [0] * 200)
        ioctl(jsdev, 0x80406A34, buf)  # JSIOCGBTNMAP

        # Main event loop
        while True:
            evbuf = jsdev.read(8)
            if evbuf:
                time, value, type, number = struct.unpack("IhBB", evbuf)
                if type & 0x01 and number == btn_id:
                    if value:
                        pressed()
                    else:
                        unpressed()
    except (IOError, OSError) as e:
        error(str(e))
else:
    error("unrecognised platform %s" % platform.system())
