#!/usr/bin/env python3
"""Safely pause or resume the Divided By All development environment.

Default mode is a dry run. Add --apply only after reading the printed actions.
The script never reads, prints, or stores application secrets.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REGION = "ap-south-1"
CLUSTER = "divided-by-all-cluster"
ASG = "Infra-ECS-Cluster-divided-by-all-cluster-e9cd13f5-ECSAutoScalingGroup-dWvHVK2i5woQ"
RDS_INSTANCE = "divided-by-all-groups-postgres"
DOCDB_CLUSTER = "divided-by-all-user-documentdb"
SERVICES = [
    "divided-by-all-groups-service",
    "divided-by-all-user-service",
    "divided-by-all-api-gateway",
    "divided-by-all-client-mfe",
    "divided-by-all-frontend-shell",
]
STATE_FILE = Path(__file__).resolve().parents[1] / "infra" / ".pause-state.local.json"


def aws(*args: str, apply: bool, capture: bool = False) -> str:
    command = ["aws", *args, "--region", REGION, "--no-cli-pager"]
    print("$ " + " ".join(command))
    if not apply:
        return ""
    result = subprocess.run(command, check=True, text=True, capture_output=capture)
    return result.stdout


def aws_json(*args: str) -> object:
    command = ["aws", *args, "--region", REGION, "--no-cli-pager", "--output", "json"]
    result = subprocess.run(command, check=True, text=True, capture_output=True)
    return json.loads(result.stdout)


def read_current_state() -> dict:
    services = aws_json(
        "ecs", "describe-services", "--cluster", CLUSTER, "--services", *SERVICES
    )["services"]
    asg = aws_json(
        "autoscaling", "describe-auto-scaling-groups", "--auto-scaling-group-names", ASG
    )["AutoScalingGroups"][0]
    return {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "services": {service["serviceName"]: service["desiredCount"] for service in services},
        "autoscaling_group": {
            "min_size": asg["MinSize"],
            "desired_capacity": asg["DesiredCapacity"],
            "max_size": asg["MaxSize"],
        },
    }


def database_status() -> tuple[str, str]:
    rds = aws_json("rds", "describe-db-instances", "--db-instance-identifier", RDS_INSTANCE)
    docdb = aws_json("docdb", "describe-db-clusters", "--db-cluster-identifier", DOCDB_CLUSTER)
    return rds["DBInstances"][0]["DBInstanceStatus"], docdb["DBClusters"][0]["Status"]


def pause(apply: bool) -> None:
    state = read_current_state()
    print("\nRecorded current desired counts and ASG limits in:", STATE_FILE)
    if apply:
        STATE_FILE.write_text(json.dumps(state, indent=2) + "\n")

    print("\n1. Set all ECS services to zero tasks.")
    for service in SERVICES:
        aws("ecs", "update-service", "--cluster", CLUSTER, "--service", service, "--desired-count", "0", apply=apply)

    print("\n2. Wait for ECS to stop the tasks before terminating their EC2 hosts.")
    aws("ecs", "wait", "services-stable", "--cluster", CLUSTER, "--services", *SERVICES, apply=apply)

    print("\n3. Scale the ECS Auto Scaling Group to zero EC2 instances.")
    aws(
        "autoscaling", "update-auto-scaling-group", "--auto-scaling-group-name", ASG,
        "--min-size", "0", "--desired-capacity", "0", "--max-size", str(state["autoscaling_group"]["max_size"]),
        apply=apply,
    )

    rds_status, docdb_status = database_status()
    print("\n4. Stop databases that are currently running.")
    if rds_status == "available":
        aws("rds", "stop-db-instance", "--db-instance-identifier", RDS_INSTANCE, apply=apply)
    else:
        print(f"RDS is already {rds_status}; no stop command needed.")
    if docdb_status == "available":
        aws("docdb", "stop-db-cluster", "--db-cluster-identifier", DOCDB_CLUSTER, apply=apply)
    else:
        print(f"DocumentDB is already {docdb_status}; no stop command needed.")

    print("\nPause submitted. RDS and DocumentDB transition asynchronously; verify their console status before closing AWS.")


def wait_for_databases() -> None:
    print("\nWaiting for RDS and DocumentDB to become available (this can take several minutes).")
    while True:
        rds_status, docdb_status = database_status()
        print(f"RDS: {rds_status}; DocumentDB: {docdb_status}")
        if rds_status == "available" and docdb_status == "available":
            return
        time.sleep(30)


def resume(apply: bool, no_wait: bool) -> None:
    if not STATE_FILE.exists():
        raise SystemExit(f"No saved pause state at {STATE_FILE}. Pause with --apply first.")
    state = json.loads(STATE_FILE.read_text())
    rds_status, docdb_status = database_status()

    print("\n1. Start databases first so application tasks do not fail during startup.")
    if rds_status == "stopped":
        aws("rds", "start-db-instance", "--db-instance-identifier", RDS_INSTANCE, apply=apply)
    else:
        print(f"RDS is {rds_status}; no start command needed.")
    if docdb_status == "stopped":
        aws("docdb", "start-db-cluster", "--db-cluster-identifier", DOCDB_CLUSTER, apply=apply)
    else:
        print(f"DocumentDB is {docdb_status}; no start command needed.")

    if apply and not no_wait:
        wait_for_databases()

    asg = state["autoscaling_group"]
    print("\n2. Restore ECS Auto Scaling Group limits and desired capacity.")
    aws(
        "autoscaling", "update-auto-scaling-group", "--auto-scaling-group-name", ASG,
        "--min-size", str(asg["min_size"]), "--desired-capacity", str(asg["desired_capacity"]),
        "--max-size", str(asg["max_size"]), apply=apply,
    )

    print("\n3. Restore each ECS service's saved desired count.")
    for service, desired_count in state["services"].items():
        aws(
            "ecs", "update-service", "--cluster", CLUSTER, "--service", service,
            "--desired-count", str(desired_count), apply=apply,
        )
    print("\nResume submitted. ECS starts tasks once EC2 capacity and databases are available.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("pause", "resume"))
    parser.add_argument("--apply", action="store_true", help="Perform actions; omit for a dry run.")
    parser.add_argument("--no-wait", action="store_true", help="On resume, do not wait for databases before restoring ECS.")
    args = parser.parse_args()
    try:
        if args.action == "pause":
            pause(args.apply)
        else:
            resume(args.apply, args.no_wait)
    except subprocess.CalledProcessError as error:
        print(f"\nAWS command failed with exit code {error.returncode}. Nothing else will run.", file=sys.stderr)
        raise SystemExit(error.returncode)


if __name__ == "__main__":
    main()
