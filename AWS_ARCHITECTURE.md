# AWS Architecture — Production Scale (1M Users)

## The Three Enemies at Scale

Before reading any architecture diagram, understand what we are defending against:

| Enemy | What it means | How we fight it |
|---|---|---|
| **Single Point of Failure** | One server dies → entire app is down | Multi-AZ: every layer runs in 2+ datacenters |
| **Latency** | User in Mumbai hits server in Virginia → 200ms network delay | Multi-Region + CloudFront CDN |
| **Thundering herd** | 100K users hit app at once → fixed server count collapses | Auto-scaling: AWS adds/removes tasks automatically |

---

## Core Mental Model

| Component | Single Responsibility |
|---|---|
| **Route 53** | Send each user to the nearest region (latency-based routing) |
| **CloudFront** | Serve cached content from 400+ edge locations globally (kills latency) |
| **API Gateway** | Which service handles this request? (routing + JWT auth + rate limiting) |
| **VPC Link** | Secure private tunnel from API Gateway into your VPC |
| **ALB** | Which task/instance of THAT service handles it? (load balancing + health checks) |
| **ECS Fargate** | Run the actual Node.js containers, auto-scale task count |
| **RDS / DocumentDB / ElastiCache** | Managed databases — Multi-AZ, automatic failover |

ALB should never know about other services. It only owns the tasks of one microservice.

---

## Full Architecture

```
                        USERS (Global)
                            │
                        Route 53              ← DNS: routes each user to nearest region
                            │                   (latency-based routing for multi-region)
                        CloudFront            ← CDN: 400+ edge locations worldwide
                            │                   SSL termination, caching, DDoS protection
              ┌─────────────┴──────────────┐
              │                            │
           /static/*                    /api/*
              │                            │
             S3                    AWS API Gateway   ← Public entry point for all APIs
        (MFE assets)                       │           JWT Authorizer, rate limiting,
                                           │           path-based routing
                                      VPC Link        ← Secure tunnel into private VPC
                                           │           Internal ALBs are NOT internet-facing
                          ┌────────────────┼────────────────┐
                          │                │                │
                   ALB-1 (internal)  ALB-2 (internal)  ALB-3 (internal)
                          │                │                │
                   user-service      group-service   expense-service
                   ECS tasks ×N      ECS tasks ×N    ECS tasks ×N
                   (auto-scaling)    (auto-scaling)  (auto-scaling)
                          │                │                │
                     DocumentDB        RDS              RDS
                     (Multi-AZ)     (PostgreSQL,     (PostgreSQL,
                          │          Multi-AZ)        Multi-AZ)
                     ElastiCache
                     Redis (Multi-AZ)

Next.js SSR Host App → separate ECS cluster + ALB (or AWS Amplify)
```

---

## What "Multi-AZ" Means

AWS regions are divided into **Availability Zones (AZs)** — physically separate datacenters
within the same city, connected by fast private fiber.

- `us-east-1` has 6 AZs: `us-east-1a`, `1b`, `1c`, `1d`, `1e`, `1f`
- If `us-east-1a` catches fire — `us-east-1b` is completely unaffected

At 1M users, every database, every load balancer, every ECS service runs across **at least
2 AZs**. If one AZ fails, traffic shifts to the other within seconds. Zero downtime.

---

## What "Multi-Region" Means

At 1M users across regions, you run the entire stack in multiple AWS regions:

| Region | Users it serves |
|---|---|
| `us-east-1` (Virginia) | North America |
| `eu-west-1` (Ireland) | Europe |
| `ap-south-1` (Mumbai) | India, South Asia |
| `ap-southeast-1` (Singapore) | East Asia |

Route 53 **latency-based routing** automatically sends each user to the nearest region.
A Mumbai user never hits Virginia.

> We nail `us-east-1` first. Every decision is made with multi-region in mind so we
> don't rewrite everything later (e.g. stateless services, distributed session storage).

---

## Component Breakdown

### Route 53
- DNS management
- **Latency-based routing** — directs users to the nearest healthy region automatically
- Health checks — if a region goes down, Route 53 stops sending traffic there
- Points your domain to CloudFront

### CloudFront
- CDN — caches static assets at 400+ edge locations globally
- SSL/TLS termination (HTTPS) — handles certificates via ACM
- DDoS protection via AWS Shield Standard (free)
- Routes `/static/*` MFE assets to S3, `/api/*` to API Gateway
- Cache behaviors:
  - `remoteEntry.js` — short TTL (60s), changes on every deploy
  - Static JS/CSS chunks (content-hashed filenames) — long TTL (1 year)

### S3
- Hosts Profiles MFE static build artifacts (`remoteEntry.js`, JS chunks)
- Never goes down, infinitely scalable, 99.999999999% durability
- Versioning enabled — instant rollback if a bad deploy goes out

### AWS API Gateway (HTTP API)
- Public entry point for all API traffic — the only thing internet-facing on the API side
- Path-based routing: `/auth/*` → user-service, `/groups/*` → group-service, `/expenses/*` → expense-service
- **JWT Authorizer** validates token before forwarding protected routes (replaces Nginx `auth_request`)
- Built-in rate limiting and throttling — protects services from abuse
- Connects to internal ALBs via VPC Link
- At 1M users: handles millions of requests/day without any infrastructure to manage

### VPC Link
- Secure private connection from API Gateway into your VPC
- Internal ALBs are not internet-facing — only reachable through VPC Link
- Attackers cannot hit your services directly even if they know the ALB DNS name

### VPC + Subnets

```
VPC: 10.0.0.0/16
│
├── Public Subnets (us-east-1a, us-east-1b)   ← NAT Gateway lives here
│   10.0.1.0/24, 10.0.2.0/24
│
└── Private Subnets (us-east-1a, us-east-1b)  ← ECS tasks, RDS, Redis, DocumentDB
    10.0.3.0/24, 10.0.4.0/24
```

- ECS tasks live in private subnets — no direct internet access
- They reach the internet (for npm, ECR pulls) via NAT Gateway in public subnet
- Databases are in private subnets — no public endpoint, ever

### Security Groups (firewall rules per resource)

| Security Group | Inbound rule | Purpose |
|---|---|---|
| `sg-alb` | 80, 443 from VPC Link | ALBs only accept traffic from API Gateway |
| `sg-ecs-tasks` | all from `sg-alb` | Tasks only accept traffic from their ALB |
| `sg-rds` | 5432 from `sg-ecs-tasks` | DB only accepts traffic from ECS tasks |
| `sg-redis` | 6379 from `sg-ecs-tasks` | Redis only accepts traffic from ECS tasks |
| `sg-docdb` | 27017 from `sg-ecs-tasks` | DocumentDB only accepts from ECS tasks |

### ALB (one per service — all internal)
- Load balances traffic across ECS tasks of its own service only
- Health checks — automatically removes unhealthy tasks, adds new ones
- Each service owns and scales its ALB independently
- Target type = **IP** (required for Fargate — tasks have no fixed IPs)
- At 1M users: if group-service needs 20 tasks, only group-service ALB scales

### ECS Fargate (one cluster per service)
- Runs Docker containers without managing any servers
- **Auto Scaling policy**: scale out when CPU > 70%, scale in when CPU < 30%
- Min tasks: 2 (always Multi-AZ), Max tasks: set per service based on load
- Pulls images from ECR
- At 1M users: a viral moment triggers auto-scale — 2 tasks → 50 tasks in minutes

### RDS (PostgreSQL) — for group-service and expense-service
- Managed PostgreSQL, fully patched and backed up by AWS
- **Multi-AZ**: primary in `us-east-1a`, standby replica in `us-east-1b`
- Automatic failover in ~60 seconds if primary fails
- Runs in private subnet — no internet access
- Daily automated backups, 7-day retention
- At 1M users: **Read Replicas** for read-heavy queries (groups listing, expense history)

### DocumentDB — for user-service
- Managed MongoDB-compatible database
- Multi-AZ with automatic failover
- Runs in private subnet
- Requires TLS — bundle `global-bundle.pem` CA cert in the Docker image

### ElastiCache (Redis) — for user-service
- Managed Redis for session storage and caching
- **Cluster mode** for horizontal scaling across multiple shards
- Multi-AZ with automatic failover
- Runs in private subnet
- At 1M users: Redis handles millions of session lookups per day — never hits the DB

---

## Per-Service ALB Routing

```
API Gateway (JWT auth happens HERE for protected routes)
  │
  ├── ANY /auth/*      → ALB-1 → user-service tasks (port 8000)
  │                             (no auth required — this IS the auth service)
  │
  ├── ANY /profiles/*  → ALB-1 → user-service tasks (port 8000)
  │                             (JWT Authorizer applied)
  │
  ├── ANY /groups/*    → ALB-2 → group-service tasks (port 4002)
  │                             (JWT Authorizer applied)
  │
  └── ANY /expenses/*  → ALB-3 → expense-service tasks
                                 (JWT Authorizer applied)
```

### Why one ALB per service
- **Independent deployability** — group-service deploys without touching user-service infra
- **Failure isolation** — if expense-service crashes, only `/expenses/*` returns 503
- **Independent scaling** — each service scales its own tasks and ALB

---

## Secrets Management

Never store secrets in code, Docker images, or `.env` files committed to git.

| Environment | How secrets are stored |
|---|---|
| Local dev | `.env` files (gitignored) |
| AWS (ECS) | **Secrets Manager** — ECS pulls at container startup |

ECS Task Definition references secrets like:
```json
"secrets": [
  {
    "name": "MONGO_URL",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:divided-by-all/user-service:MONGO_URL::"
  }
]
```

The secret value is never baked into the Docker image. Rotating a secret = update in
Secrets Manager, redeploy ECS. No code change needed.

---

## Environment Variables: Local vs Production

Application code never changes — it always reads `process.env`:

```bash
# Local (.env — never committed)
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/group_service
REDIS_HOST=localhost
MONGO_URL=mongodb://localhost:27017/devtinder

# Production (ECS Task Definition pulls from Secrets Manager)
DATABASE_URL=postgresql://user:pass@your-rds.us-east-1.rds.amazonaws.com:5432/group_service
REDIS_HOST=your-cluster.abc123.cache.amazonaws.com
MONGO_URL=mongodb://your-docdb.us-east-1.docdb.amazonaws.com:27017/devtinder?tls=true
```

---

## CI/CD Pipeline

```
Developer pushes code
  │
  └── GitHub Actions triggered
        │
        ├── Run tests
        │
        ├── docker build --platform linux/amd64
        │   (platform flag critical for Apple Silicon Macs — Fargate is x86)
        │
        ├── Push image to ECR (tagged with git SHA)
        │
        └── aws ecs update-service --force-new-deployment
              │
              └── Rolling deploy:
                    - ECS starts new tasks with new image
                    - Waits for new tasks to pass health checks
                    - Only then drains and kills old tasks
                    - Zero downtime throughout
```

- **Staging**: deploys on every merge to `main`
- **Production**: deploys on a release tag (`v1.2.3`)
- At 1M users: blue/green deployment (zero-risk cutover) added later

---

## Observability (Monitoring)

At 1M users you need to know something is broken **before** users complain.

| Tool | What it watches |
|---|---|
| **CloudWatch Metrics** | CPU, memory, request count, error rate per ECS service |
| **CloudWatch Alarms** | Alert when error rate > 1% or P99 latency > 500ms |
| **CloudWatch Logs** | All container stdout/stderr streamed and searchable |
| **ALB Access Logs** | Every request logged to S3 for debugging |
| **X-Ray** | Distributed tracing — see exactly which service is slow |

---

## Deployment Roadmap (Step by Step)

| Step | What we build | Why it matters at 1M users |
|---|---|---|
| 0 | AWS CLI + IAM user setup | Never use root account — least-privilege access |
| 1 | VPC + Subnets + Security Groups | Private network — nothing exposed to internet directly |
| 2 | RDS PostgreSQL (Multi-AZ) | groups-service DB, survives AZ failure automatically |
| 3 | ElastiCache Redis (Multi-AZ) | Session store — shared across all user-service tasks |
| 4 | DocumentDB (Multi-AZ) | user-service MongoDB-compatible DB |
| 5 | ECR | Docker image registry — where ECS pulls images from |
| 6 | ECS Fargate + Auto Scaling | Containers that scale from 2 to 200 tasks automatically |
| 7 | Internal ALBs (one per service) | Load balance across tasks, automatic health checks |
| 8 | VPC Link | API Gateway → private VPC secure tunnel |
| 9 | AWS API Gateway | Public entry, JWT auth, rate limiting |
| 10 | S3 + CloudFront | Global CDN — 400ms → <10ms for static assets |
| 11 | Route 53 | DNS + latency-based routing for multi-region |
| 12 | Secrets Manager | Zero secrets in code, images, or env files |
| 13 | CloudWatch + Alarms | Know when things break before users do |
| 14 | CI/CD (GitHub Actions) | Push code → auto deploy, zero manual steps |

---

## Local Development

```
npm run dev        # run each service natively (fast, no Docker overhead)
docker-compose up  # only for infrastructure: PostgreSQL, MongoDB, Redis
```

Production infrastructure (RDS, DocumentDB, ElastiCache) is never used in local dev.
Environment variables drive the difference — application code never changes.
