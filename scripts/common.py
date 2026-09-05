#!/usr/bin/env python3
"""common.py, helpers imported by the other scripts.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path


# The project root is the folder above this one, because this file lives in
# scripts/. __file__ is the path to this file, so we can find it whatever
# directory the user happened to be in when they ran the script:
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# The script that was actually run, resolved to an absolute path before
# anything has a chance to change directory with os.chdir().
INVOKED_SCRIPT = Path(sys.argv[0]).resolve()


def chdir_to_project_root():
    """Run from the project root no matter where the script was called from."""
    os.chdir(PROJECT_ROOT)


# ---------------------------------------------------------------------------
# Terminal Colours
# ---------------------------------------------------------------------------
# Colours are escape codes. If output is redirected to a file, printing them
# would fill the file with garbage like ESC[32m, so we only enable them when
# stdout is a real terminal.

def _colours_supported():
    # Is anyone actually looking at a terminal? If the output is being piped or
    # redirected into a file, there is nobody to see the colour:
    if not sys.stdout.isatty():
        return False
    # Windows consoles need escape codes switched on first. On macOS and Linux
    # the terminal handles them with no help from us:
    if sys.platform == "win32":
        return _enable_windows_escape_codes()

    return True

def _enable_windows_escape_codes():
    """Switch on escape-code handling in a Windows console, and report whether
    that worked.
    """
    try:
        # ctypes lets Python call the Windows API directly.
        import ctypes
        # kernel32 is the Windows library that holds the console functions:
        kernel32 = ctypes.windll.kernel32
        # The setting that makes a console interpret escape codes rather than
        # printing them literally:
        ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        # -11 is a constant for standard output:
        handle = kernel32.GetStdHandle(-11)
        # Read the console's current settings into `mode`. This fails on
        # consoles older than Windows 10 v1511, which cannot do escape codes:
        mode = ctypes.c_uint32()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        # Add our setting to whatever was already there (OR it in):
        return bool(kernel32.SetConsoleMode(
            handle, mode.value | ENABLE_VIRTUAL_TERMINAL_PROCESSING))
    except Exception:
        return False

if _colours_supported():
    C_OFF = "\033[0m"
    C_BOLD = "\033[1m"
    C_DIM = "\033[2m"
    C_PASS = "\033[1;32m"       # green
    C_FAIL = "\033[1;31m"       # red
    C_WARN = "\033[1;33m"       # yellow
    C_INFO = "\033[1;36m"       # cyan
else:
    # No colour support, so make the colour escape code variables empty strings:
    C_OFF = C_BOLD = C_DIM = C_PASS = C_FAIL = C_WARN = C_INFO = ""

def info(message):
    """Print a normal progress message:"""
    # flush=True: without it, a message printed right before we spawn a
    # subprocess (podman, verilator, ...) can sit in our own buffer and appear
    # AFTER that subprocess's output once stdout is not a live terminal --
    # e.g. piped through `tail`, or redirected to a log file.
    print(f"{C_INFO}=={C_OFF} {message}", flush=True)


def warn(message):
    """Print a warning:"""
    print(f"{C_WARN}!!{C_OFF} {message}", flush=True)


def abort(message, code=1):
    """Print a warning and stop the script immediately.
    """
    warn(message)
    sys.exit(code)


# ---------------------------------------------------------------------------
# Finding source files
# ---------------------------------------------------------------------------

def collect_verilog_files(*directories):
    """Every .v/.sv file in the directories given, as a sorted list of paths.
    Skips hidden files whose name starts with a dot.
    """
    found = []
    for directory in directories:
        for suffix in ("*.v", "*.sv"):
            found += sorted(p for p in Path(directory).glob(suffix)
                            if not p.name.startswith("."))
    return found


def tb_name(path):
    """The module name of a testbench file is its name without the extension.
    E.g. Path("tb/tb_blinker.sv").stem is "tb_blinker".
    """
    return Path(path).stem


def collect_testbenches():
    """Every testbench in tb/. Stops the script if there are none.
    """
    testbenches = collect_verilog_files("tb")
    if not testbenches:
        abort("No testbenches found in tb/")
    return testbenches


def select_testbenches(testbenches, wanted):
    """Narrow the list to the testbenches named on the command line.
    Stops the script if a name matches no file in tb/
    """
    if not wanted:
        return testbenches
    by_name = {tb_name(t): t for t in testbenches}
    selected = []
    for name in wanted:
        if name not in by_name:
            abort(f"No testbench called '{name}' in tb/")
        selected.append(by_name[name])
    return selected


# ---------------------------------------------------------------------------
# Running other programs
# ---------------------------------------------------------------------------

def require_tool(name, advice):
    """Check a program is installed before we try to use it.
    """
    if shutil.which(name) is None:
        abort(f"'{name}' is not installed or not on your PATH.\n   {advice}")


def verilator_advice():
    """The right require_tool("verilator", ...) message for this platform.
    """
    if sys.platform == "win32":
        return ("It has no native Windows build at all, so there is no way to "
                "install it directly here. Install Podman or Docker so this "
                "script can build a container for you instead -- see README.")
    return ("Locally, install Podman or Docker so "
            "this script can build a container for you (see README).")


def run(command, cwd=None, capture=False, stdin=None):
    """Run a program and return the completed process.
    """
    return subprocess.run(command, cwd=cwd, text=True, stdin=stdin,
                          stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.STDOUT if capture else None)


# ---------------------------------------------------------------------------
# Container for Verilator (Podman or Docker)
# ---------------------------------------------------------------------------
# The scripts that need Verilator will re-run themselves inside the container.
# This helps Windows and macOS users avoid the pain of installing a C++ toolchain
# and the lz4 headers that Verilator's FST waveform writer needs.

IMAGE = "mtrx3700-verilator"

def setup_native_macos_verilator_env():
    """Make a native (non-container) Verilator work on macOS with Homebrew.

    Verilator's FST waveform writer #includes <lz4.h>, but Homebrew is not a
    system location, so the compiler does not look there on its own -- and
    Homebrew's verilator does not even depend on lz4. If Homebrew's lz4 is
    installed, point the compiler at it via the environment (clang reads both
    of these variables); if not, the build fails with a hint (see ERROR_HINTS).
    """
    if sys.platform != "darwin":
        return
    for prefix in ("/opt/homebrew", "/usr/local"):    # Apple silicon, Intel
        if Path(prefix, "include", "lz4.h").exists():
            for var, sub in (("CPLUS_INCLUDE_PATH", "include"),
                             ("LIBRARY_PATH", "lib")):
                path = f"{prefix}/{sub}"
                current = os.environ.get(var, "")
                if path not in current.split(":"):
                    os.environ[var] = f"{current}:{path}" if current else path
            return

def container_runtime():
    """"podman", "docker", whichever is on the PATH, or None if neither is.
    Prefer Podman.
    """
    for name in ("podman", "docker"):
        if shutil.which(name) is not None:
            return name
    return None


def _native_verilator_fallback(problem, fix):
    """When the container runtime has a problem: fall back to the native
    verilator if there is one, otherwise stop with instructions.
    """
    if shutil.which("verilator") is not None:
        warn(f"{problem} Using the native verilator instead.")
        setup_native_macos_verilator_env()
        return
    abort(f"{problem}\n   {fix}")


def run_verilator_container_if_available(env=None):
    """If Podman or Docker is installed and working, re-run the script inside
    the project's container instead of natively, and exit with whatever exit
    code that produced. Otherwise do nothing, so the calling script falls
    through to trying Verilator natively.

    `env`, if given, is a dict of environment variables passed into the
    container with -e.

    Call this once, near the top of main(), before require_tool("verilator", ...).
    """
    runtime = container_runtime()
    if runtime is None:
        setup_native_macos_verilator_env()
        return

    # Check the container runtime is actually running:
    if run([runtime, "info"], capture=True).returncode != 0:
        if runtime == "podman":
            _native_verilator_fallback(
                "podman is installed but its VM is not running.",
                "Start it with: podman machine start\n"
                "   (the first time, run 'podman machine init' first)")
        else:
            _native_verilator_fallback(
                "docker is installed but not running.",
                "macOS/Windows: start Docker Desktop.\n"
                "   Linux:         sudo systemctl start docker")
        return

    # Build on first use. Later runs reuse the image, so this is a one-off:
    if run([runtime, "image", "inspect", IMAGE], capture=True).returncode != 0:
        info(f"Building the {IMAGE} image (first run only, ~1 minute)")
        if run([runtime, "build", "-t", IMAGE,
               "-f", "scripts/Containerfile", "."],
              cwd=PROJECT_ROOT).returncode != 0:
            _native_verilator_fallback(
                f"Building the {IMAGE} image failed (see above).",
                "Fix the container build, or install Verilator natively.")
            return

    # PROJECT_ROOT is mounted at /work, so the script path must be relative to
    # it, and Linux-style even when we are computing it on Windows:
    script = INVOKED_SCRIPT.relative_to(PROJECT_ROOT).as_posix()

    # -t only when our own stdout is a terminal, so the container still
    # produces colour interactively without writing escape codes into a log:
    tty_flag = ["-t"] if sys.stdout.isatty() else []

    # -e KEY=VALUE for each item in `env`, so the container's own re-exec of
    # this script can read them back with os.environ:
    env_flags = []
    for key, value in (env or {}).items():
        env_flags += ["-e", f"{key}={value}"]

    info(f"Running in the {IMAGE} container ({runtime})")

    result = run([
        runtime, "run", "--rm", *tty_flag, *env_flags,
        "-v", f"{PROJECT_ROOT}:/work",
        "-w", "/work",
        IMAGE, "python3", script, *sys.argv[1:],
    ])
    sys.exit(result.returncode)


# ---------------------------------------------------------------------------
# Keeping score in the test runners
# ---------------------------------------------------------------------------

# Some tool errors are accurate but give you no idea what to change. When one of
# these strings turns up in a failing log, we print the explanation underneath
# it. Add your own as you meet them.
ERROR_HINTS = [
    ("BADVLTPRAGMA",
     'A comment LINE starting with the word "verilator" is read as a tool\n'
     "      pragma rather than a comment, and the build stops. Reword the line so\n"
     "      it starts with a different word."),
    ("lz4.h",
     "Verilator's waveform writer needs the lz4 library headers, which are\n"
     "      not installed (they are not a dependency of Verilator itself).\n"
     "      macOS:  brew install lz4        (then just re-run this script)\n"
     "      Linux:  sudo apt install liblz4-dev\n"
     "      Or install Podman and the script will use its container instead."),
]

class Scoreboard:
    """Counts passes and failures, and prints the result lines."""

    # How many lines of a failed log to show, so the reason is visible without
    # having to open the file:
    TAIL_LINES = 12

    def __init__(self):
        self.passed = 0
        self.failed = 0

    def check_log(self, testbench, log_path, shown_path=None):
        """Score one testbench by reading its log file.
        The pass criterion is the string "ALL TESTS PASSED" that the testbench
        prints when it reaches the end without a $fatal().
        """
        log_path = Path(log_path)
        shown_path = shown_path or log_path
        text = log_path.read_text(errors="replace") if log_path.exists() else ""

        if "ALL TESTS PASSED" in text:
            print(f"{C_PASS}PASS{C_OFF}  {testbench}")
            self.passed += 1
        else:
            print(f"{C_FAIL}FAIL{C_OFF}  {testbench}   {C_DIM}-> see {shown_path}{C_OFF}")
            for line in text.splitlines()[-self.TAIL_LINES:]:
                print(f"      {C_DIM}|{C_OFF} {line}")

            # Explain any error that is hard to act on:
            for needle, hint in ERROR_HINTS:
                if needle in text:
                    print(f"      {C_WARN}hint:{C_OFF} {hint}")

            self.failed += 1

    def summary(self):
        """Print the tally and return an exit code: 0 if everything passed."""
        print()
        if self.failed == 0:
            print(f"{C_PASS}{self.passed} passed, 0 failed{C_OFF}")
        else:
            print(f"{C_PASS}{self.passed} passed{C_OFF}, {C_FAIL}{self.failed} failed{C_OFF}")
        return 0 if self.failed == 0 else 1


# ---------------------------------------------------------------------------
# Verilator build directory
# ---------------------------------------------------------------------------

SIM_VERILATOR_FOLDER = Path("sim_verilator")

# The flags both Verilator scripts use, and why each one is there:
#
#   -Wall               Turn on all the style/lint warnings. Verilator is a much
#                       stricter linter than Quartus or ModelSim, so treat its
#                       warnings as good code review. Read them.
#   --Wno-fatal         ...but do not stop the build on a warning. Remove this
#                       flag if you want to force yourself to fix every one.
#   --Wno-TIMESCALEMOD  Silences "some modules have a `timescale and some do
#                       not". The lesson modules are inconsistent about it and
#                       it does not affect results.
#   --timing            REQUIRED for testbenches that use # delays (e.g.
#                       `always #10 clk = ~clk;`). Without it the testbench will not
#                       build.
#   --assert            Enables SystemVerilog immediate/concurrent assertions.
#   --trace-fst         Enables $dumpvars, so we can write waveforms. FST is
#                       a compressed format: far smaller and quicker to load
#                       than VCD, and both Surfer and GTKWave read it.
VERILATOR_FLAGS = [
    "-Wall", "--Wno-fatal", "--Wno-TIMESCALEMOD",
    "--timing", "--assert", "--trace-fst",
]


def verilator_build_dir():
    """Make sure sim_verilator/ exists and was built by the Verilator we are
    about to use.

    Verilator writes absolute paths to its own installation into the makefiles
    it generates. A stamp file records which Verilator built the directory,
    so we know to start fresh whenever it changes.
    """
    stamp = SIM_VERILATOR_FOLDER / ".toolchain"

    version = run(["verilator", "--version"], capture=True)
    toolchain = f"{shutil.which('verilator')}:{version.stdout.strip()}"

    if not stamp.exists() or stamp.read_text() != toolchain:
        shutil.rmtree(SIM_VERILATOR_FOLDER, ignore_errors=True)
        SIM_VERILATOR_FOLDER.mkdir(parents=True, exist_ok=True)
        stamp.write_text(toolchain)

    # "Verilator 5.050 2026-07-01 rev ..." -> "Verilator 5.050", for messages:
    return " ".join(version.stdout.split()[:2])
