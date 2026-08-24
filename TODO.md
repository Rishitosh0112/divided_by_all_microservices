# Togetherly: scalability roadmap

This is a staged path from the current single-region ECS deployment to a resilient,
high-throughput platform. A "1M RPS" goal must always name the route, payload size,
read/write ratio, latency objective, geographic distribution, and budget.

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
