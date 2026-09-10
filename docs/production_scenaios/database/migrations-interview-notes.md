# Database Migrations — Prisma + PostgreSQL + Node.js

## 1. Core Mental Model

A **database migration** is a version-controlled, repeatable change that moves the database schema/data from one known state to another.

Changing `schema.prisma` does **not** itself change PostgreSQL.

```text
Node.js Application
        |
        | Prisma Client
        v
Prisma schema / tooling
        |
        | Prisma Migrate
        v
PostgreSQL
(actual tables, columns, indexes, constraints)
```

- **Node.js + Prisma Client**: runtime database access.
- **schema.prisma**: describes the model expected by the application.
- **Prisma Migrate**: manages migration files/workflow.
- **PostgreSQL**: executes the actual SQL changes.

## 2. Why Migrations?

Without controlled migrations, environments can have different schemas. This is **schema drift**.

Migration files keep database evolution in source control and allow Dev, QA, Staging, and Production to apply the same changes.

## 3. Important Prisma Commands

### Development

```bash
npx prisma migrate dev --name add_expense_currency
```

Creates/applies a migration during development.

### Production

```bash
npx prisma migrate deploy
```

Applies already-created pending migrations.

### Generate Client

```bash
npx prisma generate
```

Generates Prisma Client from `schema.prisma`.

**It does not migrate PostgreSQL.**

## 4. Rolling Deployment Example

Suppose Expense V2 introduces a mandatory `currency` field.

Original table:

```text
expenses
--------
id
amount
```

### Step 1 — Expand

Add the column as nullable:

```sql
ALTER TABLE expenses
ADD COLUMN currency TEXT NULL;
```

This allows both old and new Node.js versions to work.

```text
                 PostgreSQL
              currency nullable
                    ^
                    |
         +----------+----------+
         |                     |
     Node V1                 Node V2
     old code                new code
         |                     |
   currency=NULL          currency='INR'
```

During rolling deployment:

```text
id   amount   currency
----------------------
1    500      NULL   <- historical row
2    300      NULL   <- request handled by old Node instance
3    700      INR    <- request handled by new Node instance
4    900      INR    <- request handled by new Node instance
```

This temporary state is expected.

### Step 2 — Complete Rolling Deployment

Wait until old Node.js instances are gone.

```text
Old Node V1 instances = 0

Node V2
Node V2
Node V2
Node V2
```

Now all future writes should populate `currency`.

### Step 3 — Backfill

If `currency` is mandatory business data, update old NULL values:

```sql
UPDATE expenses
SET currency = 'INR'
WHERE currency IS NULL;
```

If the new field is genuinely optional, NULL values may remain NULL.

### Step 4 — Enforce the Invariant

After all application instances write `currency` and existing rows have been backfilled:

```sql
ALTER TABLE expenses
ALTER COLUMN currency SET NOT NULL;
```

## 5. Production Pattern

```text
EXPAND
Add backward-compatible DB structure
        |
        v
ROLLING DEPLOY
Old + new Node.js versions coexist
        |
        v
NEW VERSION ACTIVE
All new writes use new structure
        |
        v
BACKFILL
Fix historical/temporary old data
        |
        v
CONTRACT / ENFORCE
Add constraints or remove old structure
```

This is commonly called **Expand → Migrate/Backfill → Contract**.

## 6. Important Production Principle

Database migration strategy must consider application deployment strategy.

During rolling deployments, old and new Node.js instances can coexist. Therefore, destructive changes such as immediately dropping or renaming a column can break old instances.

Prisma cannot automatically solve this compatibility problem. It requires application and migration design.

## 7. Migrations Can Include

- Tables
- Columns
- Primary keys
- Foreign keys
- UNIQUE constraints
- CHECK constraints
- NOT NULL constraints
- Indexes
- Data backfills
- Data transformations
- Renamed/deprecated structures

## Interview Answer — 30 Seconds

> A database migration is a version-controlled way of evolving database schema or data. With Node.js, Prisma and PostgreSQL, `schema.prisma` represents the application model, Prisma Migrate manages migration files, and PostgreSQL executes the actual SQL changes. In production, migrations should be backward compatible because old and new Node.js instances can coexist during rolling deployments. For example, when introducing a mandatory currency field, I would first add it as nullable, deploy the new application version, backfill NULL values after old instances are gone, and finally enforce NOT NULL. This follows the expand-migrate-contract pattern.

# TODO — Next Production Topic

## What if the table has 500 million rows?

Running one giant operation such as:

```sql
UPDATE expenses
SET currency = 'INR'
WHERE currency IS NULL;
```

against **500 million rows** can be a very bad idea in PostgreSQL.

Learn next:

- [ ] Why a giant UPDATE is dangerous
- [ ] Batched backfills
- [ ] PostgreSQL locks during migrations
- [ ] MVCC during large updates
- [ ] WAL generation and disk impact
- [ ] Replication lag
- [ ] Transaction size and long-running transactions
- [ ] Index creation on large production tables
- [ ] Migration failure and recovery
- [ ] Safe production migration strategies
- [ ] How Prisma migrations should handle these cases
- [ ] How this affects Node.js services during deployment
