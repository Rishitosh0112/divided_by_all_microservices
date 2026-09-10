# Group Service — Production Plan

This document is the implementation plan for operating Group Service safely in
production. It complements the application code and uses
[`../Production_Grade.md`](../Production_Grade.md) as the production-readiness
source of truth.

## Database

### Ownership and current state

Group Service exclusively owns group lifecycle, membership, and invitations.
It owns the PostgreSQL `groups`, `group_members`, and `group_invitations`
tables. User IDs are external references owned by User Service, so they are
stored as text and must not have cross-service database foreign keys.

| Area | Current state | Required production outcome |
| --- | --- | --- |
| Database | PostgreSQL; Amazon RDS is the AWS target | One Group-owned database/schema and no direct access by other services |
| Schema | Prisma schema defines groups, members, invitations, and their internal foreign keys | Add/confirm `NOT NULL`, `CHECK`, `UNIQUE`, timestamp, and query-driven index invariants through reviewed migrations |
| ORM/client | Prisma with `@prisma/adapter-pg` over a `pg.Pool` | One long-lived writer pool and, after replicas are provisioned, one long-lived reader pool per Node process |
| Migrations | Version-controlled Prisma migrations exist | A dedicated, serialized migration job; application tasks must not run migrations at startup |
| Current pool | `min: 2`, `max: 10`, 2-second acquisition timeout, 30-second idle timeout | Deliberate limits, error handling, metrics, query/transaction timeouts, connection lifetime, and graceful pool shutdown |

### Target topology: one writer and two read replicas

The requested topology is:

```text
                         +--> Read replica 1 (read-only)
Group Service ---> DB routing
                         +--> Read replica 2 (read-only)
                         `--> Writer / primary (all writes and consistency-critical reads)
```

The primary writer accepts all inserts, updates, deletes, transactions, and
migrations. Replicas are asynchronous copies and can lag behind the writer.
Therefore, routing is based on consistency requirements, not merely whether a
statement begins with `SELECT`.

| Operation | Initial database role | Reason |
| --- | --- | --- |
| Create group and creator membership | Writer | One transaction; must commit atomically |
| Create invitation | Writer | Mutates authoritative state |
| Accept/reject invitation and create membership | Writer | Requires a transaction and current invitation state |
| Update/deactivate group | Writer | Mutates authoritative state |
| Authorization checks, including `getGroup` membership verification | Writer | A stale replica could incorrectly deny or allow a just-changed membership |
| Immediate read after a successful write | Writer | Guarantees read-your-write behavior |
| User group list | Writer initially; replica only after stale-list behavior is explicitly accepted | A newly created or joined group may not appear immediately on a replica |
| Historical, non-authoritative reporting/list endpoints | Replica candidate | Only after a defined maximum acceptable staleness and fallback behavior |

Replica routing must include a health and replication-lag policy. When both
replicas are unavailable or lag exceeds the accepted threshold, eligible reads
must fall back to the writer or fail predictably according to the endpoint
contract. The application must prevent writes from being sent to a replica.

### Migration plan

Current state: `groups-service/Dockerfile` invokes `npx prisma migrate deploy`
before starting Node. This is acceptable only for a single, tightly controlled
instance; it is unsafe with multiple application tasks because each task can
try to acquire migration locks and execute DDL during startup.

Plan:

1. Remove migration execution from the application container command.
2. Build a dedicated migration image/job using the same immutable release
   artifact and writer-only database credentials.
3. Run exactly one migration job before deploying tasks that depend on the new
   schema; record its outcome and stop the release on failure.
4. Use expand-and-contract changes: add compatible schema, deploy compatible
   code, backfill in resumable batches, switch reads/writes, then remove old
   schema in a later release.
5. Prefer roll-forward recovery. Never automatically run destructive changes
   from a service replica.

Acceptance criteria:

- Multiple ECS tasks can start concurrently without running a migration.
- Only the migration job can use migration privileges.
- A failed migration is visible, halts the deployment, and has a documented
  recovery procedure.
- Application code remains compatible throughout a rolling deployment.

### Query inventory and index-validation plan

Current query paths in `src/services/group-service.ts`:

| Use case | Main access pattern | Current state / validation required |
| --- | --- | --- |
| Create group | Insert `groups`, then creator `group_members` in one transaction | Verify rollback and transaction timeout |
| Get group | Find group by primary key; find member by `(groupId, userId)` | Composite uniqueness supports member lookup; inspect plan |
| List user groups | Filter groups through membership, sort by `createdAt DESC`, paginate with offset | Requires representative `EXPLAIN (ANALYZE, BUFFERS)`; consider an index supporting user membership and pagination; replace offset pagination with cursor/keyset pagination if data size justifies it |
| Update/deactivate group | Find/update by group primary key | Verify authorization and write concurrency policy |
| Create invitation | Insert invitation scoped by group/user | Existing unique `(groupId, invitedUserId)`; decide re-invitation/history behavior explicitly |
| Resolve invitation | Find invitation by ID; validate state; update invitation; optionally insert membership in one transaction | Add concurrent acceptance test and verify a rejected invitation persists its final state |

Indexes will be added only after capturing real or representative execution
plans. Every proposed index must document the query it serves, measured benefit,
write/storage cost, and rollback plan.

### Connection pools and budget

Pools are per Node process. Pool limits are not global limits for the service.
The production maximum must include all normal tasks and temporary deployment
overlap:

```text
maximum database connections per role =
  maximum simultaneously running ECS tasks
  × Node processes per task
  × pools per process for that role
  × maximum pool size
```

With one writer pool and two reader pools, each Node process has three pools.
The total also requires capacity reserved for the migration job, database
operators, monitoring, maintenance, and failover headroom.

Initial sizing must not be guessed. Before setting final pool limits, record:

- normal desired task count;
- maximum task count during a rolling deployment (`deployment_maximum_percent`);
- processes per task (normally one Node process per container);
- writer and reader maximum pool sizes;
- RDS instance/cluster connection capacity and any proxy limits;
- migration, operator, monitoring, and recovery reserves;
- whether writer and read replicas are separate RDS instances/endpoints.

Example only — not an approved production configuration:

```text
5 normal tasks, up to 6 during a 120% rolling deployment
1 Node process/task
writer max pool = 5
each reader max pool = 3

Writer ceiling:   6 × 1 × 1 × 5 = 30
Reader ceiling:   6 × 1 × 2 × 3 = 36
Application total: 66 connections, before migration/admin/monitoring reserves
```

The initial writer and reader pool settings must include acquisition, idle,
connection-lifetime, query/statement, and transaction timeouts. Pool
acquisition failures, active/idle/waiting counts, timeout count, query latency,
slow queries, and database lock waits must be measurable and alertable.

### Required tests and failure exercises

- Pool reuse under load and acquisition timeout when the pool is exhausted.
- Connection leak simulation followed by healthy request recovery.
- Transaction rollback followed by connection reuse.
- Database restart and replica unavailability/lag routing behavior.
- Concurrent invitation acceptance and duplicate membership prevention.
- Rolling deployment capacity calculation and task termination behavior.
- Migration-job failure, retry, and roll-forward procedure.

### Remaining production requirements

The database plan is necessary but not sufficient for a fully production-ready
Group Service. Remaining P0/P1 work includes:

- startup configuration validation, readiness/liveness separation, and graceful
  shutdown;
- stable API contracts, request limits, correlation IDs, and safe error shapes;
- authentication, authorization, tenant/resource isolation, and threat model;
- structured redacted logging, metrics, traces, dashboards, alerts, and audit
  records where administrative actions require them;
- unit, integration, contract, end-to-end, load, failure, and security tests;
- immutable image delivery, CI checks, ECS deployment safety, rollback/runbooks,
  backup/restore validation, RPO, and RTO.

## Implementation order

1. Record the real RDS topology, capacity, endpoints, and deployment task
   limits; approve the connection budget.
2. Separate migration execution from application startup.
3. Define reader-routing and acceptable-staleness policy for every endpoint.
4. Provision and validate the writer/replica endpoints and least-privilege
   credentials.
5. Introduce explicit writer/reader pool configuration, lifecycle handling,
   timeouts, metrics, and failure tests.
6. Capture query plans and make evidence-based index/pagination changes.
7. Complete the remaining service-wide production readiness work.
