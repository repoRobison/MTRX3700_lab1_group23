#!/usr/bin/env python3
"""submit_to_ed.py, push this repository to Ed for marking.

ONE group member runs this, at the end. Ed's git access is tied to an individual
student account, so it will only work for whoever runs it. That is fine, only
one submission is needed.

    python scripts/submit_to_ed.py

Re-running it replaces the previous submission -- resubmitting is fine, right up
to the deadline. Ed marks whatever the latest push put at the HEAD of master.

The challenge number lives in the file ED_CHALLENGE_ID in the project root. If a
tutor gives you a different one, edit that file (it is one line, just the
number).
"""

import re
import sys
from pathlib import Path

import common

ID_FILE = Path("ED_CHALLENGE_ID")

def challenge_id():
    """The Ed challenge number from ED_CHALLENGE_ID."""
    if not ID_FILE.exists():
        common.abort(f"{ID_FILE} is missing. It should contain the Ed challenge number on\n"
                   "   a single line. Find it in the Ed challenge's URL, or ask a tutor.")

    # Take the first non-blank line and strip whitespace, so a stray trailing
    # space or a Windows line ending does not end up inside the URL:
    lines = [line.strip() for line in ID_FILE.read_text().splitlines() if line.strip()]
    if not lines:
        common.abort(f"{ID_FILE} is empty. It should contain the Ed challenge number.")
    return lines[0]


def git(*args, capture=False):
    return common.run(["git", *args], capture=capture)


def report_remote_status(head):
    """Say what is on Ed right now, so it is clear what this push will do.
    Returns False if Ed already has exactly this commit (nothing to submit).
    """
    remote = git("ls-remote", "ed", "refs/heads/master", capture=True)
    if remote.returncode != 0:
        common.warn("Could not contact Ed to check the current submission:")
        print(remote.stdout.rstrip())
        common.info("Attempting the push anyway.")
        return True

    # Pick the "<40-hex-digit hash>\trefs/heads/master" line out of the output,
    # which can also contain unrelated ssh warnings:
    match = re.search(r"^([0-9a-f]{40})\s+refs/heads/master", remote.stdout, re.M)
    submitted = match.group(1) if match else None
    if submitted is None:
        common.info("This will be the group's first submission to this challenge.")
    elif submitted == head:
        common.info(f"Ed already has exactly this commit ({head[:7]}). Nothing new to submit.")
        return False
    else:
        common.info(f"Replacing the current submission {submitted[:7]} with {head[:7]}.")
    return True


def main():
    common.chdir_to_project_root()
    common.require_tool("git", "Install git: https://git-scm.com/downloads")

    url = f"git.edstem.org:challenge/{challenge_id()}/code-submission"

    # Add the Ed remote the first time. If it already exists but points
    # somewhere else, update it, so that ED_CHALLENGE_ID is always what decides
    # where this pushes.
    existing = git("remote", "get-url", "ed", capture=True)
    if existing.returncode != 0:
        git("remote", "add", "ed", url)
        common.info(f"Added Ed remote: {url}")
    elif existing.stdout.strip() != url:
        common.warn(f"Ed remote was {existing.stdout.strip()}")
        git("remote", "set-url", "ed", url)
        common.info(f"Updated Ed remote: {url}")
    else:
        common.info(f"Ed remote: {url}")

    head = git("rev-parse", "HEAD", capture=True).stdout.strip()

    if not report_remote_status(head):
        return 0

    # Ed marks what you PUSH: uncommitted changes stay behind on this machine.
    status = git("status", "--porcelain", capture=True)
    if status.stdout.strip():
        common.warn("You have uncommitted changes. They will NOT be part of the submission:")
        git("status", "--short")
        print("   (If they belong in the submission: commit them and run this again.)")

    # The submission checklist requires the final bitstream in the upload:
    tracked = git("ls-tree", "-r", "--name-only", "HEAD", capture=True).stdout
    if not any(line.endswith(".sof") for line in tracked.splitlines()):
        common.warn("This commit contains no .sof. The submission checklist requires your\n"
                    "   final bitstream. To include it:")
        print("      python scripts/compile_fpga.py")
        print("      git add -f output_files/demo.sof")
        print('      git commit -m "final bitstream for submission"')
        print("   then run this script again.")

    common.info(f"Pushing {head[:7]} to Ed master")

    # Ed marks the HEAD of the master branch. HEAD:master pushes whatever you
    # have checked out to Ed's master, so this works whatever your local branch
    # happens to be called.
    result = git("push", "--force", "ed", "HEAD:master")
    if result.returncode != 0:
        return result.returncode

    print()
    common.info("Submitted. Check the challenge page on Ed to confirm.")
    return 0


if __name__ == "__main__":
    sys.exit(main())