#!/usr/bin/env python3

import os
import platform
import subprocess
import sys


def is_wsl() -> bool:
    return platform.system() == "Linux" and (
        "microsoft" in platform.release().lower()
        or "WSL_DISTRO_NAME" in os.environ
    )


def main() -> int:
    # Drain the Stop hook payload so large assistant messages cannot fill the pipe.
    sys.stdin.read()

    try:
        if platform.system() == "Darwin":
            import fcntl

            with open(f"/tmp/codex-notify-{os.getuid()}.lock", "w") as dialog_lock:
                try:
                    fcntl.flock(dialog_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    # The dialog inherits the fd, keeping the lock until it closes.
                    subprocess.Popen(
                        [
                            "/usr/bin/osascript",
                            "-e",
                            "activate",
                            "-e",
                            'display dialog "Task complete." with title "Codex" buttons {"OK"} '
                            'default button "OK" with icon note',
                        ],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        pass_fds=(dialog_lock.fileno(),),
                    )
            subprocess.run(
                ["/usr/bin/afplay", "/System/Library/Sounds/Glass.aiff"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        elif is_wsl():
            script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$notification = New-Object System.Windows.Forms.NotifyIcon
$notification.Icon = [System.Drawing.SystemIcons]::Information
$notification.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
$notification.BalloonTipTitle = 'Codex'
$notification.BalloonTipText = 'Task complete.'
$notification.Visible = $true

[System.Media.SystemSounds]::Asterisk.Play()
$notification.ShowBalloonTip(5000)

Start-Sleep -Seconds 5
$notification.Dispose()
'''
            subprocess.Popen(
                ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except OSError:
        pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
