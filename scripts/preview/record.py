# Records the preview scene: screen video plus the app's own sound log, on one clock.
#   python3 -I scripts/preview/record.py <udid> <app> <outdir> <seconds> [launch args...]   (make.sh runs it)
import subprocess, sys, time, signal, os, threading
udid, app, out, seconds = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
extra = sys.argv[5:]
sim = lambda *a: subprocess.run(["xcrun", "simctl", *a], capture_output=True, text=True)
sim("terminate", udid, "com.carriage.app"); sim("uninstall", udid, "com.carriage.app"); sim("install", udid, app)
sim("status_bar", udid, "override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100", "--cellularBars", "4", "--wifiBars", "3")
video = os.path.join(out, "screen.mov")
rec = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", video], stderr=subprocess.PIPE, text=True)
started = None
for line in rec.stderr:
    if "Recording started" in line:
        started = time.clock_gettime(time.CLOCK_UPTIME_RAW); break
threading.Thread(target=lambda: rec.stderr.read(), daemon=True).start()
print("recording at", started, "mach", time.clock_gettime(time.CLOCK_MONOTONIC_RAW))
time.sleep(0.6)
sim("launch", udid, "com.carriage.app", "-seedDemo", "-seenOnboarding", "YES", "-seenFocusSetup", "YES", "-foldSimulation", "regular", "-unlocked", "-lampHour", "13", "-previewScript", *extra)
time.sleep(seconds)
rec.send_signal(signal.SIGINT); rec.wait()
data = sim("get_app_container", udid, "com.carriage.app", "data").stdout.strip()
for f in ["preview-sound.wav", "preview-sound.txt"]:
    subprocess.run(["cp", os.path.join(data, "Documents", f), out])
first = float(open(os.path.join(out, "preview-sound.txt")).read().split()[0])
print("first sound", first, "offset into video", first - started)
open(os.path.join(out, "offset.txt"), "w").write(str(first - started))
sim("status_bar", udid, "clear")
