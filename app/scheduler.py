#!/usr/bin/env python3
"""Run GPTWOL's persisted cron-style schedules without a cron daemon."""

import os
import subprocess
from datetime import datetime

SCHEDULE_FILE = os.environ.get("GPTWOL_SCHEDULE_FILE", "/app/db/gptwol.cron")
WAKEONLAN = os.environ.get("GPTWOL_WAKEONLAN", "/usr/local/bin/wakeonlan")


def _field_matches(field, value, minimum, maximum):
    for item in field.split(","):
        if item == "*":
            return True

        base, _, step_text = item.partition("/")
        step = int(step_text) if step_text else 1

        if base == "*":
            if (value - minimum) % step == 0:
                return True
            continue

        if "-" in base:
            start_text, end_text = base.split("-", 1)
            start, end = int(start_text), int(end_text)
            if start <= value <= end and (value - start) % step == 0:
                return True
            continue

        if value == int(base):
            return True

    return False


def cron_matches(expression, now):
    parts = expression.split()
    if len(parts) != 5:
        return False

    minute, hour, dom, month, dow = parts

    if not _field_matches(minute, now.minute, 0, 59):
        return False
    if not _field_matches(hour, now.hour, 0, 23):
        return False
    if not _field_matches(month, now.month, 1, 12):
        return False

    dom_matches = _field_matches(dom, now.day, 1, 31)
    cron_dow = (now.weekday() + 1) % 7
    dow_matches = _field_matches(dow, cron_dow, 0, 7)

    # Match traditional cron's OR behaviour when both DOM and DOW
    # are explicitly restricted.
    if dom != "*" and dow != "*":
        return dom_matches or dow_matches
    if dom != "*":
        return dom_matches
    if dow != "*":
        return dow_matches
    return True


def load_entries():
    if not os.path.exists(SCHEDULE_FILE):
        return []

    entries = []
    with open(SCHEDULE_FILE, encoding="utf-8") as schedule_file:
        for raw_line in schedule_file:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            fields = line.split()
            if len(fields) < 8:
                continue

            expression = " ".join(fields[:5])
            command = fields[6:]

            if len(command) != 2:
                continue
            if command[0] != WAKEONLAN:
                continue

            entries.append((expression, command[1]))

    return entries


def run():
    now = datetime.now().replace(second=0, microsecond=0)

    for expression, mac_address in load_entries():
        if not cron_matches(expression, now):
            continue

        subprocess.run(
            [WAKEONLAN, mac_address],
            check=True,
            timeout=10,
        )
        print(
            f"Scheduled WOL sent to {mac_address} ({expression})",
            flush=True,
        )


if __name__ == "__main__":
    run()
