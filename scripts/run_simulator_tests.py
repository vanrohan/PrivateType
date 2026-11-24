"""Run simulator tests. Stop the process group at the first crash restart."""

import os
import signal
import subprocess
import sys
import time


def stop(process, timeout=5):
    try:
        os.killpg(process.pid, signal.SIGTERM)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            process.poll()
            os.killpg(process.pid, 0)
            time.sleep(0.05)
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        process.poll()
        rows = subprocess.check_output(["ps", "-axo", "pgid=,stat="], text=True).splitlines()
        members = [row.split() for row in rows if row.strip()]
        if any(group == str(process.pid) and not state.startswith("Z") for group, state in members):
            raise
    process.wait()


def run(command):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            if "Restarting after unexpected exit, crash, or test timeout" in line:
                stop(process)
                print("Stopped the test run after a crash. Fix it before another run.", flush=True)
                return 1
        return process.wait()
    except KeyboardInterrupt:
        stop(process)
        return 130
    finally:
        process.stdout.close()


if __name__ == "__main__":
    arguments = [
        "xcodebuild", "-project", "SimpleKeyboard.xcodeproj", "-scheme", "SimpleKeyboard",
        "-destination", "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2",
        "-derivedDataPath", "/tmp/privatetype-public-tests", "-parallel-testing-enabled", "NO",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    raise SystemExit(run(arguments + sys.argv[1:] + ["test"]))
