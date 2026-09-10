# Togetherly: scalability roadmap

This is a staged path from the current single-region ECS deployment to a resilient,
high-throughput platform. A "1M RPS" goal must always name the route, payload size,
read/write ratio, latency objective, geographic distribution, and budget.

## Production-grade implementation track

Source of truth: [`Production_Grade.md`](./Production_Grade.md). Complete P0 work
before introducing conditional P2 infrastructure. The first implementation track is
database production engineering, beginning with Expense & Settlement because it has
the highest correctness risk.

### P0 — database correctness and deployment safety

- [ ] Inventory every service database, schema, ORM/client, migration, query path,
  connection pool, and production connection budget.
- [ ] Record database ownership: User → DocumentDB; Groups → PostgreSQL; Expense &
  Settlement → separate PostgreSQL database; Activity → its own store if persisted.
- [ ] Create Expense & Settlement's version-controlled initial migration; do not use
  schema push for deploys.
- [ ] Enforce Expense database invariants with PostgreSQL constraints: required
  fields, positive expense amounts, non-negative split/balance amounts, ISO-style
  currencies, foreign keys, and unique split participants.
- [ ] Document which financial invariants remain application-owned because they need
  trusted Group membership state or cross-service authorization.
- [ ] Define transaction boundaries for every expense and settlement write; never
  make remote calls inside a financial transaction.
- [ ] Add real-PostgreSQL integration tests for rollback, concurrent balance updates,
  conflicting writes, transaction reuse, and database rejection of invalid data.
- [ ] Configure and validate one long-lived database pool per process, including
  acquisition, idle, query/statement, connection-lifetime, and transaction timeouts.
- [ ] Add startup configuration validation; do not listen for traffic before required
  database configuration and connectivity policy are satisfied.
- [ ] Add liveness/readiness endpoints and graceful shutdown that drains HTTP work and
  closes database clients within a deadline.
- [ ] Move migrations out of application-container startup into one serialized,
  deploy-safe migration job; use expand-and-contract schema changes.
- [ ] Review representative queries with `EXPLAIN (ANALYZE, BUFFERS)` and add only
  query-justified indexes and bounded pagination.
- [ ] Add database/pool metrics, slow-query and lock-wait visibility, dashboards, and
  alerts for saturation and user-impacting failures.
- [ ] Define RPO/RTO, backup retention, point-in-time recovery, restore verification,
  and database incident runbooks; record a restore drill.

### P1 — reliable asynchronous services

- [ ] Define the event catalogue, owners, schemas, topic names, partition keys, and
  compatibility rules for Groups and Expense events.
- [ ] Add client-supplied idempotency keys for retried Expense/Settlement writes,
  including payload mismatch and concurrent-request behavior.
- [ ] Implement a transactional outbox within the Expense transaction and a bounded,
  observable publisher.
- [ ] Introduce Kafka locally and MSK in AWS only with explicit producer, consumer,
  retry, DLQ, offset, and security policies.
- [ ] Implement idempotent Notification Lambda event processing and Activity Service
  consumers; treat both as eventually consistent.
- [ ] Add outbox age, publish error, consumer lag, DLQ, and trace-propagation metrics
  with actionable alarms.

### P0/P1 — application-wide operation

- [ ] Define SLOs/SLIs for core writes and reads, including p50/p95/p99 latency,
  availability, durability, RPO, RTO, traffic assumptions, and error budgets.
- [ ] Establish stable API contracts: validation, error codes, request IDs, body and
  pagination limits, versioning, OpenAPI, and backward-compatible deprecation.
- [ ] Enforce authentication, resource authorization, tenant isolation, secret
  handling, least privilege, and a threat model for every externally reachable API.
- [ ] Add structured redacted logs, metrics, distributed traces, financial audit
  records, dashboards, alerts, and on-call runbooks.
- [ ] Add unit, integration, contract, end-to-end, load, failure, and security tests
  appropriate to each capability.
- [ ] Upgrade CI/CD to run tests, type checks, migration validation, dependency and
  image scanning, immutable image builds, deployment checks, and rollback/roll-forward
  procedures.
- [ ] Make ECS deployment capacity and health checks safe for rolling deployments;
  test SIGTERM, dependency failure, database restart, pool exhaustion, and task loss.

### P2 — introduce only with evidence

- [ ] Add read replicas and separate reader/writer pools only after defining
  lag-tolerant reads and demonstrating primary read pressure.
- [ ] Add Redis caching only for a measured latency/load problem and with an explicit
  invalidation and stale-data policy; never cache authoritative balances casually.
- [ ] Add autoscaling, advanced Kafka tooling, and multi-region components only after
  measurement, SLOs, failure modes, cost, and operational ownership justify them.

## 0. Cost and safety baseline

- [x] Add a pause/resume script for ECS tasks, EC2 capacity, RDS, and DocumentDB.
- [x] Verify all paused services have zero running tasks and zero ECS EC2 instances.
- [ ] Identify and remove or manage unrelated `us-east-1` resources that continue to cost money.
- [ ] Create AWS Budgets and cost-anomaly alerts for the development account.
- [ ] Keep high-scale experiments in a separate staging/load-test environment with a hard budget.

## 1. Current application reliability

- [x] Route Frontend Shell → API Gateway privately through ECS Service Connect.
- [x] Route API Gateway → User Service privately through ECS Service Connect.
- [x] Add the API Gateway security-group egress rule for User Service port `8000`.
- [x] Add a User Service container health check on `/health`.
- [ ] Add container health checks for every remaining service.
- [ ] Define readiness, liveness, timeout, retry, and graceful-shutdown behavior for every service.
- [ ] Add structured logs, request IDs, error metrics, and tracing across services.

## 2. Measure before scaling

- [ ] Resume the environment only when needed.
- [ ] Define the first User Service load-test route; use a non-writing endpoint before testing signup.
- [ ] Create safe test data and a cleanup plan for all write tests.
- [ ] Run an incremental baseline test: 10 → 50 → 100 RPS.
- [ ] Record p50/p95/p99 latency, error rate, CPU, memory, network, database connections, and cost.
- [ ] Find the first bottleneck and fix it before raising the request rate.

## 3. Single-region horizontal scaling

- [ ] Make every API service stateless so any task can serve any request.
- [ ] Add ECS Service Auto Scaling for API Gateway using `ALBRequestCountPerTarget` and CPU.
- [ ] Add ECS Service Auto Scaling for User and Groups services using CPU/memory/custom metrics.
- [ ] Configure EC2 capacity-provider/Auto Scaling Group capacity to grow with ECS task demand.
- [ ] Use at least two Availability Zones and test task/instance failure recovery.
- [ ] Add deployment alarms and rollback criteria.
- [ ] Load test task scale-out, scale-in, and recovery under controlled traffic.

## 4. Remove database pressure from hot paths

- [ ] Introduce Redis/ElastiCache for sessions, rate limits, hot reads, and cache invalidation.
- [ ] Add idempotency keys for write endpoints.
- [ ] Move asynchronous work to SQS/Kinesis and worker services.
- [ ] Batch durable writes where product semantics allow it.
- [ ] Add connection pooling and database query monitoring.
- [ ] Review indexes and remove inefficient database-query patterns.

## 5. Product-specific scale design

- [ ] Serve Frontend Shell and MFEs from S3 + CloudFront rather than ECS where feasible.
- [ ] Upload video directly from browser to S3 using presigned URLs.
- [ ] Deliver video through CloudFront; use asynchronous media processing where needed.
- [ ] Build chat as a separate WebSocket/realtime service with durable event and fan-out design.
- [ ] Add WAF, rate limiting, abuse prevention, and per-user quotas at the edge.

## 6. Global and very-high-scale architecture

- [ ] Define concrete targets for cached reads, authenticated reads, writes, chat connections, and video traffic.
- [ ] Add multi-region active-active or active-passive strategy only after single-region scaling is proven.
- [ ] Evaluate Global Accelerator/Route 53 routing and regional failover.
- [ ] Design cross-region data replication and consistency rules.
- [ ] Create an isolated load-test account/environment and obtain required AWS quotas.
- [ ] Run progressively larger tests: 1k → 10k → 100k RPS before considering 1M RPS.
- [ ] Document capacity model, failure modes, rollback plan, and per-test spend limit.

## Definition of done for a 1M-RPS claim

- [ ] Specify the exact endpoint mix and response payload sizes.
- [ ] Sustain the stated rate for a defined duration with a defined p99 latency and error-rate target.
- [ ] Demonstrate database/cache/queue behavior under the same workload.
- [ ] Demonstrate autoscaling, AZ failure recovery, and load shedding.
- [ ] Capture the measured infrastructure cost and capacity assumptions.
