# Divided by All — Kafka Event Design with Amazon MSK

> This document consolidates the Kafka event design, Transactional Outbox Pattern,
> Polling Publisher, and future Debezium-based implementation.

---

# 1. Why Kafka?

The Ledger Service is responsible only for completing the financial transaction.

After a successful transaction, multiple independent services may react:

- Notification Service
- Activity Feed Service
- Analytics Service

Instead of calling each service synchronously, Ledger publishes a business event to Amazon MSK.

```
Ledger Service
      |
      v
Amazon MSK
      |
      ├── Notification Service
      ├── Activity Feed Service
      └── Analytics Service
```

---

# 2. Platform

## Local

Kafka in Docker

## AWS

Amazon MSK

---

# 3. Topic

```
ledger.events
```

---

# 4. Events

- EXPENSE_CREATED
- EXPENSE_UPDATED
- EXPENSE_DELETED
- SETTLEMENT_CREATED

---

# 5. Event Flow

POST /expenses

↓

PostgreSQL Transaction

- Insert Expense
- Insert ExpenseSplit
- Update Balance
- Insert Outbox Event

↓

COMMIT

↓

Outbox Publisher

↓

Amazon MSK

↓

Notification / Activity Feed / Analytics

---

# 6. Database Changes

## EXPENSE_CREATED

| Table | Operation |
|------|-----------|
| expenses | INSERT |
| expense_splits | INSERT |
| balances | INSERT / UPDATE |
| outbox_events | INSERT |

## EXPENSE_UPDATED

| Table | Operation |
|------|-----------|
| expenses | UPDATE |
| expense_splits | Replace |
| balances | UPDATE |
| outbox_events | INSERT |

## EXPENSE_DELETED

| Table | Operation |
|------|-----------|
| expenses | Soft Delete |
| balances | Reverse |
| outbox_events | INSERT |

## SETTLEMENT_CREATED

| Table | Operation |
|------|-----------|
| settlements | INSERT |
| balances | UPDATE |
| outbox_events | INSERT |

---

# 7. Transactional Outbox Pattern

The Outbox is simply another PostgreSQL table.

```
BEGIN

Insert Expense
Insert ExpenseSplit
Update Balance
Insert Outbox Event

COMMIT
```

Because all four writes belong to the same PostgreSQL transaction, either all succeed or none succeed.

Example Outbox row:

| event_id | event_type | aggregate_id | status |
|----------|------------|--------------|--------|
| event-101 | EXPENSE_CREATED | exp-101 | PENDING |

The Outbox row is **not** the Kafka message.

It is a durable reminder that the event still needs to be published.

---

# 8. Outbox Publisher (Phase 1)

A separate Node.js worker continuously polls the Outbox.

Every 1–2 seconds:

1. Read PENDING rows.
2. Publish to Amazon MSK.
3. Mark rows as PUBLISHED.

Example query:

```sql
SELECT *
FROM outbox_events
WHERE status='PENDING'
ORDER BY created_at
LIMIT 100
FOR UPDATE SKIP LOCKED;
```

Recommended partial index:

```sql
CREATE INDEX idx_outbox_pending
ON outbox_events(created_at)
WHERE status='PENDING';
```

Best Practices

- Batch reads
- Partial index
- Adaptive polling
- Archive old PUBLISHED rows

---

# 9. Is Polling Expensive?

Generally no.

Reasons:

- Indexed lookup
- Only PENDING rows
- Batch processing
- Tiny query
- Adjustable polling interval

Suitable for small and medium systems.

---

# 10. Debezium (Phase 2)

Instead of polling, Debezium reads PostgreSQL's Write-Ahead Log (WAL).

```
PostgreSQL
      |
      v
Write Ahead Log (WAL)
      |
      v
Debezium
      |
      v
Amazon MSK
```

Whenever a new Outbox row is committed, Debezium immediately detects it and publishes the event.

No polling required.

---

# 11. Polling vs Debezium

| Polling Publisher | Debezium |
|-------------------|----------|
| Queries PostgreSQL | Reads WAL |
| Polling | Event-driven |
| Easy | More infrastructure |
| Good for medium systems | Better for large systems |
| Custom worker | CDC platform |

---

# 12. Consumer Groups

Each downstream service owns its own consumer group.

- notification-service
- analytics-service
- activity-feed-service

Every service receives every event independently.

---

# 13. Kafka Message Key

Use:

```
groupId
```

This preserves ordering for all events belonging to the same group.

---

# 14. Idempotency

Kafka can deliver duplicate events.

Each consumer should store processed eventIds.

```
Receive Event

↓

Already Processed?

Yes → Ignore

No → Process → Save eventId → Commit Offset
```

---

# 15. Final Decision

## Phase 1

```
Ledger

↓

PostgreSQL

↓

Outbox Table

↓

Node.js Polling Publisher

↓

Amazon MSK
```

## Phase 2

Replace only:

```
Node.js Polling Publisher
```

with

```
Debezium + Amazon MSK Connect
```

The Ledger Service and Outbox table remain unchanged.
