# Divided By All — Production-Readiness Teaching and Implementation Brief

## 1. Purpose

This document instructs Codex to act as an application architect, senior Node.js production engineer, teacher, reviewer, tester, and interviewer while evolving **Divided By All**, a Splitwise-like application, into a production-style system.

The learner already understands JavaScript/TypeScript and application development but has not operated Node.js in production. The objective is not to generate a large amount of code quickly. The objective is to understand, implement, test, observe, and explain the production practices that recur in roughly 80% of serious backend applications.

This is a curriculum and execution contract. Codex must work through it incrementally and must not claim that the system is production-ready merely because the happy path works.

## 2. Current system context

Use the repository as the source of truth. Inspect it before proposing changes. Do not overwrite working code or invent components that already exist.

Confirmed domain and architecture:

- Node.js and TypeScript
- REST APIs
- PostgreSQL
- Kafka locally; Amazon MSK is the likely production equivalent
- Docker for local dependencies and service packaging
- AWS ECS Fargate for long-running services
- Amazon RDS for PostgreSQL
- **User Service** owns users, identity-related profile data, and user lifecycle
- **Group Service** owns groups, membership, invitations, and group lifecycle
- **Expense & Settlement Service** owns expenses, splits, settlements, and the financial transaction boundary
- **Notification Service** is implemented with AWS Lambda; it consumes relevant Kafka/MSK events through an event-source integration and sends notifications through the selected email/SMS/push provider
- **Activity Service** consumes domain events and builds the user/group activity history
- These are five independently deployable services; do not describe them as three services
- Expense and Settlement deliberately belong to the same service and transactional boundary
- One payer per expense; equal and exact-amount splits are in scope
- Balances are derived and remain owned by the Expense & Settlement domain unless a separate read model is explicitly justified later
- Notification processing is asynchronous and eventually consistent
- Activity processing is asynchronous and eventually consistent
- Database-per-service ownership must be respected
- An outbox table may publish domain events to Kafka
- Strong consistency is required for accepted financial writes
- Eventual consistency is acceptable for notifications, activity feeds, and explicitly identified projections

Do not split services merely to demonstrate microservices. Service boundaries must follow business ownership, transactional boundaries, independent scaling, failure isolation, or team ownership.

## 2.1 Application-wide production mandate

Treat **every part of this application as production software**. Production style is not limited to database code or Kafka. Every new or existing capability must be assessed across all applicable dimensions:

- Correct domain behaviour and invariants
- Concurrency and transaction safety
- Input validation and stable contracts
- Authentication, authorization, and tenant/resource isolation
- Secrets, encryption, and least privilege
- Timeouts, bounded retries, idempotency, and backpressure
- Failure behaviour and recovery
- Structured logs, metrics, traces, dashboards, and actionable alerts
- Unit, integration, contract, end-to-end, load, and failure testing as appropriate
- Backward-compatible migrations and rolling deployments
- Resource limits, connection budgets, and cost
- CI/CD, rollback or roll-forward, backups, restore, and runbooks
- Behaviour with multiple replicas/tasks and partial dependency failure

Codex must not implement a happy-path feature and postpone all operational work indefinitely. Each feature is complete only when its relevant production concerns are implemented and verified. At the same time, Codex must avoid unjustified complexity: production-grade means reliable and operable for stated requirements, not automatically adding every available technology.

The **first implementation track is database production engineering**. This determines the order of work only; it does not reduce the final production-readiness scope of the application.

## 3. Teaching and collaboration contract

For every production concern, Codex must follow this sequence:

1. Inspect and explain the current implementation.
2. Describe the concrete production failure or limitation.
3. Ask the learner to propose a solution or predict the behaviour.
4. Present two or three realistic options and their trade-offs.
5. Recommend the simplest option justified by current requirements.
6. Create a small implementation plan with acceptance criteria.
7. Let the learner implement the central idea when practical.
8. Review the learner's code and explain corrections.
9. Add or improve automated tests.
10. Run the tests and relevant static checks.
11. Simulate at least one failure scenario.
12. Add the logs, metrics, traces, dashboards, or alarms needed to detect it.
13. Explain local behaviour and AWS production behaviour.
14. Record the architectural decision if it is material.
15. Ask interview questions and require the learner to explain the final design.

Do not dump the entire implementation in one response. Work on one bounded concern at a time. Never hide uncertainty behind the phrase “best practice.” Explain the requirement, scale, risk, cost, and trade-off that make a practice appropriate.

When writing code:

- Prefer small, reviewable changes.
- Preserve user changes and repository conventions.
- Explain important Node.js runtime behaviour.
- Show relevant control flow, failure flow, and ownership boundaries.
- Do not introduce a library until its responsibility is clear.
- Pin and review dependencies using the package manager already selected.
- Never place real secrets or credentials in source control.
- Run existing tests before and after material changes.

## 4. Priority classification

Every item must be labelled during implementation:

- **P0 — Universal:** expected in almost every production backend.
- **P1 — Common distributed-system requirement:** expected when a service uses databases, Kafka, multiple replicas, or remote dependencies.
- **P2 — Conditional:** valuable only when traffic, compliance, availability, organization size, or operational evidence justifies it.

Complete P0 before adding most P2 mechanisms.

## 5. Definition of production-ready for this project

For the bounded scope exercised by the project, production-ready means:

- Correct under expected concurrent requests
- Predictable when dependencies are slow or unavailable
- Safe under duplicate requests and duplicate event delivery
- Secure against common API and dependency attacks
- Observable enough to detect, diagnose, and alert on failures
- Deployable repeatedly without manual database or configuration repair
- Backward compatible during rolling deployments
- Recoverable from instance, deployment, Kafka-consumer, and database failures
- Tested at unit, integration, contract, end-to-end, load, and failure levels appropriate to the risk
- Documented with ownership, runbooks, dashboards, alerts, and rollback procedures
- Operable by a person who did not write the original code

It does not mean infinite scale, zero downtime under every disaster, or implementing every distributed-systems pattern.

---

# Part A — Architecture and domain correctness

## 6. Requirements and service-level objectives — P0

Codex must help define measurable expectations before tuning the system:

- Core user journeys
- Expected daily and peak traffic
- Read/write ratio
- Maximum request and event sizes
- Availability target for core writes and balance reads
- Latency objectives using percentiles, especially p50, p95, and p99
- Data durability and acceptable data-loss window
- Recovery Time Objective (RTO)
- Recovery Point Objective (RPO)
- Consistency requirements by operation
- Retention requirements
- Expected growth assumptions
- Cost constraints

Create an initial SLO document and identify which numbers are assumptions. Explain SLIs, SLOs, SLAs, error budgets, and why averages hide tail latency.

Acceptance criteria:

- Every important API is associated with a latency and success-rate SLI.
- Financial write correctness is not traded away merely to meet latency.
- Alerts are ultimately derived from user impact or exhaustion risk.

## 7. Domain boundaries and invariants — P0

Identify and enforce invariants such as:

- Expense amount must be positive.
- Currency must be supported and consistent within the relevant group or operation.
- Money must never use JavaScript floating-point arithmetic.
- Split amounts must sum exactly to the expense amount.
- Payer and participants must be valid group members at the required point in time.
- A settlement cannot pay oneself.
- Settlement amount must be positive.
- Authorization must be checked from trusted server-side state.
- Updates must preserve accounting history and auditability.
- Concurrent modifications must not silently lose data.

Use integer minor units or an appropriate fixed-precision representation. Explain rounding rules explicitly. Define whether historical records are immutable, versioned, corrected with compensating entries, or updated in place.

## 8. Architecture decisions — P0

Maintain lightweight Architecture Decision Records for decisions such as:

- Expense and Settlement transactional boundary
- PostgreSQL as source of truth
- Kafka event ownership and delivery semantics
- Outbox implementation
- Balance calculation versus projection storage
- Read-replica routing policy
- Authentication and authorization model
- Deployment model

Each ADR must contain context, decision, alternatives, consequences, and reconsideration triggers.

## 9. API contracts and compatibility — P0

Implement and teach:

- Resource-oriented routes and correct HTTP methods
- Request and response schemas
- Input validation at the system boundary
- Stable error shape with machine-readable error codes
- Appropriate status codes
- Pagination, filtering, sorting, and limits
- Maximum body size
- Request identifiers
- API versioning policy
- Backward-compatible schema evolution
- Deprecation policy
- OpenAPI documentation generated from or verified against implementation

Never leak stack traces, SQL, secrets, or internal topology to clients.

## 10. Idempotent HTTP operations — P1

For retried financial writes, design idempotency using a client-supplied idempotency key or stable business command identifier.

Teach and test:

- Scope of an idempotency key
- Persistence and expiry
- Same key with same payload
- Same key with different payload
- Concurrent requests using the same key
- Response replay
- Atomicity between idempotency record and business write
- Behaviour after partial failure or timeout

Do not treat HTTP method semantics alone as sufficient for business idempotency.

---

# Part B — Node.js production engineering

## 11. Runtime and process model — P0

Teach how the deployed Node.js process works:

- Single JavaScript thread and event loop
- libuv thread pool
- Microtask and timer behaviour relevant to starvation
- Non-blocking I/O versus CPU-bound work
- Memory allocation and garbage collection at a useful operational level
- One process per container as the default deployment model
- Horizontal scaling with multiple ECS tasks
- Why in-memory state cannot be authoritative across replicas

Identify and measure event-loop blocking. Move truly CPU-heavy work to worker threads, a separate worker service, or a more appropriate runtime only when profiling justifies it.

## 12. Application lifecycle — P0

Implement:

- Deterministic startup sequence
- Configuration validation before listening
- Database and Kafka initialization policy
- Startup timeout
- Liveness and readiness separation
- SIGTERM and SIGINT handling
- Stop accepting new traffic during shutdown
- Drain in-flight HTTP requests
- Stop or pause Kafka consumption safely
- Finish or abandon work according to delivery semantics
- Close producers, consumers, pools, and telemetry exporters
- Enforced shutdown deadline
- Non-zero exit for fatal startup/runtime failure

Test rolling-deployment and forced-termination behaviour.

## 13. Error handling — P0

Define a typed error taxonomy:

- Validation/client errors
- Authentication/authorization errors
- Not-found and conflict errors
- Transient dependency errors
- Rate-limit errors
- Internal programming errors

Implement centralized translation from domain/application errors to HTTP responses. Define policy for `uncaughtException` and `unhandledRejection`: log safely, initiate controlled shutdown when process integrity is uncertain, and rely on orchestration to restart.

## 14. Configuration and secrets — P0

Implement:

- Environment-specific configuration without environment-specific code branches scattered throughout the application
- Startup schema validation
- Safe defaults only where genuinely safe
- Secrets outside source control
- AWS Secrets Manager or SSM Parameter Store in production
- Credential rotation strategy
- No secret values in logs, traces, errors, images, or CI output
- Separate configuration for writer DB, reader DB, Kafka, telemetry, and timeouts

Teach configuration precedence and fail-fast behaviour.

## 15. Dependency management and supply-chain hygiene — P0

Require:

- Committed lockfile
- Reproducible installs
- Supported Node.js LTS version
- Dependency vulnerability scanning
- Removal of unused packages
- Review of high-risk/transitive packages
- Automated dependency updates with tests
- Production install excluding development dependencies
- License considerations when relevant

Do not automatically upgrade major versions without reviewing migration risks.

## 16. Timeouts, cancellation, retries, and backpressure — P0/P1

Every network or database operation must have a deliberate timeout. Teach:

- Connection timeout versus operation/request timeout
- End-to-end deadline propagation
- AbortController/cancellation where supported
- Retry only for transient and safe/idempotent operations
- Exponential backoff with jitter
- Maximum attempts and retry budget
- Avoiding layered retry multiplication
- Circuit breaking only when justified
- Bulkheads/concurrency limits
- Queue bounds and load shedding
- Returning overload responses instead of exhausting the process

Test slow dependencies, hanging connections, retry storms, and recovery.

## 17. Memory, resources, and event-loop health — P1

Implement and observe:

- Container CPU and memory limits
- Node heap sizing only when evidence justifies it
- Heap/RSS monitoring
- Event-loop delay
- Open handles and leaked timers
- Stream-based handling for large payloads
- Bounded caches and collections
- File descriptor and socket usage
- Protection against unbounded promises and concurrency

Create a memory-leak investigation exercise using heap snapshots or allocation profiling without exposing sensitive production data.

---

# Part C — PostgreSQL and data correctness

## 18. Schema design and ownership — P0

Require:

- Clear data ownership per service
- Primary keys appropriate for distributed creation and indexing
- Foreign keys inside the owning database where appropriate
- `NOT NULL`, `CHECK`, and `UNIQUE` constraints for invariants
- Correct timestamp and timezone handling
- Explicit money representation
- Indexes derived from real query patterns
- No direct cross-service table access
- Data retention and deletion policy

Explain why database constraints remain necessary even when application validation exists.

## 19. Connection pooling — P0

Connection pooling is mandatory. Implement and teach:

- One long-lived pool per process per database role, not one connection/pool per request
- Writer pool and, when introduced, reader pool
- Minimum/maximum pool size
- Connection acquisition timeout
- Idle timeout and lifetime/recycling policy
- Statement/query timeout
- Correct connection release in `finally`
- Transaction queries using the same checked-out connection
- Pool error handling
- Pool exhaustion behaviour
- Database connection budget across all services, tasks, deploy overlap, workers, migrations, and administrative access

Calculate a safe initial pool size:

`total possible DB connections = tasks × processes per task × pools per process × max pool size`

Reserve capacity for failover, rolling deployments, migrations, and operators. Explain why increasing pool size can reduce database performance.

Evaluate PgBouncer only after understanding application pools. If used, teach session versus transaction pooling, prepared-statement implications, transaction state, and observability.

Mandatory tests:

- Pool reuse under load
- Pool acquisition timeout
- Connection leak simulation
- Database restart
- Rolling deployment temporarily doubling task count
- Transaction rollback followed by connection reuse

## 20. Transactions and isolation — P0

For every write use case, explicitly define the transaction boundary. Teach:

- ACID in terms of this application
- PostgreSQL default isolation
- Lost updates, non-repeatable reads, phantoms, and write skew
- Row-level locking
- Optimistic concurrency/version columns
- `SELECT ... FOR UPDATE` when appropriate
- Deadlock causes and retry policy
- Short transactions and why remote calls must not occur inside them
- Correct rollback and connection release

Create concurrent integration tests for duplicate or conflicting expense and settlement changes.

## 21. Query performance and indexing — P0

Implement a repeatable process:

- Capture representative queries
- Use `EXPLAIN (ANALYZE, BUFFERS)` in a safe environment
- Understand sequential scans, index scans, joins, sorts, and row estimates
- Add single, composite, partial, covering, or expression indexes only for demonstrated access patterns
- Understand column order and selectivity
- Avoid N+1 queries
- Set pagination and result-size limits
- Prefer keyset/cursor pagination for large or changing datasets
- Monitor slow queries and lock waits
- Consider statistics, vacuum, and table/index bloat operationally

Do not add indexes to every column; explain write amplification and storage cost.

## 22. Migrations and backward-compatible deployment — P0

Use version-controlled migrations. Teach and implement expand-and-contract:

1. Add backward-compatible schema.
2. Deploy code capable of old and new states.
3. Backfill in bounded, resumable batches.
4. Switch reads/writes safely.
5. Remove old schema in a later deployment.

Cover:

- Migration ownership and serialization
- Lock risks of DDL
- Online index creation where appropriate
- Transactional versus non-transactional migrations
- Backfill throttling and progress
- Roll-forward preference
- Compatibility during rolling deployment
- Migration recovery and verification

Never run destructive schema changes automatically with every application replica.

## 23. Primary, standby, and read routing — P1/P2

Read replicas are conditional, not automatically required. Introduce them to demonstrate production considerations or when read load justifies them.

Teach:

- Primary handles writes
- Standby/replica replication mechanics at a useful level
- Synchronous versus asynchronous replication
- Replication lag and stale reads
- Read-after-write anomalies
- Transactions must stay on one appropriate connection/role
- Reads that enforce authorization, uniqueness, workflow correctness, or immediate confirmation may need the primary
- Analytics and tolerant list reads may use replicas
- Reader failover/fallback policy
- Preventing accidental writes to a reader
- Lag monitoring and routing away from unhealthy/stale replicas

Implement separate writer and reader pools only with an explicit routing policy. Never route all `SELECT` statements blindly to replicas.

## 24. Backup, restore, and disaster recovery — P0 operationally

Backups do not count until restore is tested. Define:

- Automated backups
- Point-in-time recovery
- Encryption
- Retention
- Cross-account or cross-region considerations when required
- RPO and RTO mapping
- Restore test schedule
- Data validation after restore
- Application and DNS/endpoint recovery procedure
- Runbook ownership

Perform or document a realistic restore drill for the selected environment.

## 25. Caching — P2

Do not add Redis merely because production systems use caches. Add caching only for a measured latency/load problem.

When justified, cover:

- Cache-aside flow
- Key ownership and versioning
- TTL and jitter
- Invalidation
- Stampede protection
- Negative caching
- Bounded local caches
- Stale data tolerance
- Security/tenant isolation
- Behaviour when cache is unavailable
- Metrics for hit rate, latency, memory, and evictions

Never cache authoritative balances without an explicit consistency design.

---

# Part D — Kafka and event-driven reliability

## 26. Event design and ownership — P1

For each event define:

- Owning producer
- Business meaning in past tense
- Event ID
- Event type and schema version
- Aggregate/entity ID
- Partition key
- Occurred-at timestamp and producer metadata
- Trace/correlation ID
- Payload schema
- Classification of sensitive data
- Retention requirement
- Consumer expectations

Events are contracts, not internal ORM objects. Avoid leaking entire database rows. Keep payloads reasonably small.

## 27. Topics, partitions, keys, and consumer groups — P1

Teach and decide:

- Topic boundaries
- Partition count and future scaling implications
- Key choice based on ordering requirement
- Ordering is only guaranteed within a partition
- Consumer-group concurrency is limited by partitions
- Rebalancing behaviour
- Retention, compaction, and replay requirements
- Environment isolation
- Topic configuration ownership

For expense, settlement, notification, and activity events, preserve ordering only where the owning use case requires it. Do not promise global ordering.

## 28. Database–Kafka atomicity and transactional outbox — P1

Never perform a naive database commit followed by Kafka publish for a business event that must not be lost.

Implement the transactional outbox:

1. Write business data and outbox row in the same PostgreSQL transaction.
2. Commit atomically.
3. Publish pending outbox records asynchronously.
4. Mark or otherwise track publication safely.
5. Retain/clean records according to an explicit policy.

Teach:

- Dual-write failure
- Polling publisher versus CDC/Debezium
- `FOR UPDATE SKIP LOCKED` or claim/lease strategy for competing publishers
- Publisher crash before publish
- Publisher crash after publish but before marking complete
- Why the result is generally at-least-once, not magically exactly-once
- Backlog monitoring
- Poison outbox records
- Replay and operational repair

Start with the simplest reliable polling publisher. Introduce Debezium/Kafka Connect only if its operational cost is justified or as a documented production alternative.

## 29. Idempotent consumers — P1

Every state-changing consumer must tolerate duplicates. Implement atomic consumption using a processed-event/inbox record or a naturally idempotent state transition.

Teach and test:

- Duplicate delivery
- Crash before database commit
- Crash after database commit but before offset commit
- Unique constraint on processed event ID
- Atomic business update and deduplication record
- Idempotency retention
- Reprocessing and replay semantics

## 30. Offset and delivery semantics — P1

Define explicitly:

- When offsets are committed
- Whether auto-commit is disabled for state-changing work
- Batch versus per-message processing
- At-most-once, at-least-once, and the limited scope of Kafka exactly-once features
- Consequences of retrying a batch
- Maximum processing time and poll interval
- Heartbeats and session timeouts
- Graceful shutdown and partition revocation

Never commit an offset before required durable side effects complete.

## 31. Retry and dead-letter handling — P1

Classify errors as:

- Retriable/transient
- Non-retriable/permanent
- Unknown and requiring bounded retry/inspection

Implement:

- Bounded attempts
- Backoff with jitter
- Retry topics or another non-blocking retry design when appropriate
- Dead-letter topic with original metadata, failure reason, and attempt count
- Alerts on DLQ arrival and retry backlog
- Redrive/replay tool with authorization and audit trail
- Protection against endlessly replaying poison messages

A DLQ is not a solution unless somebody owns and operates it.

## 32. Schema evolution — P1

Define compatibility policy. Teach:

- Additive changes
- Required versus optional/defaulted fields
- Producer/consumer deployment order
- Versioned event types for breaking semantic changes
- Schema registry and Avro/Protobuf/JSON Schema trade-offs
- Contract tests
- Unknown field and unknown version handling

Test old consumer/new producer and new consumer/old producer combinations relevant to rolling releases.

## 33. Kafka security and operations — P1

Cover:

- TLS in transit
- Authentication and least-privilege authorization/ACLs
- Separate credentials per service
- Secret rotation
- Broker/topic/partition health
- Producer error and retry rate
- Consumer lag and lag growth
- Throughput and message size
- Under-replicated/offline partitions
- Disk/retention pressure
- Rebalance frequency
- MSK-specific monitoring and networking considerations

Do not log sensitive event payloads.

---

# Part E — Security and privacy

## 34. Threat modelling — P0

Create a lightweight threat model covering:

- Internet client to API
- Service-to-service calls
- Application to PostgreSQL
- Application to Kafka
- CI/CD to AWS
- Operator/admin access
- Data exports, logs, backups, and dead-letter records

Identify assets, trust boundaries, likely threats, mitigations, and remaining risk. Revisit it when architecture changes.

## 35. Authentication and session/token handling — P0

Implement and teach:

- Trusted identity provider or appropriately designed authentication
- Password hashing only with a suitable adaptive algorithm if passwords are owned
- Short-lived access tokens where used
- Refresh/session revocation strategy
- Signature, issuer, audience, expiry, and algorithm validation
- Key rotation
- Secure cookie attributes if cookies are used
- CSRF protection for cookie-authenticated state changes
- Brute-force and credential-stuffing protection
- No sensitive tokens in URLs or logs

## 36. Authorization and tenant isolation — P0

Authorization must be enforced server-side for every resource operation. Cover:

- Role/permission model
- Object-level authorization
- Group membership checks
- Tenant/user isolation in queries
- Administrative operations
- Least privilege between services and AWS roles
- Tests for horizontal and vertical privilege escalation
- Avoiding stale replica reads for security-critical decisions

## 37. Input, output, and API protection — P0

Implement:

- Schema validation and rejection of unknown/dangerous input where appropriate
- Parameterized SQL/ORM safety
- Body, header, URL, and pagination limits
- Content-type checks
- Secure response headers
- CORS allowlist appropriate to clients
- Rate limiting and abuse protection
- Avoidance of mass assignment
- Safe serialization
- File-upload controls if uploads exist
- SSRF protection for server-side URL access
- Dependency-specific injection protections

## 38. Encryption and sensitive data — P0

Define:

- TLS for all network paths
- Encryption at rest using managed service capabilities
- Data classification
- Minimization of PII in events and logs
- Retention and deletion
- Backup and snapshot access
- Key ownership and rotation
- Redaction strategy
- Audit logging for sensitive administrative actions

Do not implement custom cryptography.

## 39. AWS identity and network security — P1

Design:

- IAM role per workload
- Least-privilege task roles
- No long-lived AWS keys in containers
- Private subnets for databases/brokers where appropriate
- Security groups using explicit paths
- Controlled ingress through load balancer/API gateway
- Egress awareness and restriction when justified
- Secrets Manager access scoped to required secrets
- CloudTrail/audit visibility
- Image and dependency scanning
- WAF only when threat/risk justifies it

---

# Part F — Observability and operations

## 40. Structured logging — P0

Use structured JSON logs with:

- Timestamp
- Severity
- Service name and version
- Environment
- Request/event/trace correlation identifiers
- Route or operation name
- Outcome, duration, and safe error classification
- Relevant entity identifiers when allowed

Never log secrets, access tokens, passwords, full financial payloads, or unnecessary PII. Avoid duplicate logging at every layer. Define sampling or level policy for high-volume logs.

## 41. Metrics — P0

Implement RED metrics for services:

- Request rate
- Error rate
- Duration histograms

Add saturation and dependency metrics:

- CPU, memory, event-loop delay
- Active/in-use/idle/waiting DB pool connections
- Pool acquisition timeouts
- Database latency, errors, slow queries, locks
- Kafka publish latency/errors
- Consumer throughput, failures, lag, retries, and DLQ
- Outbox backlog age and size
- Business metrics such as successful expense/settlement creation

Avoid unbounded metric-cardinality labels such as raw user ID, request ID, or event ID.

## 42. Distributed tracing — P1

Use OpenTelemetry or equivalent to trace:

- Incoming HTTP request
- Application/service operation
- PostgreSQL call
- Outbox publication where trace linkage is meaningful
- Kafka producer and consumer processing
- Downstream calls

Propagate trace/correlation context through events. Apply sampling deliberately and never attach sensitive payloads.

## 43. Health endpoints — P0

Define:

- Liveness: is the process alive and not irrecoverably stuck?
- Readiness: should it receive new traffic?
- Startup health if platform behaviour requires it

Do not make liveness fail merely because a remote dependency briefly fails, which can create restart storms. Readiness may reflect inability to serve the endpoint’s critical function.

## 44. Alerts and dashboards — P0 operationally

Create dashboards and actionable alerts for:

- SLO burn/error budget
- Sustained error and latency changes
- Task crash/restart loops
- CPU/memory/event-loop saturation
- DB connection exhaustion
- Database storage, locks, replication lag, and failover
- Kafka consumer lag growth
- Outbox oldest-message age
- Retry/DLQ accumulation
- No traffic or no successful business operations when unexpected

Every alert needs severity, owner, user impact, diagnostic links, and runbook. Avoid alerting on every transient error.

## 45. Auditability — P0 for financial/admin changes

Record who performed sensitive or financial operations, what command was accepted, when it occurred, and relevant correlation IDs. Audit logs must be tamper-resistant enough for the project’s risk, access-controlled, searchable, and retained appropriately. Do not confuse debug logs with audit records.

---

# Part G — Testing and verification

## 46. Test strategy — P0

Use a risk-based test pyramid:

- Unit tests for domain calculations and validation
- Integration tests with real PostgreSQL for constraints, transactions, repositories, and concurrency
- Integration tests with Kafka/test containers for event flows where feasible
- Contract tests for APIs and events
- End-to-end tests for critical user journeys
- A small number of smoke tests after deployment

Avoid excessive mocking of PostgreSQL/Kafka behaviour that the mock cannot reproduce.

## 47. Financial correctness tests — P0

Cover:

- Equal and exact splits
- Rounding and minor units
- Invalid totals
- Expense create/update/delete/correction policy
- Settlement effects
- Concurrent updates
- Duplicate commands
- Duplicate events
- Out-of-order events where the design permits them
- Replay/rebuild of ledger projections
- Invariants across generated/property-based cases

## 48. Failure and resilience tests — P1

Deliberately exercise:

- PostgreSQL unavailable, slow, restarted, or connection-exhausted
- Deadlock and serialization failure
- Kafka unavailable or slow
- Producer publish timeout
- Duplicate delivery
- Consumer crash before/after database commit
- Consumer rebalance during processing
- Poison event
- Outbox publisher crash before/after publish
- Read-replica lag/unavailability
- Downstream API timeout
- ECS task termination during request/event processing
- Secret/configuration missing at startup
- Telemetry backend unavailable

State expected behaviour before running each experiment.

## 49. Load, stress, soak, and capacity testing — P1

Create representative workloads rather than testing only a single endpoint:

- Normal expected load
- Peak load
- Sudden burst
- Read/write mix
- Long enough soak to reveal leaks
- Stress test to find saturation and failure mode

Measure:

- p50/p95/p99 latency
- Throughput and error rate
- CPU, memory, event-loop delay
- DB pool wait and database utilization
- Kafka lag and outbox age

Derive initial task count, autoscaling thresholds, pool size, and safe capacity with headroom. Do not advertise a request-per-second number without workload and hardware context.

## 50. Security testing — P0/P1

Include:

- Authentication and authorization negative tests
- Cross-user/group resource access
- Injection attempts
- Rate-limit behaviour
- Dependency and container scanning
- Secret scanning
- Unsafe error response checks
- Basic dynamic API security testing where feasible

Track findings to closure; scanning alone is not remediation.

---

# Part H — Delivery, AWS, and operational readiness

## 51. Container image — P0

Build a production image with:

- Multi-stage build
- Minimal trusted base image
- Supported pinned runtime version
- Non-root user
- Only required runtime artifacts/dependencies
- No source secrets or local environment files
- Correct signal forwarding
- Read-only filesystem where practical
- Image scanning
- Immutable version tag/digest
- Reasonable startup time and size

Do not run database migrations independently from every scaling application task.

## 52. CI pipeline — P0

On every change, run as appropriate:

- Formatting/linting
- Type checking
- Unit tests
- Integration tests
- Contract/schema compatibility tests
- Dependency and secret scanning
- Image build and scan
- Migration validation
- Artifact publication with immutable identity

Pull requests must not deploy unreviewed code to production.

## 53. CD and deployment safety — P0/P1

Implement or design:

- Separate environments/accounts as appropriate
- Infrastructure as code
- Repeatable deployments
- Rolling, blue/green, or canary strategy based on risk
- Readiness gates
- Backward compatibility during mixed-version operation
- Automatic halt/rollback criteria
- Roll-forward plan for database changes
- Feature flags for risky behavioural changes where justified
- Post-deployment smoke tests
- Deployment audit trail

Explain why rollback of code does not automatically roll back data or events.

## 54. ECS Fargate operation — P1

Cover:

- Task definition, CPU/memory sizing, port, health checks
- Execution role versus task role
- Service desired count across availability zones
- Load balancer target deregistration and connection draining
- Deployment minimum/maximum healthy percentages
- Autoscaling on meaningful signals
- Log and telemetry delivery
- Secret injection
- Ephemeral filesystem assumptions
- Task termination behaviour
- No reliance on local disk or process memory for durable state

## 55. RDS operation — P1

Cover:

- Multi-AZ availability versus read replicas
- Instance/storage sizing and autoscaling risks
- Connection limits and pool budgeting
- Parameter groups/timeouts
- Encryption and TLS
- Automated backups/PITR
- Maintenance windows
- Monitoring, Performance Insights, slow queries
- Failover behaviour and DNS reconnection
- Replica lag if readers exist
- Safe migration connectivity

Do not confuse Multi-AZ standby with an application-readable replica unless the chosen RDS topology explicitly provides that feature.

## 56. MSK/Kafka production operation — P1

Cover:

- Cluster sizing/topology or serverless trade-off
- Networking and authentication
- Topic replication and minimum in-sync replicas
- Producer durability settings
- Retention and storage capacity
- Partition count
- Monitoring and alarms
- Broker maintenance/failure behaviour
- Client reconnect/backoff
- Cost

## 57. Infrastructure as code — P1

Represent production infrastructure using one consistent tool such as AWS CDK, Terraform, or CloudFormation. Include reviewable definitions for networking, ECS, load balancing, IAM, secrets references, RDS, MSK dependencies, logs, alarms, and dashboards. Do not store secret values in IaC state/source when avoidable.

## 58. Runbooks and incident response — P0 operationally

Create short runbooks for:

- Elevated API errors/latency
- Database pool exhaustion
- Slow query/lock incident
- RDS failover or storage pressure
- Kafka consumer lag
- DLQ messages
- Outbox backlog
- Deployment failure
- Task crash loop
- Credential/secret rotation
- Restore from backup

Each runbook must include symptoms, impact, checks, mitigation, rollback/recovery, verification, and escalation/owner.

Teach incident principles:

- Stabilize before deeply diagnosing
- Preserve evidence without leaking sensitive data
- Communicate impact and updates
- Use blameless post-incident review
- Convert findings into owned corrective actions

## 59. Cost and capacity — P1

Estimate and monitor major cost drivers:

- ECS task CPU/memory and minimum count
- RDS instance, storage, I/O, backups, replicas
- MSK cluster/serverless throughput and storage
- NAT/data transfer
- Logs, metrics, and traces
- Secrets and load balancer

Tag resources, set budgets/alerts, and prefer a simpler architecture until measured load requires more.

---

# Part I — Conditional patterns: teach, but do not automatically implement

## 60. Apply only with evidence — P2

The following are important but not universal. Codex must explain their triggers and costs before implementation:

- Read replicas
- Redis/distributed cache
- CQRS with separate read models
- Event sourcing
- Saga orchestration/choreography
- Debezium and Kafka Connect
- Kubernetes/EKS
- Service mesh
- GraphQL
- gRPC
- Multi-region active-active
- Database sharding
- Elasticsearch/OpenSearch
- Feature-flag platform
- Dedicated secrets sidecar/agent
- Chaos engineering platform

For each, state:

- Problem it solves
- Evidence that the problem exists
- Simpler alternative
- New failure modes
- Operational ownership
- Cost
- Removal/reconsideration trigger

## 61. Patterns explicitly prohibited without justification

- Shared database tables accessed directly by multiple services
- Distributed transactions/2PC as a default answer
- Database commit followed by unprotected Kafka publish
- Kafka consumer that assumes exactly-once delivery without an end-to-end proof
- Blind retries of non-idempotent operations
- Unlimited retries
- No timeout on remote calls
- One database connection or pool per request
- Arbitrarily huge connection pools
- Using replica data for all reads regardless of consistency needs
- Storing money in JavaScript floating-point values
- In-memory authoritative state in horizontally scaled services
- Logging credentials, tokens, complete event payloads, or unnecessary PII
- Running destructive migrations from every application replica
- Adding infrastructure only to make the architecture look sophisticated

---

# Part J — Required learning deliverables

## 62. Artifacts Codex must maintain

As the project progresses, create or update:

- Architecture overview
- Context/container/component diagrams where useful
- API/OpenAPI contract
- Event catalogue and schemas
- Database schema and key query/index rationale
- ADRs
- Threat model
- SLO/SLI definition
- Test strategy and test results
- Load-test report
- Failure-injection report
- Deployment and rollback procedure
- Dashboards and alert catalogue
- Operational runbooks
- Backup/restore drill record
- Production-readiness checklist

Keep documentation close to the repository and prevent it from drifting from code.

## 63. Evidence required before marking a topic complete

A checkbox may be marked complete only when Codex can point to:

- Explanation of the problem and chosen trade-off
- Implemented code/configuration or an explicitly approved design-only outcome
- Automated verification where feasible
- At least one failure or negative test
- Relevant observability
- Documentation/ADR where the decision is material
- Learner explanation or answers demonstrating understanding

“Code compiles” and “tests pass” are necessary but insufficient.

## 64. Interview checkpoint for every major topic

Ask the learner questions such as:

- What production failure does this solve?
- What happens with five ECS tasks instead of one?
- What happens if the dependency responds after our timeout?
- Where is the transaction boundary?
- Can this operation be retried safely?
- What happens if the process crashes at each step?
- How is duplication handled?
- How would we detect this failure before a customer reports it?
- What metric would alert us?
- What is the rollback or recovery plan?
- What simpler alternative did we reject and why?
- At what scale would this design need to change?

Do not accept memorized definitions when the learner cannot apply them to Divided By All.

---

# Part K — Three-week execution order

## 65. First implementation track: production database engineering

Begin here before working through the remaining production tracks. Apply the work to every existing database-owning service, starting with Expense & Settlement because it has the highest correctness risk.

1. Inventory every service, database, schema, ORM/client, query path, migration, and current pool configuration.
2. Establish strict database ownership for User, Group, and Expense & Settlement; Activity must own its activity store if it persists data.
3. Validate PostgreSQL configuration and secrets at startup.
4. Correct money representation, financial invariants, and database constraints.
5. Implement one long-lived pool per process and calculate the total production connection budget across ECS tasks, workers, deployments, migrations, and operators.
6. Configure acquisition, idle, connection, statement, and transaction timeouts deliberately.
7. Define transaction boundaries for expenses and settlements.
8. Test isolation, concurrent updates, lost updates, locking, deadlocks, rollback, and safe retry.
9. Review queries with execution plans and add only justified indexes.
10. Implement version-controlled, backward-compatible migrations and a deployment-safe migration process.
11. Add database logs, metrics, slow-query visibility, pool saturation metrics, dashboards, and alerts.
12. Test database restart, pool exhaustion, connection leaks, slow queries, failed migrations, and rolling deployment capacity.
13. Define backup, point-in-time recovery, restore verification, RPO, RTO, and the database incident runbooks.
14. Introduce read replicas and separate reader/writer pools only after defining which reads tolerate lag and which must use the primary.

Exit condition: every accepted database operation is correct under concurrency, connections are bounded and observable, schema changes are deployable safely, database failures have predictable behaviour, and recovery has been documented and tested for the selected environment.

## 66. Week 2: reliable asynchronous system

Complete:

1. Event catalogue, schema, ownership, and partition keys
2. Kafka producer/consumer configuration
3. Transactional outbox
4. Idempotent Notification and Activity consumers
5. Offset-commit policy
6. Retries, DLQ, and redrive ownership
7. Schema evolution and contract tests
8. Consumer lag/outbox metrics and alerts
9. Trace propagation
10. Consumer/publisher crash experiments

Exit condition: no accepted expense/settlement event is silently lost, duplicates do not corrupt state, and failure/backlog is visible.

## 67. Week 3: deployment and operation

Complete:

1. Production container image
2. CI checks and artifact build
3. AWS architecture/IaC for ECS, RDS, MSK, IAM, secrets, and observability
4. Deployment compatibility and migration procedure
5. ECS termination/rolling-deployment test
6. Load, burst, stress, and soak tests
7. Pool and task-size tuning from measurements
8. Backup/restore procedure or drill
9. Dashboards, alerts, and essential runbooks
10. Security review and negative tests
11. Cost estimate
12. Final architecture/interview defence

Exit condition: the learner can deploy, observe, diagnose, recover, and explain the scoped system with evidence.

## 68. First instruction to Codex

Start with a read-only repository assessment. Produce:

1. Current architecture and runtime flow
2. Existing User, Group, Expense & Settlement, Notification, and Activity services; their databases, Kafka topics, Lambda/event-source configuration, and deployment code
3. Production-readiness gap matrix mapped to this document
4. Risks ranked by severity and likelihood
5. An application-wide production backlog with dependencies and acceptance criteria
6. A detailed first implementation backlog limited to production database engineering
7. The first small database P0 task

Do not modify code during this initial assessment. After the assessment, implement the database track first, one bounded concern at a time. Continue to treat the entire application as production-grade across code, Kafka, Lambda, security, testing, deployment, observability, and recovery. Do not assume a listed component exists merely because it appears in this document. Ask only for information that cannot be discovered from the repository or current conversation.

## 69. Final instruction

Optimise for **understanding, correctness, reliability, operability, and justified simplicity**. The goal is not to check every technology box. The goal is to build a system whose important behaviour is understood during normal operation, concurrency, partial failure, deployment, and recovery.
