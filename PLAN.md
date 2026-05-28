# Migration Plan: Sessions → JWT + AWS-Ready Architecture

## Goal
Migrate from session-based auth (Redis) to JWT, clean up local dev, and prepare every service for AWS deployment.

---

## Current State

| Service | Auth | DB | Issues |
|---|---|---|---|
| user-service | Session → Redis cookie | MongoDB Atlas | Sessions don't work with API Gateway |
| group-service | Reads `X-User-Id` header (set by Nginx) | PostgreSQL (Docker) | Header set by Nginx — no Nginx in AWS |
| expense-service | Unknown | Unknown | Not wired up |
| api-gateway (Nginx) | `auth_request /auth/validate` | — | Being replaced by AWS API Gateway |

---

## Phase 1 — JWT Migration (user-service)

**Why first:** Everything else depends on this. API Gateway JWT Authorizer, group-service auth, local dev — all blocked until JWT is in place.

### 1.1 — Replace session logic with JWT in `auth_session.ts`

**Login route** — instead of creating a Redis session:
- Sign a JWT with `{ userId }` payload using `jsonwebtoken` (already installed)
- Set it as an `httpOnly` cookie (`token=...`) instead of `session_id`
- Remove all `redis.set(...)` calls from login

**Logout route** — instead of deleting Redis session:
- Clear the `token` cookie on the client
- No server-side state to delete (stateless)

**Signup route** — no change needed

**`/auth/validate` route** — instead of Redis lookup:
- Read `token` from cookie
- Verify JWT signature using `jwt.verify()`
- If valid, set `X-User-Id` header and return 200
- If invalid, return 401

### 1.2 — Replace `requireAuth` middleware in `middleware/auth.ts`

Current (session-based):
```ts
const session = await redis.get(`session:${sessionId}`)
req.user = JSON.parse(session)
```

New (JWT):
```ts
const token = req.cookies?.token
const decoded = jwt.verify(token, process.env.JWT_SECRET)
req.user = decoded  // { userId }
```

### 1.3 — Remove Redis dependency from user-service

- Redis was only used for sessions
- Remove `redis.ts` config file
- Remove `ioredis` calls from auth routes
- Keep `ioredis` package for now (may use Redis for caching later)

### 1.4 — Environment variables

Add to `.env`:
```
JWT_SECRET=your-secret-here
JWT_EXPIRES_IN=7d
```

Never hardcode the secret. In AWS this comes from Secrets Manager.

---

## Phase 2 — Fix group-service auth

**Problem:** group-service currently reads `X-User-Id` from a header set by Nginx. In AWS, API Gateway JWT Authorizer sets this header after validating the token. Locally there is no Nginx.

### 2.1 — Update `extractUserId` middleware in `middleware/auth.ts`

For local dev, read the JWT directly from the cookie and extract `userId`:
```ts
// If X-User-Id header exists (set by API Gateway in prod), use it
// Otherwise (local dev), verify JWT from cookie directly
```

This way:
- **Local:** middleware verifies JWT itself (no gateway needed)
- **Prod:** API Gateway validates JWT, sets `X-User-Id` header, middleware reads it

### 2.2 — Add `.env` to group-service

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/group_service
JWT_SECRET=your-secret-here   # same secret as user-service
PORT=4002
```

---

## Phase 3 — Local dev setup (no Docker for app code)

### 3.1 — Run infrastructure only via Docker Compose

Create a single `docker-compose.dev.yml` at the root of the microservices repo:
```yaml
# Only databases and Redis — no app services
services:
  mongo:     # for user-service
  postgres:  # for group-service
  redis:     # optional, for future caching
```

### 3.2 — Run each service natively

```bash
# Terminal 1
cd User && npm run dev        # localhost:8000

# Terminal 2
cd groups-service && npm run dev   # localhost:4002

# Terminal 3
cd expense-service && npm run dev  # localhost:5000
```

### 3.3 — Add `.env.example` to every service

So any developer knows exactly which env vars to set:

**User service:**
```
MONGO_URL=mongodb://localhost:27017/devtinder
JWT_SECRET=
JWT_EXPIRES_IN=7d
PORT=8000
```

**Groups service:**
```
DATABASE_URL=postgresql://postgres:postgres@localhost:5434/group_service
JWT_SECRET=
PORT=4002
```

---

## Phase 4 — Wire up expense-service

- Audit current state of expense-service
- Apply same JWT middleware pattern as group-service
- Add `.env.example`
- Ensure it runs on its own port (e.g. 5000)

---

## Phase 5 — Docker images for prod (ECR)

Each service already has a `Dockerfile`. Verify each one:
- Uses multi-stage build (build → production)
- Runs `npm run build` then `node dist/index.js`
- No `.env` files baked in (all config via env vars at runtime)
- `.dockerignore` excludes `node_modules`, `.env`

---

## Phase 6 — AWS deployment (in order)

### 6.1 Networking
- VPC with public + private subnets across 2 AZs
- NAT Gateway (private subnet services need outbound internet for ECR pulls)
- Security Groups per service

### 6.2 Databases
- **RDS (PostgreSQL)** for group-service and expense-service
- **MongoDB Atlas** (easier than DocumentDB for beginners, same connection string format)
- **ElastiCache (Redis)** — optional for now, add when needed for caching

### 6.3 ECR
- One repository per service: `user-service`, `group-service`, `expense-service`
- Push images: `docker build → docker tag → docker push`

### 6.4 ECS Fargate (one service at a time)
- Start with user-service — get it fully working end to end first
- ECS Cluster → Task Definition → Service
- Internal ALB per service (not internet-facing)
- Service Discovery via AWS Cloud Map (`.local` DNS names between services)

### 6.5 API Gateway
- HTTP API type (not REST API — simpler, cheaper)
- JWT Authorizer: points to user-service JWKS endpoint or shared secret
- Routes: `/auth/{proxy+}`, `/groups/{proxy+}`, `/expenses/{proxy+}`
- VPC Link to connect to internal ALBs

### 6.6 Frontend
- S3 + CloudFront for Profiles MFE
- ECS Fargate for Next.js SSR shell (or Amplify)

### 6.7 Route 53 + SSL
- ACM certificate for your domain
- CloudFront distribution with custom domain

### 6.8 Secrets Manager
- Move all secrets (JWT_SECRET, DB passwords, MONGO_URL) out of env files
- ECS Task Definition references Secrets Manager ARNs — injected at runtime

---

## Phase 7 — CI/CD

GitHub Actions workflow per service:
```
on: push to main
  → run tests
  → docker build
  → push to ECR
  → aws ecs update-service --force-new-deployment
```

Staging on every merge to main. Production on release tag.

---

## Immediate next step

**Start with Phase 1 — JWT migration in user-service.**

Files to change:
- `User/src/router/auth_session.ts` — login, logout, validate routes
- `User/src/middleware/auth.ts` — replace Redis session lookup with jwt.verify
- `User/src/config/redis.ts` — remove or keep for future caching
- `User/.env` — add JWT_SECRET
