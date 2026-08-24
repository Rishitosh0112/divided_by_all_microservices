# Pause and Resume the Development Environment

Use this runbook when the development environment is not needed and you want to reduce running
charges without deleting application data or infrastructure.

## What pause does

```text
ECS services -> desired task count 0 -> ECS tasks stop
ECS EC2 Auto Scaling Group -> desired capacity 0 -> EC2 hosts terminate
RDS PostgreSQL + DocumentDB -> stop -> database instance-hour charges pause
```

The helper stores the current ECS desired counts and Auto Scaling Group values in the local,
Git-ignored file `infra/.pause-state.local.json`. It does not store credentials, passwords, or
application secrets.

The Application Load Balancer, ECR image storage, CloudWatch log storage, and database storage are
preserved and can still incur smaller charges. RDS and DocumentDB automatically restart after at
most seven days; do not rely on this workflow for a longer shutdown.

## Pause now

Start with a dry run. It prints the actions without modifying AWS:

```bash
cd /Users/rishitoshsingh/Desktop/Code/Web_Application/DevTinder_SSR_MICROSERVICES/divided_by_all_microservices
python3 scripts/pause_resume_environment.py pause
```

If the output is correct, perform the pause:

```bash
python3 scripts/pause_resume_environment.py pause --apply
```

The command first stops ECS tasks, waits for them to finish, and only then reduces EC2 capacity to
zero. It finally submits RDS and DocumentDB stop operations.

## Resume later

Start with a dry run:

```bash
python3 scripts/pause_resume_environment.py resume
```

To resume for real:

```bash
python3 scripts/pause_resume_environment.py resume --apply
```

The script starts RDS and DocumentDB first, waits until both are available, restores the saved EC2
capacity, and then restores each ECS service's desired task count. Database startup can take several
minutes. ECS tasks start only after enough EC2 capacity registers.

## Important current capacity note

The Frontend Shell deployment needs a fifth ECS host. The account has an open request to raise the
EC2 Standard On-Demand vCPU quota from 8 to 10. Until AWS approves it, the Frontend Shell task can
remain in `PROVISIONING`; pausing and resuming does not resolve that quota restriction.

## Terraform relationship

This helper performs runtime start/stop operations. Terraform still declares the normal desired
state as one task per service, so a later Terraform apply can resume services by reconciling that
configuration. Do not run unrelated Terraform applies while the environment is intentionally
paused. A Terraform-native pause switch can be added later after the current deployment is stable.
