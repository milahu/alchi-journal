#!/usr/bin/env python3

# FIXME basename input should suggest previous basename

# FIXME remove black page background
# we already can remove the white bottom rectangle with
# scripts/crop-images-bottom-white.py
r'''
small change:
instead of a white rectangle on the bottom,
i am looking for a white page bottom edge,
so when the script scans the image from bottom to top,
then it first finds a white rectangle,
then a black/darkgray trapezoid,
then the white page background,
then the page contents (in darkgray).
the script should remove as much as possible from the black background behinde the white page,
and if the script cannot remove (crop) it completely because the bottom page edge is not perfectly horizontal,
then the script should fill the remaining black rectangle with white
'''

"""
Single-pass duplex scanning of multiple pages (ADF)
"""

r'''
FIXME this is spamming the terminal:

creating large/2026-08-18.10-40.large.avif
magick /run/user/1000/scan.2026-08-23.08-12-43.021.pnm -set colorspace RGB +profile '*' -quality 40% -coalesce large/2026-08-18.10-40.large.avif
creating 2026-08-18.10-40.avif
magick /run/user/1000/scan.2026-08-23.08-12-43.021.pnm -set colorspace RGB +profile '*' -quality 40% -coalesce -scale 50% -level 40x98% 2026-08-18.10-40.avif
'''

import datetime
import getpass
import os
import re
import select
import shutil
import subprocess
import sys
import termios
import tty
from pathlib import Path


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

THIS_USER_UID = os.getuid()
THIS_USER_GID = os.getgid()

OUTPUT_USER_UID = 1000
OUTPUT_USER_GID = 100

TEMPDIR = Path(f"/run/user/{OUTPUT_USER_UID}")

KEEP_TEMPFILE = False
WRITE_LOGFILE = False

DO_CHOWN = (
    OUTPUT_USER_UID != THIS_USER_UID
    or OUTPUT_USER_GID != THIS_USER_GID
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(args, **kwargs):
    """Run a command, printing it first."""
    print("+", " ".join(shlex_quote(str(arg)) for arg in args))
    return subprocess.run(args, **kwargs)


def shlex_quote(value):
    """Shell-like quoting for display only."""
    import shlex
    return shlex.quote(value)


def timestamp():
    return datetime.datetime.now().strftime("%Y-%m-%d.%H-%M-%S")


def timestamp_utc_iso():
    return datetime.datetime.now(
        datetime.timezone.utc
    ).isoformat(timespec="seconds")


def read_char():
    """Read exactly one character without requiring Enter."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)

    try:
        tty.setraw(fd)
        return sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def read_with_default(prompt, default):
    """
    Read a line with `default` pre-filled for editing, similar to:

        read -e -p "$prompt" -i "$default" title

    Pressing Enter without changing the value returns `default`.
    """
    import readline

    readline.set_startup_hook(lambda: readline.insert_text(default))

    try:
        value = input(prompt)
    finally:
        readline.set_startup_hook(None)

    return value





def read_with_default_zzzz(prompt, default):
    """
    Similar to Bash:

        read -e -p "..." -i "$default" title

    Uses readline if available.
    """
    try:
        import readline

        readline.set_startup_hook(
            lambda: readline.insert_text(default)
        )

        try:
            return input(prompt)
        finally:
            readline.set_startup_hook()

    except Exception:
        value = input(f"{prompt}[{default}] ")
        return value if value else default


def chown_if_needed(path):
    if DO_CHOWN:
        os.chown(path, OUTPUT_USER_UID, OUTPUT_USER_GID)


def trim_and_normalize_title(title):
    # Equivalent to:
    # sed -E 's/^[ \t\r]+//; s/[ \t\r]+$//'
    title = re.sub(r"^[ \t\r]+|[ \t\r]+$", "", title)

    # Equivalent to:
    # sed -E 's/[\r]+//g; s/[ \t]+/./g'
    title = title.replace("\r", "")
    title = re.sub(r"[ \t]+", ".", title)

    return title


def page_number_from_path(path):
    """
    Extract the number from:

        scan.2023-...42.1.pnm

    returning 1.
    """
    return int(path.stem.rsplit(".", 1)[1])


def zero_pad_page_number(path, page_number_format="%03d"):
    """
    Rename:

        scan.date.1.pnm

    to:

        scan.date.001.pnm
    """
    extension = path.suffix
    without_extension = path.stem

    base, number_string = without_extension.rsplit(".", 1)
    number = int(number_string)

    new_name = (
        f"{base}."
        f"{page_number_format % number}"
        f"{extension}"
    )

    new_path = path.with_name(new_name)

    print(f"renaming {path} -> {new_path}")
    path.rename(new_path)

    return new_path, number


def start_feh(path):
    """
    Start feh without connecting it to our stdin/stdout/stderr.
    """
    return subprocess.Popen(
        ["feh", "--scale-down", str(path)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def stop_process(process):
    if process is None:
        return

    try:
        process.kill()
        process.wait(timeout=1)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        pass


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

def convert_page(
    temp_path,
    title,
    extra_convert_options,
    this_extra_convert_options,
    shared_convert_options,
    small_convert_options,
    large_convert_options,
):
    """
    Background worker corresponding to the Bash subshell:

        (
          magick ...
          magick ...
          ...
        ) &
    """
    large_dir = Path("large")
    large_dir.mkdir(parents=True, exist_ok=True)

    output_large = large_dir / f"{title}.large.avif"
    output_small = Path(f"{title}.avif")

    convert_args_large = [
        "magick",
        str(temp_path),
        *extra_convert_options,
        *shared_convert_options,
        *this_extra_convert_options,
        *large_convert_options,
        str(output_large),
    ]

    convert_args_small = [
        "magick",
        str(temp_path),
        *extra_convert_options,
        *shared_convert_options,
        *this_extra_convert_options,
        *small_convert_options,
        str(output_small),
    ]

    if 0:
        # debug
        print(f"creating {output_large}")
        print(" ".join(shlex_quote(str(arg)) for arg in convert_args_large))

        print(f"creating {output_small}")
        print(" ".join(shlex_quote(str(arg)) for arg in convert_args_small))

    try:
        subprocess.run(convert_args_large, check=True)
        chown_if_needed(output_large)

        subprocess.run(convert_args_small, check=True)
        chown_if_needed(output_small)

        if KEEP_TEMPFILE:
            print(f"keeping tempfile {temp_path}")
            chown_if_needed(temp_path)
        else:
            temp_path.unlink(missing_ok=True)

    except subprocess.CalledProcessError as exc:
        print(
            f"error: ImageMagick conversion failed: {exc}",
            file=sys.stderr,
        )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global KEEP_TEMPFILE

    # -----------------------------------------------------------------------
    # Command-line arguments
    # -----------------------------------------------------------------------

    if len(sys.argv) < 2:
        print(
            "error: missing argument: device_name",
            file=sys.stderr,
        )
        print(
            f"example use: {sys.argv[0]} brother5:bus2;dev2",
            file=sys.stderr,
        )
        print(
            "hint: use this to get the device name: scanimage -L",
            file=sys.stderr,
        )
        return 1

    device_name = sys.argv[1]

    # All remaining arguments are passed to ImageMagick.
    # Example:
    #
    #   ./scan_adf.py brother5:bus2;dev2 -rotate 90
    #
    extra_convert_options = sys.argv[2:]

    # -----------------------------------------------------------------------
    # Scanner settings
    # -----------------------------------------------------------------------

    source = "Automatic Document Feeder(left aligned,Duplex)"
    mode = "24bit Color[Fast]"
    image_format = "pnm"

    extra_options = [
        "--MultifeedDetection=yes",
        "--SkipBlankPage=no",
        "-x", "210", "-y", "297", # DIN A4
    ]

    quality = "40%"
    small_scale = "50%"
    resolution = 300

    # -----------------------------------------------------------------------
    # Image processing settings
    # -----------------------------------------------------------------------

    lowthresh = 40
    highthresh = 98

    if resolution == 300:
        crop_x = 2480
        crop_y = 3430
    elif resolution == 600:
        crop_x = 2480 * 2
        crop_y = 3430 * 2
    else:
        print(
            f"error: bad resolution {resolution}",
            file=sys.stderr,
        )
        return 1

    # crop_x/crop_y are currently intentionally unused, matching the active
    # Bash script, where the crop option is commented out.

    shared_convert_options = [
        "-set",
        "colorspace",
        "RGB",
        "+profile",
        "*",
        "-quality",
        quality,
        "-coalesce",
    ]

    small_convert_options = [
        "-scale",
        small_scale,
        "-level",
        f"{lowthresh}x{highthresh}%",
    ]

    large_convert_options = []

    # -----------------------------------------------------------------------
    # Temporary directory and scan filename format
    # -----------------------------------------------------------------------

    date_time = timestamp()

    # Original Bash does:
    #
    # mkdir /run/user/$(id --user) 2>/dev/null || true
    #
    # Do not fail if it already exists.
    Path(f"/run/user/{THIS_USER_UID}").mkdir(
        parents=True,
        exist_ok=True,
    )

    # Note that TEMPDIR intentionally remains /run/user/1000 by default,
    # matching the original script.
    temp_path_format = (
        TEMPDIR
        / f"scan.{date_time}.%d.{image_format}"
    )

    page_number_format = "%03d"

    # -----------------------------------------------------------------------
    # Build scanimage command
    # -----------------------------------------------------------------------

    scanimage_args = [
        "scanimage",
        f"--device-name={device_name}",
        f"--resolution={resolution}",
        f"--format={image_format}",
        f"--batch={temp_path_format}",
        "--batch-print",
        f"--mode={mode}",
        f"--source={source}",
        *extra_options,
    ]

    print(
        " ".join(
            shlex_quote(str(arg))
            for arg in scanimage_args
        ),
        file=sys.stderr,
    )

    if WRITE_LOGFILE:
        scanimage_log_path = (
            TEMPDIR
            / f"scanimage.{timestamp_utc_iso()}.log"
        )

        print(
            f"writing scanimage log to {scanimage_log_path}",
            file=sys.stderr,
        )

        scan_stderr = open(scanimage_log_path, "w")

    else:
        scan_stderr = subprocess.PIPE

    # -----------------------------------------------------------------------
    # Start scanimage
    # -----------------------------------------------------------------------

    process = subprocess.Popen(
        scanimage_args,
        stdout=subprocess.PIPE,
        stderr=scan_stderr,
        text=True,
        bufsize=1,
    )

    conversion_processes = []
    last_title = None

    try:
        if WRITE_LOGFILE:
            # We only need to wait. The logfile receives stderr.
            assert process.stdout is not None

            for line in process.stdout:
                temp_path_string = line.strip()

                if not temp_path_string:
                    continue

                conversion_processes, last_title = process_scanned_page(
                    temp_path_string,
                    conversion_processes,
                    last_title,
                    page_number_format,
                    extra_convert_options,
                    shared_convert_options,
                    small_convert_options,
                    large_convert_options,
                )

        else:
            assert process.stdout is not None
            assert process.stderr is not None

            # scanimage --batch-print writes scanned filenames to stdout.
            #
            # Read stdout and stderr concurrently so scanner messages do not
            # block the process.
            streams = [process.stdout, process.stderr]

            while streams:
                readable, _, _ = select.select(streams, [], [])

                for stream in readable:
                    line = stream.readline()

                    if line == "":
                        streams.remove(stream)
                        continue

                    line = line.rstrip("\n")

                    if stream is process.stdout:
                        temp_path_string = line.strip()

                        if not temp_path_string:
                            continue

                        conversion_processes, last_title = (
                            process_scanned_page(
                                temp_path_string,
                                conversion_processes,
                                last_title,
                                page_number_format,
                                extra_convert_options,
                                shared_convert_options,
                                small_convert_options,
                                large_convert_options,
                            )
                        )

                    else:
                        # Equivalent to:
                        #
                        # grep -v -E "^(Scanning page|Scanned page|...)"
                        ignored = (
                            "Scanning page",
                            "Scanned page",
                            "scanimage: sane_read: "
                            "Document feeder out of documents",
                            "Batch terminated",
                        )

                        if not line.startswith(ignored):
                            print(line, file=sys.stderr)

    finally:
        if WRITE_LOGFILE and scan_stderr is not subprocess.PIPE:
            scan_stderr.close()

    return_code = process.wait()

    # -----------------------------------------------------------------------
    # Wait for all background conversions
    # -----------------------------------------------------------------------

    for conversion_process in conversion_processes:
        conversion_process.join()

    return return_code


def process_scanned_page(
    temp_path_string,
    conversion_processes,
    last_title,
    page_number_format,
    extra_convert_options,
    shared_convert_options,
    small_convert_options,
    large_convert_options,
):
    """
    Handle one filename emitted by scanimage --batch-print.
    """

    import multiprocessing

    temp_path = Path(temp_path_string)

    print(f"temp path: {temp_path}")

    # -----------------------------------------------------------------------
    # Add zero padding to the page number
    # -----------------------------------------------------------------------

    try:
        temp_path, temp_path_number = zero_pad_page_number(
            temp_path,
            page_number_format,
        )
    except (ValueError, FileNotFoundError) as exc:
        print(
            f"error: cannot process scanned path {temp_path}: {exc}",
            file=sys.stderr,
        )
        return conversion_processes, last_title

    # -----------------------------------------------------------------------
    # Show image
    # -----------------------------------------------------------------------

    feh_process = start_feh(temp_path)

    this_extra_convert_options = []

    print("  e = edit the image with gimp")
    print("  k = delete the image")
    print("  r = rotate by 90 degrees to the right = clockwise")
    print("  v = rotate by 180 degrees")
    print("  l = rotate by 90 degrees to the left = counter clockwise")
    print("  * = continue (press any other key, like enter or space)")

    print("what should i do? ", end="", flush=True)
    response = read_char()
    print()

    if response == "e":
        gimp_process = subprocess.Popen(
            ["gimp", str(temp_path)]
        )

        print(
            "edit the image in gimp, then: file > overwrite"
        )
        input("hit enter when done editing")

        # Do not force-kill GIMP: the Bash version also merely waits for
        # the user to press Enter.

    elif response == "k":
        print(f"deleting {temp_path}")
        temp_path.unlink(missing_ok=True)
        stop_process(feh_process)

        return conversion_processes, last_title

    elif response == "r":
        this_extra_convert_options += [
            "-rotate",
            "90",
        ]

    elif response == "v":
        this_extra_convert_options += [
            "-rotate",
            "180",
        ]

    elif response == "l":
        this_extra_convert_options += [
            "-rotate",
            "270",
        ]

    else:
        print(f"continuing to process {temp_path}")

    # -----------------------------------------------------------------------
    # Default title
    # -----------------------------------------------------------------------

    default_title = temp_path.stem

    # Remove "scan." prefix.
    if default_title.startswith("scan."):
        default_title = default_title[len("scan."):]

    r'''
    if last_title:
        # Reuse yyyy-mm-dd.hh-mm from the previous title.
        match = re.match(
            r"^(\d{4}-\d{2}-\d{2}\.\d{2}-\d{2})\..*$",
            last_title,
        )

        if match:
            default_title = match.group(1)
    '''

    if last_title:
        # Reuse the datetime from the previous title.
        #
        # Bash equivalent:
        # sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{2}-[0-9]{2})\..*$/\1/'
        #
        # This intentionally handles both:
        #
        #   2026-08-13.16-00
        #   2026-08-13.16-00.some-suffix
        #
        match = re.match(
            r"^(\d{4}-\d{2}-\d{2}\.\d{2}-\d{2})(?:\..*)?$",
            last_title,
        )

        if match:
            default_title = match.group(1)

    # -----------------------------------------------------------------------
    # Ask for title, retrying on errors
    # -----------------------------------------------------------------------

    title_len_max = 240

    while True:
        title = read_with_default(
            "please enter the basename: ",
            default_title,
        )

        title = trim_and_normalize_title(title)

        if not title:
            title = default_title

        outputs = [
            Path(f"{title}.avif"),
            Path("large") / f"{title}.large.avif",
        ]

        existing = [
            output
            for output in outputs
            if output.exists()
        ]

        if existing:
            for output in existing:
                print(
                    f"error: output file exists: {output}"
                )

            default_title = title
            continue

        if len(title.encode("utf-8")) >= title_len_max:
            print(
                "error: title is too long. "
                f"{len(title.encode('utf-8'))} versus "
                f"{title_len_max}. "
                "please use a shorter title"
            )

            default_title = title
            continue

        break

    print(f"using basename: {title!r}")

    # Close image viewer before conversion.
    stop_process(feh_process)

    # -----------------------------------------------------------------------
    # Start conversion in the background
    # -----------------------------------------------------------------------

    if KEEP_TEMPFILE:
        print(f"keeping tempfile {temp_path}")

    conversion_process = multiprocessing.Process(
        target=convert_page,
        args=(
            temp_path,
            title,
            extra_convert_options,
            this_extra_convert_options,
            shared_convert_options,
            small_convert_options,
            large_convert_options,
        ),
    )

    conversion_process.start()
    conversion_processes.append(conversion_process)

    last_title = title

    return conversion_processes, last_title


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
