# Divided By All — AWS Production Architecture

This is the target AWS-native architecture. It covers current User and Groups services and
the planned Expense, Settlement, and Notification services. Start in one region (recommended:
`ap-south-1` for an India-first product) using at least two Availability Zones.

## Principles

- Every microservice is a bounded context with an independent deployment and data store.
- Client commands and reads use synchronous HTTP; cross-domain work uses events.
- Event delivery is at-least-once, so consumers are idempotent.
- A service writes data and an outbox event in one transaction before publishing.
- Only CloudFront/API Gateway are public. ECS tasks and databases stay private.
- Secrets come from Secrets Manager at runtime, never Git or container images.

## AWS service mapping

| Concern | AWS service |
|---|---|
| DNS, certificates, edge caching | Route 53, ACM, CloudFront |
| Web application | Next.js ECS/Fargate service behind public ALB; S3 for static MFE assets |
| Public API and identity | API Gateway HTTP API + Amazon Cognito User Pool |
| Container build/run | ECR + ECS Fargate |
| Internal HTTP routing | Internal ALBs and Cloud Map / ECS Service Connect |
| User-profile store | DocumentDB or MongoDB Atlas (select one before migration) |
| Groups, Expenses, Settlements | Dedicated RDS PostgreSQL database/cluster per service |
| Notification inbox/delivery state | DynamoDB |
| Event routing | EventBridge custom event bus |
| Durable consumption / failure isolation | SQS queues and DLQs |
| Email | SES |
| Secrets/encryption | Secrets Manager, IAM roles, KMS |
| Logs, metrics, alarms, tracing | CloudWatch and X-Ray/OpenTelemetry |

## Full topology

```text
Users
  |
Route 53 --> CloudFront + AWS WAF
               |                          |
               | /                        +--> S3: static microfrontend assets
               v
          Next.js SSR host (ECS/Fargate; public ALB)
               |
               +----> API Gateway HTTP API
                         | Cognito JWT authorizer + VPC Link
                         v
                     private internal ALBs
  +----------------------+----------+----------+-------------------------+
  |                      |          |          |                         |
User service          Groups      Expense    Settlement             Notification
ECS/Fargate           ECS         ECS        ECS                    ECS workers
  |                      |          |          |                         |
DocumentDB/Atlas       RDS        RDS        RDS                    DynamoDB + SES
  |                      |          |          |
  +----------------------+----------+----------+
                         |
                 transactional outbox publishers
                         v
             EventBridge custom domain-event bus
                     |          |          |
                  SQS queue  SQS queue  SQS queue
                  per consumer, each with retries and DLQ
```

## Current services on AWS

### User service

- **Current responsibility:** signup/login/logout, JWT validation, profiles.
- **Current implementation:** Express, Mongoose, MongoDB-compatible store.
- **Route ownership:** `/auth/*` and `/profiles/*`.
- **Target hosting:** ECS Fargate, private ALB, DocumentDB/Atlas.
- **Target change:** Cognito issues production tokens. User service retains application profiles,
  keyed by the Cognito `sub`, but does not sign its own production JWTs. API Gateway validates
  Cognito-issued tokens before requests reach protected services.

### Groups service

- **Current responsibility:** groups, members, invitations, creator authorization.
- **Current implementation:** Express, Prisma, PostgreSQL.
- **Route ownership:** `/groups/*`.
- **Target hosting:** ECS Fargate, internal ALB, dedicated RDS PostgreSQL.
- **Event role:** publishes membership events; Expense and Notification consume them.

## New services on AWS

### Expense service

- **Routes:** `/expenses/*`.
- **Domain:** expense lifecycle, payer, participant snapshots, equal/exact/percentage/share
  strategies, obligations, and history.
- **Storage:** dedicated RDS PostgreSQL plus outbox table.
- **Consumes:** Group membership events.
- **Publishes:** `expense.created.v1`, `expense.updated.v1`, `expense.deleted.v1`.

### Settlement service

- **Routes:** `/balances/*` and `/settlements/*`.
- **Domain:** materialized group balances, debt simplification/proposals, confirmed payments,
  and a settlement ledger.
- **Storage:** dedicated RDS PostgreSQL projection/ledger plus outbox table.
- **Consumes:** Expense events and relevant member-removal events.
- **Publishes:** `settlement.proposed.v1`, `settlement.recorded.v1`.

### Notification service

- **Routes:** `/notifications/*` for an authenticated notification inbox.
- **Domain:** preferences, inbox items, delivery attempts, read/unread state, templates.
- **Storage:** DynamoDB, designed for efficient per-user inbox reads.
- **Consumes:** Group, Expense, and Settlement events through dedicated SQS queues.
- **Delivery:** SES for email; push/SMS are future infrastructure adapters.

## Event reliability model

```text
Database transaction
  ├─ domain records change
  └─ outbox_events record inserted
           |
           v
Outbox publisher --> EventBridge --> rule --> consumer SQS --> service
                                                   |
                                               retry / DLQ
```

- EventBridge routes by `source` and event type; it contains no domain business rules.
- Each consumer persists processed event IDs together with its state mutation.
- CloudWatch alarms monitor DLQ depth, oldest-message age, consumer failures, and outbox lag.
- Event contracts are versioned, such as `expense.created.v1`; incompatible changes create a new
  version.
- EventBridge routes events; SQS gives every consumer durable, isolated work and back-pressure.

## Network and access

```text
VPC across two+ AZs
├─ Public subnets: NAT Gateways and public ALB for SSR host
└─ Private subnets: ECS tasks, internal ALBs, RDS and DocumentDB
```

- API Gateway reaches private ALBs through VPC Link.
- Database security groups accept traffic only from the owning ECS task security group.
- ECS task IAM roles have least-privilege access to a specific secret, bus publish permission,
  and only their own SQS queues.
- WAF protects CloudFront; API Gateway enforces JWT authorization, throttling, and validation.
- Use KMS-backed encryption for RDS, DocumentDB, DynamoDB, SQS, and secrets.

## Delivery, scale, and observability

- Each service has an ECR repository, ECS service, health endpoint, CloudWatch dashboard, and
  autoscaling policy.
- Start public-facing services with two tasks across AZs. Consumer services also scale using SQS
  queue depth and message age.
- CI/CD: test, build/tag/scan image, push to ECR, deploy staging, then production.
- Carry a `correlationId` from API request through logs, outbox, EventBridge, SQS, and consumers.

## Migration from today

1. Remove committed credentials and hardcoded connection strings; use `.env.example` locally and
   Secrets Manager in AWS.
2. Refactor User and Groups to clean layers and introduce shared event-envelope/outbox interfaces.
3. Introduce Cognito and API Gateway, retaining a controlled local JWT transition only as needed.
4. Deploy User and Groups to ECS with private networking and their own databases.
5. Build Expense with RDS, outbox, events, and split-strategy domain objects.
6. Build Settlement as an independent Expense-event consumer and balance projection.
7. Build Notification with DynamoDB, SQS workers, SES, DLQs, and alarms.
8. Add multi-region disaster recovery only after the single-region system is stable and measured.

## Why this replaces the earlier Kafka/MSK direction

EventBridge plus SQS is the default AWS-native choice here: it handles event fan-out, isolates
each consumer with a queue, and avoids operating Kafka infrastructure. MSK can remain a later
option only if throughput, long retention/replay, or stream-processing requirements justify it.
