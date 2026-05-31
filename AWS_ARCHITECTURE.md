# AWS Architecture

## Core Mental Model

| Component | Single Responsibility |
|---|---|
| **API Gateway** | Which service should handle this request? (routing + auth) |
| **ALB** | Which task/instance of THAT service handles it? (load balancing) |
| **ECS Fargate** | Run the actual Node.js application code |
| **VPC Link** | Secure tunnel from API Gateway into the private VPC |

ALB should never know about other services. It only owns the tasks of one microservice.

---

## Full Architecture

```
Browser
  │
Route 53 (DNS)
  │
CloudFront (CDN, SSL, caching)
  ├── /static/*  →  S3 (Profiles MFE static assets)
  └── /api/*     →  AWS API Gateway (HTTP API)
                          │
                    JWT Authorizer (validates token on protected routes)
                          │
                       VPC Link
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ALB-1 (internal)  ALB-2 (internal)  ALB-3 (internal)
          │               │               │
   user-service      group-service   expense-service
   ECS tasks         ECS tasks       ECS tasks
          │               │
    DocumentDB         RDS (PostgreSQL)
          │
    ElastiCache (Redis)

Next.js SSR shell → separate ECS + ALB (or AWS Amplify)
```

---

## Component Breakdown

### Route 53
- DNS management
- Points your domain to CloudFront

### CloudFront
- CDN — caches static assets at edge locations globally
- SSL termination (HTTPS)
- Routes static MFE assets to S3, everything else to API Gateway

### S3
- Hosts Profiles MFE static build artifacts (`remoteEntry.js`, JS chunks)
- `remoteEntry.js` — short Cache-Control TTL
- Static chunks — long Cache-Control TTL (content-hashed filenames)

### AWS API Gateway (HTTP API)
- Public entry point for all API traffic
- Path-based routing: `/auth/*`, `/groups/*`, `/expenses/*`
- JWT Authorizer validates token before forwarding protected routes
- Rate limiting and throttling built-in
- Connects to internal ALBs via VPC Link

### VPC Link
- Secure private connection from API Gateway into your VPC
- Internal ALBs are not internet-facing — only reachable through VPC Link

### ALB (one per service — all internal)
- Load balances traffic across ECS tasks of its own service only
- Health checks — removes unhealthy tasks automatically
- Each service team owns and scales their ALB independently

### ECS Fargate (one cluster per service)
- Runs Docker containers without managing servers
- Auto-scales task count based on CPU/memory
- Pulls images from ECR

### RDS (PostgreSQL)
- Managed PostgreSQL for group-service (and expense-service)
- Runs in private subnet — not internet accessible
- Multi-AZ for production (automatic failover)

### DocumentDB
- Managed MongoDB-compatible database for user-service
- Runs in private subnet

### ElastiCache (Redis)
- Managed Redis for session storage and caching (user-service)
- Runs in private subnet

---

## Per-Service ALB Layout

```
API Gateway
  │
  ├── /auth/*      → ALB-1 → user-service task 1
  │                        → user-service task 2
  │                        → user-service task 3
  │
  ├── /groups/*    → ALB-2 → group-service task 1
  │                        → group-service task 2
  │
  └── /expenses/*  → ALB-3 → expense-service task 1
                           → expense-service task 2
```

### Why one ALB per service
- Independent deployability — group-service team deploys without touching user-service infra
- Failure isolation — if expense-service crashes, only `/expenses/*` returns 503
- Independent scaling — each service scales its own tasks and ALB

---

## Local Development

```
npm run dev        # run each service natively (fast, no Docker overhead)
docker-compose up  # only for infrastructure: PostgreSQL, MongoDB, Redis
```

Environment variables drive the difference between local and prod:

```bash
# Local (.env — never committed)
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/group_service
REDIS_HOST=localhost
MONGO_URL=mongodb://localhost:27017/devtinder

# Production (ECS Task Definition / Secrets Manager)
DATABASE_URL=postgresql://user:pass@your-rds.us-east-1.rds.amazonaws.com:5432/group_service
REDIS_HOST=your-cluster.abc123.cache.amazonaws.com
MONGO_URL=mongodb://your-docdb.us-east-1.docdb.amazonaws.com:27017/devtinder
```

Application code never changes — it reads `process.env` regardless of environment.

---

## Secrets Management

- Local: `.env` files (gitignored)
- AWS: **Secrets Manager** or **Parameter Store**
- ECS pulls secrets at container startup — never baked into Docker images

---

## CI/CD Pipeline

```
git push
  → GitHub Actions
  → run tests
  → docker build
  → push image to ECR
  → deploy to ECS (update-service --force-new-deployment)
  → rolling deploy (old tasks stay up until new tasks are healthy)
```

Staging deploys on every merge to main. Production deploys on a release tag.

---

## AWS Console Setup Order (Beginner Path)

1. **VPC + Subnets** — public subnets (ALB, NAT) and private subnets (ECS, RDS, Redis)
2. **RDS** — PostgreSQL in private subnet
3. **ElastiCache** — Redis in private subnet
4. **DocumentDB** — MongoDB-compatible in private subnet
5. **ECR** — push Docker images
6. **ECS Fargate** — deploy one service, get it running
7. **Internal ALB** — one per service, health checks configured
8. **VPC Link** — connect API Gateway to internal ALBs
9. **AWS API Gateway** — path routing + JWT Authorizer
10. **S3 + CloudFront** — deploy Profiles MFE
11. **Route 53** — point domain to CloudFront
12. **Secrets Manager** — move all credentials out of env files
13. **CDK (TypeScript)** — codify everything once you understand it visually
