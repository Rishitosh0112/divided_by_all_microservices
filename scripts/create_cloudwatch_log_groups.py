#!/usr/bin/env python3
"""Create the Divided By All CloudWatch log groups.

The script uses the AWS CLI credentials already configured on this computer.
Run without --apply to review the planned AWS changes. Run with --apply to
create any missing log groups and set their retention period.
"""

from __future__ import annotations

import argparse
import subprocess
import sys


REGION = "ap-south-1"
RETENTION_DAYS = 7
LOG_GROUPS = (
    "/ecs/divided-by-all/frontend-shell",
    "/ecs/divided-by-all/client-mfe",
    "/ecs/divided-by-all/api-gateway",
    "/ecs/divided-by-all/user-service",
    "/ecs/divided-by-all/groups-service",
)


def aws_command(*arguments: str) -> list[str]:
    return ["aws", "logs", *arguments, "--region", REGION]


def run_command(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=False, capture_output=True, text=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Create the log groups and set the retention period.",
    )
    arguments = parser.parse_args()

    action = "apply" if arguments.apply else "dry run"
    print(f"CloudWatch log-group {action}: {REGION}")

    for log_group in LOG_GROUPS:
        if not arguments.apply:
            print(f"Would create {log_group} and set retention to {RETENTION_DAYS} days.")
            continue

        create_result = run_command(
            aws_command("create-log-group", "--log-group-name", log_group)
        )
        if create_result.returncode == 0:
            print(f"Created {log_group}.")
        elif "ResourceAlreadyExistsException" in create_result.stderr:
            print(f"{log_group} already exists; keeping it.")
        else:
            print(create_result.stderr.strip(), file=sys.stderr)
            return create_result.returncode

        retention_result = run_command(
            aws_command(
                "put-retention-policy",
                "--log-group-name",
                log_group,
                "--retention-in-days",
                str(RETENTION_DAYS),
            )
        )
        if retention_result.returncode != 0:
            print(retention_result.stderr.strip(), file=sys.stderr)
            return retention_result.returncode

        print(f"Set {log_group} retention to {RETENTION_DAYS} days.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
