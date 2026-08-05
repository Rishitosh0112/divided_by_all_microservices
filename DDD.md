# Domain-Driven Design (DDD)

## Purpose

DDD helps us structure code around business rules instead of frameworks, databases, or HTTP routes.

For this project, the important business concepts are:

- Expense
- Split
- Money
- Balance
- Settlement
- Group member

## Bounded Contexts

Each microservice owns its own business area.

| Service | Owns |
|---|---|
| User Service | Authentication and user profiles |
| Groups Service | Groups, members, roles |
| Expense Service | Expenses and split calculations |
| Settlement Service | Balances, debts, repayments |

A service must not directly access another service’s database.

## Folder Structure

Each NestJS service will follow this structure:

```text
src/
├── domain/
├── application/
├── infrastructure/
└── interface/
```

## Domain Layer

`domain/` contains pure business rules.

```text
domain/
  expense/
    expense.entity.ts
    money.value-object.ts
    split.strategy.ts
    expense.repository.ts
    expense-created.event.ts
```

Examples:

- `Money` validates money amounts and currency.
- `Expense` validates an expense.
- `SplitStrategy` calculates how an expense is divided.
- `ExpenseRepository` defines storage needs as an interface.
- `ExpenseCreated` represents a completed business event.

The domain layer must not import NestJS, Prisma, Kafka, Express, or database code.

## Application Layer

`application/` contains use cases: one class per business action.

```text
application/
  expense/
    create-expense.use-case.ts
    get-expense.use-case.ts
```

Example responsibility of `CreateExpenseUseCase`:

1. Receive input.
2. Create a valid `Expense`.
3. Save it using a repository.
4. Publish its event.
5. Return the result.

A use case coordinates work. It should not contain HTTP or database code.

## Infrastructure Layer

`infrastructure/` contains technical details.

```text
infrastructure/
  persistence/
    prisma-expense.repository.ts
  messaging/
    kafka-event.publisher.ts
```

Examples:

- Prisma database repository
- Kafka event publisher
- Environment configuration

Infrastructure implements interfaces defined by the domain or application layer.

## Interface Layer

`interface/` handles incoming communication.

```text
interface/
  http/
    expense.controller.ts
    dto/
      create-expense.dto.ts
  messaging/
    group-events.consumer.ts
```

Examples:

- NestJS controllers
- Request DTOs
- Kafka consumers

Controllers should only receive requests, call a use case, and return a response.

## Dependency Rule

Dependencies point inward:

```text
Interface → Application → Domain
Infrastructure → Application / Domain
```

The domain layer never depends on infrastructure.

## Example Expense Flow

```text
POST /expenses
  ↓
ExpenseController          interface/
  ↓
CreateExpenseUseCase       application/
  ↓
Expense.create()           domain/
  ↓
ExpenseRepository.save()   domain interface
  ↓
PrismaExpenseRepository    infrastructure/
  ↓
KafkaEventPublisher        infrastructure/
```

## First Domain Concept

The first concept to build is `Money`.

Rules:

- Store money using integer minor units.
- INR 10.50 is stored as 1050 paise.
- Currency is required.
- Negative values are rejected where not allowed.
- Do not use JavaScript floating-point values for money.
