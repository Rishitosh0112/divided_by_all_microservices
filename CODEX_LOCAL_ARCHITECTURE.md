# Divided By All — Local Development Architecture

This document describes the developer-machine architecture for the Splitwise-style app. It
includes the current **User** and **Groups** services and the target **Expense**,
**Settlement**, and **Notification** services.

## Service ownership

Each service owns its data. No service may read or write another service's database.

| Service | Status | Responsibility | Port |
|---|---|---|---:|
| API gateway | Current | Local routing and temporary auth boundary | 8080 |
| User | Current | Login/signup, current JWT flow, user profiles | 8000 |
| Groups | Current | Groups, membership, invitations | 4002 |
| Expense | Target | Expenses, splits, participant obligations | 4003 |
| Settlement | Target | Group balance projection and recorded payments | 4004 |
| Notification | Target | In-app inbox and delivery attempts | 4005 |

## Current local architecture

```text
Browser / SSR microfrontend
        |
        | HTTP + token cookie
        v
Nginx API gateway :8080
  | /auth, /profiles                    | /groups
  v                                     v
User service :8000                  Groups service :4002
  | MongoDB through MONGO_URL           | PostgreSQL :5434 via Prisma
  |
  +-- /auth/validate returns X-User-Id to Nginx
```

### Current User service

- Express/Mongoose service on port `8000`.
- Provides signup, login, logout, token validation, profile update, lookup, and listing routes.
- Login writes an HTTP-only JWT cookie containing `userId`.
- It must use a private `MONGO_URL` from `.env`; no credentials belong in source code.

### Current Groups service

- Express/Prisma/PostgreSQL service on port `4002`.
- Owns `Group`, `GroupMember`, and `GroupInvitation` records.
- Provides create, list, read, update, soft-delete, invite, and invitation-response endpoints.
- It currently receives `X-User-Id` from Nginx. New services will use shared claims middleware
  rather than accepting an arbitrary user-ID header.

## Target local architecture

```text
                                      +---------------------------+
                                      | LocalStack                |
                                      | EventBridge + SQS + DLQs  |
                                      | DynamoDB (optional)       |
                                      +-------------+-------------+
                                                    ^
                                                    | outbox-published events
Browser --> Nginx :8080 --> User :8000 ------------+
                  |          Groups :4002 ----------+--> group events
                  |          Expense :4003 ---------+--> expense events
                  |          Settlement :4004 ------+--> settlement events
                  |          Notification :4005 <---+    SQS consumers
                  |
                  +--> Mailpit :8025 (email preview)

User --------> local MongoDB
Groups ------> group PostgreSQL database
Expense -----> expense PostgreSQL database
Settlement --> settlement PostgreSQL database
Notification -> DynamoDB Local (or PostgreSQL during first iteration)
```

## Local cloud-service equivalents

| AWS production service | Local equivalent |
|---|---|
| API Gateway + Cognito | Nginx + transitional local JWT verification |
| ECS Fargate | `npm run dev` or Compose service |
| RDS PostgreSQL | PostgreSQL containers/databases |
| EventBridge + SQS | LocalStack EventBridge/SQS |
| DynamoDB | DynamoDB Local/LocalStack |
| SES | Mailpit or MailHog |
| Secrets Manager | Gitignored `.env` files |

## Event flow and reliability

Every write service follows a transactional outbox pattern:

1. Commit its domain change and an `outbox_events` row in one database transaction.
2. An outbox publisher forwards the event to local EventBridge.
3. Each consumer receives a separate SQS message and records processed event IDs.
4. Failed messages retry and ultimately move to a DLQ; processing is idempotent.

| Event | Producer | Consumers |
|---|---|---|
| `group.member.joined.v1`, `group.member.removed.v1` | Groups | Expense, Notification |
| `expense.created.v1`, `expense.updated.v1`, `expense.deleted.v1` | Expense | Settlement, Notification |
| `settlement.recorded.v1` | Settlement | Expense, Notification |

All events include `id`, `type`, `source`, `occurredAt`, `correlationId`, and `data`.

## Expense and settlement example

```text
1. Alice creates an expense in a group.
2. Expense validates the split and commits expense + obligations + outbox event.
3. Settlement consumes expense.created and updates its group-balance projection.
4. Notification consumes the event and adds inbox/email work for affected members.
5. Alice receives the creation response without waiting for steps 3–4.
```

Expense stores the financial facts. Settlement owns computed balances and confirmed payments;
it is not an Expense-service side effect.

## Local run model

Create one root `docker-compose.dev.yml` for infrastructure only:

- MongoDB;
- PostgreSQL for Groups, Expense, and Settlement;
- LocalStack (EventBridge, SQS, DynamoDB);
- Mailpit; and
- optional Nginx gateway.

Run application services in native watch mode:

```bash
cd User && npm run dev
cd groups-service && npm run dev
cd expense-service && npm run dev
cd settlement-service && npm run dev
cd notification-service && npm run dev
```

Each service needs a committed `.env.example` plus a private `.env` ignored by Git.
