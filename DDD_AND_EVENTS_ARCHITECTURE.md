# Clean Code, Domain-Driven Design & Event Architecture

This document is the companion to [`AWS_ARCHITECTURE.md`](./AWS_ARCHITECTURE.md). That doc
answers "how does a request survive at 1M users?" This doc answers two different questions:

1. **How should code inside each service be organized** so business logic is easy to find,
   test, and change without breaking unrelated things? (Clean Code / DDD)
2. **How do services talk to each other asynchronously** instead of only via synchronous
   HTTP, and what does that look like as a managed AWS service? (Kafka → MSK)

No code changes yet — this is the target shape we refactor towards.

---

## Part 1 — Where We Are Today (honest audit)

| Service | Current layering | Problem |
|---|---|---|
| **User** | Router → Mongoose model, directly. `router/profile.ts` mixes validation, `req.user` mutation, and a redundant second `User.updateOne()` write for the same field. `router/auth_jwt.ts` does password hashing + JWT signing + cookie-setting inline in the route handler. `dal/index.ts` is mislabeled — it holds unrelated leftover `Discount` class code, not a real data-access layer. | No service layer. Business rules (password policy, session rules, profile-edit rules) are not in one place — they're smeared across route handlers. Impossible to unit test without spinning up Express + Mongo. |
| **groups-service** | Router → Controller (`asyncHandler` + validators) → `GroupService` (business rules + Prisma calls + authorization checks) → Prisma. | Closest to clean already. But `GroupService` still does two jobs: enforcing domain rules (*"only the creator can delete a group"*) **and** persistence (`prisma.group.create(...)`). Those are different concerns wearing one hat. |
| **expense-service** | Doesn't exist yet (empty directory). | Blank slate — the one service we can build DDD-correct from day one, no migration cost. |
| **SSR host + MFE** | Redux slices call `fetch()` directly inside `createAsyncThunk`. Two near-duplicate `groupSlice.ts` files (host `app/store/` and remote `client-side-app/src/store/`). | No API-client abstraction; duplicated logic between host and remote frontend. |

This audit matters because DDD isn't "add folders called `domain/`" — it's about *separating
things that change for different reasons*. Today, a change to "how we hash passwords" and a
change to "what a valid profile edit looks like" both require touching the same file
(`router/auth_jwt.ts` / `router/profile.ts`). That's the smell we're fixing.

---

## Part 2 — Target Layering (Clean Architecture, per service)

Each backend service gets the same four layers, dependency arrows pointing **inward only**:

```
┌─────────────────────────────────────────────────────┐
│  Interface Layer          (routers, controllers)     │  ← knows HTTP, knows Express
│  ┌─────────────────────────────────────────────────┐ │
│  │  Application Layer      (use cases / services)   │ │  ← orchestrates, no HTTP, no SQL
│  │  ┌───────────────────────────────────────────┐   │ │
│  │  │  Domain Layer   (entities, value objects,  │   │ │  ← pure business rules,
│  │  │                  domain events, invariants) │   │ │    zero dependencies
│  │  └───────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────┘ │
│  Infrastructure Layer    (Prisma/Mongoose repos,     │  ← knows the DB, the
│  Kafka producers, Redis)                             │    message broker
└─────────────────────────────────────────────────────┘
```

**The rule that makes this work:** the Domain layer never imports from Infrastructure.
Infrastructure implements interfaces (ports) that Domain/Application defines. This is what
lets you swap Prisma for something else, or unit-test a domain rule with zero database.

### Proposed folder structure (per service)

```
src/
├── domain/                    # Pure business logic. No express, no prisma, no mongoose.
│   ├── group/
│   │   ├── group.entity.ts        # Group class: invariants, e.g. "name required, max 100 chars"
│   │   ├── group-member.entity.ts
│   │   ├── group.repository.ts    # INTERFACE only: findById(), save() — no implementation
│   │   └── group.events.ts        # GroupCreated, MemberInvited, MemberJoined (domain events)
│   └── shared/
│       └── errors.ts               # NotFound, Forbidden, ValidationError (already exists, keep it)
│
├── application/                # Use cases — one file per user-facing action, orchestrates domain + infra
│   ├── create-group.usecase.ts
│   ├── invite-member.usecase.ts
│   └── resolve-invitation.usecase.ts
│
├── infrastructure/              # Everything that talks to the outside world
│   ├── persistence/
│   │   └── prisma-group.repository.ts   # implements domain/group/group.repository.ts
│   ├── messaging/
│   │   └── kafka-producer.ts
│   └── config.ts
│
└── interface/                   # HTTP-facing
    ├── routers/
    │   └── group.router.ts
    ├── controllers/
    │   └── group.controller.ts
    └── middleware/
        └── auth.ts, errorHandler.ts
```

**What actually moves, concretely, in groups-service:**
- `services/group-service.ts` splits into: `domain/group/group.entity.ts` (invariants —
  e.g. "a group must have a name, `createdBy` cannot change") + one `application/*.usecase.ts`
  per operation (createGroup, inviteMember, resolveInvitation, removeMember) +
  `infrastructure/persistence/prisma-group.repository.ts` (the actual `prisma.group.create()` calls).
- Authorization checks like *"only creator can delete"* are a **domain rule** → they move
  into `group.entity.ts` or a domain service, not the use case, and definitely not the controller.
- `controllers/group-controller.ts` shrinks to: parse request → call one use case → shape response.
  No business logic left in it.

**What actually moves, concretely, in User service:**
- `router/auth_jwt.ts`'s password hashing + JWT issuance becomes a `RegisterUser` /
  `LoginUser` use case in `application/`, calling a `PasswordHasher` and `TokenService` port.
- `router/profile.ts`'s duplicate write bug gets fixed *as a side effect* of this refactor —
  there will be exactly one `UpdateProfile` use case with one write path.
- `dal/index.ts`'s orphaned `Discount` classes get deleted (dead code, unrelated to this domain).
- Mongoose schema becomes the Infrastructure-layer implementation of a `UserRepository` port;
  the Domain layer's `User` entity has no knowledge that Mongo exists.

**expense-service (built fresh, DDD from day one):**
```
domain/expense/
  expense.entity.ts       # invariants: amount > 0, splits sum to 100% of total, currency match
  split-strategy.ts        # EqualSplit, ExactAmountSplit, PercentageSplit — classic DDD strategy pattern
  expense.events.ts        # ExpenseCreated, ExpenseSettled
```
This is the one place where DDD earns its keep immediately — "how is this expense split
among members" is genuinely complex domain logic (equal / exact / percentage / shares),
exactly the kind of thing DDD's entity + value-object pattern is built for.

### Naming convention for bounded contexts

Each microservice **is** a DDD *bounded context*. Don't try to build one shared domain model
across all three — `User` in user-service (auth, credentials, session) is a different concept
than `User` referenced by `groups-service` (just a `userId` string + role). That's correct DDD:
each context has its own model of "user," scoped to what it needs.

---

## Part 3 — Async Messaging: Kafka, Mapped to AWS

### Why introduce a message queue at all

Today every cross-service interaction is synchronous HTTP (or none at all — services don't
talk to each other yet beyond the API Gateway's auth check). Once `expense-service` exists,
real cross-domain workflows appear:

- User creates an expense in a group → groups-service should know the group's "last activity" changed
- A user is removed from a group → expense-service needs to know so it can flag/reassign their unsettled expenses
- An expense is settled → could trigger a notification service (future) without expense-service knowing notification-service exists

Doing this over synchronous HTTP means expense-service must know about, call, and handle
failures for every downstream consumer — tight coupling, and a slow/down consumer blocks the
whole request. A message queue decouples producers from consumers: expense-service publishes
`ExpenseCreated`, and doesn't know or care who's listening.

### Local dev: Kafka. Production: Amazon MSK.

Chosen over SNS+SQS specifically so local Docker Compose and production behave identically —
same protocol, same client library (`kafkajs`), same mental model of topics/partitions/consumer
groups/offsets. No shim, no localstack translation layer.

```
Local (docker-compose.yml)              Production (AWS)
─────────────────────────               ─────────────────────────
Kafka (KRaft mode, no ZK)      ────►     Amazon MSK (Provisioned or Serverless)
  1 broker, 1 partition/topic              3 brokers min, Multi-AZ, 3 partitions/topic
                                           IAM auth (SASL/IAM) instead of PLAINTEXT
                                           Runs inside the same private VPC as ECS tasks
```

### Where MSK sits in the AWS architecture

Extends the diagram in `AWS_ARCHITECTURE.md`:

```
                          ┌────────────────┼────────────────┐
                          │                │                │
                   ALB-1 (internal)  ALB-2 (internal)  ALB-3 (internal)
                          │                │                │
                   user-service      group-service   expense-service
                   ECS tasks ×N      ECS tasks ×N    ECS tasks ×N
                          │                │                │
                     DocumentDB        RDS              RDS
                          │                │                │
                          └────────┬───────┴────────┬───────┘
                                   │ (produce/consume)
                              Amazon MSK
                         (private subnet, Multi-AZ,
                          3 brokers, IAM auth)
                                   │
                    ┌──────────────┼──────────────┐
                topic:group-events   topic:expense-events
```

- MSK brokers live in the **private subnets**, same security-group pattern as RDS/DocumentDB:
  a new `sg-msk` allowing port 9098 (IAM-auth) only from `sg-ecs-tasks`.
- Each service is both a producer (publishes its own domain events) and potentially a
  consumer (subscribes to events it cares about) — e.g. expense-service consumes
  `MemberRemoved` from `group-events`.
- Consumer group per service, so scaling expense-service tasks horizontally also scales
  Kafka consumption (partitions distribute across task instances).

### Topics and events, mapped to the domain entities that exist today

| Topic | Producer | Example events | Consumers (once built) |
|---|---|---|---|
| `group-events` | groups-service | `GroupCreated`, `MemberInvited`, `MemberJoined`, `MemberRemoved` | expense-service (reassign/flag expenses on member removal) |
| `expense-events` | expense-service | `ExpenseCreated`, `ExpenseSettled`, `ExpenseDeleted` | groups-service (update group activity timestamp), future notification-service |
| `user-events` | user-service | `UserRegistered`, `UserProfileUpdated` | groups-service (cache display name), expense-service |

Each event is a domain event defined in that service's `domain/*/[].events.ts` (Part 2) —
the event schema is part of the domain model, not an infrastructure afterthought.

### Roadmap addition (extends the table in AWS_ARCHITECTURE.md)

| Step | What we build | Why it matters |
|---|---|---|
| 15 | Kafka locally via docker-compose (KRaft, single broker) | Prove event flow works before paying for MSK |
| 16 | Domain events defined per service (`*.events.ts`) | Events are part of the domain model, designed alongside entities |
| 17 | Amazon MSK (Provisioned, 3 brokers, Multi-AZ) | Managed Kafka, IAM auth, in private subnet |
| 18 | Producer/consumer wiring in `infrastructure/messaging/` | Only the infra layer knows Kafka exists |
| 19 | CloudWatch consumer-lag alarms | At 1M users, a stuck consumer group silently backs up — alarm on lag, not just errors |

---

## Part 4 — Mongo → DocumentDB: Compatibility Gaps to Design Around

`AWS_ARCHITECTURE.md` already maps user-service's Mongo to DocumentDB. DocumentDB is
**MongoDB-compatible**, not MongoDB — it reimplements the wire protocol, it isn't a fork of
MongoDB's engine. That gap needs to shape how the User domain/infrastructure layer is written:

| Gap | Practical impact | Design guardrail |
|---|---|---|
| API version ceiling | DocumentDB tracks MongoDB 4.0/5.0/6.0 API compatibility (varies by DocDB engine version) — never the newest MongoDB features | Pin the local Kafka... err, local **Mongo** Docker image to the same major version DocumentDB supports. Don't develop against MongoDB 7/8-only features (e.g. certain newer aggregation operators). |
| Aggregation pipeline gaps | Some `$` operators / stages aren't implemented in DocumentDB | Keep aggregation pipelines used in `infrastructure/persistence/mongo-user.repository.ts` simple; if you use an advanced operator, verify it against DocumentDB's supported-operator list before relying on it. |
| Transactions | Multi-document ACID transactions work but with stricter constraints (retry semantics, no changing shard key mid-transaction) than modern MongoDB | Because the Domain layer defines the repository *interface* and Infrastructure implements it against DocumentDB specifically, transaction quirks stay isolated in one file instead of leaking into use cases. |
| TLS mandatory | DocumentDB requires TLS with the `global-bundle.pem` CA (already noted in AWS_ARCHITECTURE.md) | Local Mongo doesn't require TLS by default — the `infrastructure/config.ts` should make TLS conditional on environment, not hardcoded off. |
| No native full-text/Atlas Search | DocumentDB has its own (more limited) text index support, not Atlas Search | If profile/user search becomes a feature, evaluate DocumentDB's text index limits early, don't assume Atlas-grade search. |

**Why this belongs in the DDD doc and not just the AWS doc:** because the Repository pattern
(Part 2) is exactly the seam that absorbs this risk. As long as `UserRepository` stays an
interface and Mongoose/DocumentDB specifics stay inside one Infrastructure file, a
compatibility gap discovered later means editing one file — not chasing Mongo-specific calls
scattered through route handlers (which is where they live today).

---

## Part 5 — Frontend: Extending the Pattern to the MFEs

Lighter touch than backend DDD, but the same "separate what changes for different reasons"
principle applies to `app/store/groupSlice.ts` and `client-side-app/src/store/groupSlice.ts`:

- Introduce a thin **API client module** (e.g. `lib/api/groups.ts`) that wraps `fetch()` —
  Redux thunks call the API client, they don't call `fetch()` directly. This is the frontend
  equivalent of a Repository: Redux (application layer) shouldn't know if it's REST, GraphQL,
  or gRPC underneath.
- The near-duplicate slice between host and remote MFE is a packaging problem, not solved by
  DDD — that's a candidate for a shared package (e.g. `@divided-by-all/shared-store` or
  Module-Federation-shared library) so the API client and slice logic exist once.

---

## Summary: What Changes, In Order

1. **groups-service** (has the least distance to travel): extract `domain/group/*.entity.ts`
   invariants out of `GroupService`, split `GroupService` into per-action use cases, introduce
   `group.repository.ts` interface + Prisma implementation.
2. **User service** (has the most cleanup): introduce `domain/user/user.entity.ts`,
   `application/*.usecase.ts` for register/login/update-profile, `UserRepository` interface +
   Mongoose implementation, delete `dal/index.ts`'s dead `Discount` code, fix the duplicate-write
   bug in profile update as part of consolidating to one use case.
3. **expense-service**: build DDD-first from an empty directory — no migration cost, and it's
   the service where the domain logic (split strategies) most rewards this pattern.
4. **Kafka**: add `docker-compose` Kafka locally once at least two services have events worth
   publishing (after step 1–2 land) → then map to MSK in AWS per Part 3.
5. **Frontend**: extract shared API-client module, address slice duplication.

No code is being changed as part of this document — this is the target to refactor towards,
service by service, in the order above.
