#!/usr/bin/env python3

import json
import os
import platform
import re
import subprocess
import sys


def is_wsl() -> bool:
    return platform.system() == "Linux" and (
        "microsoft" in platform.release().lower()
        or "WSL_DISTRO_NAME" in os.environ
    )


def conversation_deep_link(hook_input: object) -> str | None:
    if not isinstance(hook_input, dict):
        return None
    session_id = hook_input.get("session_id")
    if not isinstance(session_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", session_id):
        return None
    if (
        os.environ.get("__CFBundleIdentifier") == "com.microsoft.VSCode"
        or os.environ.get("TERM_PROGRAM") == "vscode"
        or any(name.startswith("VSCODE_") for name in os.environ)
    ):
        return f"vscode://openai.chatgpt/local/{session_id}"
    return f"codex://threads/{session_id}"


WINDOWS_DIALOG = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$createdNew = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\CodexCompletionDialog', [ref]$createdNew)
if (-not $createdNew) {
    $mutex.Dispose()
    exit 0
}

try {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Codex'
    $form.ClientSize = New-Object System.Drawing.Size(340, 125)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.TopMost = $true

    $message = New-Object System.Windows.Forms.Label
    $message.AutoSize = $true
    $message.Location = New-Object System.Drawing.Point(24, 24)
    $message.Text = 'Task complete.'
    $form.Controls.Add($message)

    $ok = New-Object System.Windows.Forms.Button
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(241, 76)
    $ok.Size = New-Object System.Drawing.Size(75, 28)
    $ok.Text = 'OK'
    $form.AcceptButton = $ok
    $form.CancelButton = $ok
    $form.Controls.Add($ok)

    if ($env:CODEX_NOTIFY_DEEP_LINK) {
        $open = New-Object System.Windows.Forms.Button
        $open.Location = New-Object System.Drawing.Point(158, 76)
        $open.Size = New-Object System.Drawing.Size(75, 28)
        $open.Text = 'Open'
        $open.Add_Click({
            try {
                if (-not $env:CODEX_NOTIFY_EDITOR_URI) {
                    throw 'No editor URI'
                }
                $code = Get-Command code.cmd -ErrorAction SilentlyContinue
                if (-not $code) {
                    $code = Get-Command code -ErrorAction Stop
                }
                & $code.Source --reuse-window --open-url $env:CODEX_NOTIFY_EDITOR_URI
            }
            catch {
                Start-Process -FilePath $env:CODEX_NOTIFY_DEEP_LINK
            }
            $form.Close()
        })
        $form.Controls.Add($open)
    }

    [System.Media.SystemSounds]::Asterisk.Play()
    [void]$form.ShowDialog()
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
'''


def main() -> int:
    try:
        hook_input = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, TypeError):
        hook_input = {}
    deep_link = conversation_deep_link(hook_input)
    editor_uri = (
        deep_link.replace("vscode://openai.chatgpt/local/", "openai-codex://route/local/", 1)
        if deep_link and deep_link.startswith("vscode://")
        else None
    )

    try:
        if platform.system() == "Darwin":
            import fcntl

            with open(f"/tmp/codex-notify-{os.getuid()}.lock", "w") as dialog_lock:
                try:
                    fcntl.flock(dialog_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass
                else:
                    dialog_command = ["/usr/bin/osascript", "-e", "activate"]
                    if deep_link:
                        dialog_command.extend(
                            [
                                "-e",
                                'set dialogResult to display dialog "Task complete." with title "Codex" '
                                'buttons {"Open", "OK"} default button "OK" with icon note',
                                "-e",
                                'if button returned of dialogResult is "Open" then',
                            ]
                        )
                        if editor_uri:
                            dialog_command.extend(
                                [
                                    "-e",
                                    "try",
                                    "-e",
                                    'set vscodeApp to POSIX path of '
                                    '(path to application id "com.microsoft.VSCode")',
                                    "-e",
                                    'do shell script quoted form of '
                                    '(vscodeApp & "Contents/Resources/app/bin/code") & '
                                    '" --reuse-window --open-url " & quoted form of '
                                    f'"{editor_uri}"',
                                    "-e",
                                    "on error",
                                    "-e",
                                    f'open location "{deep_link}"',
                                    "-e",
                                    "end try",
                                ]
                            )
                        else:
                            dialog_command.extend(["-e", f'open location "{deep_link}"'])
                        dialog_command.extend(["-e", "end if"])
                    else:
                        dialog_command.extend(
                            [
                                "-e",
                                'display dialog "Task complete." with title "Codex" buttons {"OK"} '
                                'default button "OK" with icon note',
                            ]
                        )
                    # The dialog inherits the fd, keeping the lock until it closes.
                    subprocess.Popen(
                        dialog_command,
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
        elif platform.system() == "Windows" or is_wsl():
            child_env = os.environ.copy()
            if deep_link:
                child_env["CODEX_NOTIFY_DEEP_LINK"] = deep_link
            else:
                child_env.pop("CODEX_NOTIFY_DEEP_LINK", None)
            if editor_uri:
                child_env["CODEX_NOTIFY_EDITOR_URI"] = editor_uri
            else:
                child_env.pop("CODEX_NOTIFY_EDITOR_URI", None)
            subprocess.Popen(
                ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", WINDOWS_DIALOG],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=child_env,
            )
    except OSError:
        pass

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
