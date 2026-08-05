# Divided by All - Ledger Service (Current Design Notes)

## Core Tables

### 1. expenses

  Column            Description
  ----------------- ------------------------------------
  expense_id        Unique expense id
  group_id          Group in which expense was created
  description       Expense description
  paid_by_user_id   Single payer
  total_amount      Total expense amount
  split_type        EQUAL / EXACT
  currency          Currency

Example

  ----------------------------------------------------------------------------------------------
  expense_id   group_id   description   paid_by_user_id     total_amount split_type   currency
  ------------ ---------- ------------- ----------------- -------------- ------------ ----------
  exp-101      group-1    Dinner        rishitosh                   3000 EQUAL        INR

  ----------------------------------------------------------------------------------------------

------------------------------------------------------------------------

### 2. expense_splits

One row per participant.

  expense_split_id   expense_id   user_id       owed_amount
  ------------------ ------------ ----------- -------------
  split-1            exp-101      rishitosh            1000
  split-2            exp-101      amit                 1000
  split-3            exp-101      neha                 1000

Meaning: - Rishitosh's share = ₹1000 - Amit's share = ₹1000 - Neha's
share = ₹1000

------------------------------------------------------------------------

### 3. balances

Current outstanding balance between two users inside a group.

  ---------------------------------------------------------------------------------------
  balance_id   group_id    debtor_user_id   creditor_user_id           amount currency
  ------------ ----------- ---------------- ------------------ -------------- -----------
  bal-1        group-1     amit             rishitosh                    1000 INR

  bal-2        group-1     neha             rishitosh                    1000 INR
  ---------------------------------------------------------------------------------------

Balance is a **derived read model**.

------------------------------------------------------------------------

### 4. settlements

Each payment creates a new row.

  -------------------------------------------------------------------------------------------
  settlement_id   group_id    paid_by_user_id   paid_to_user_id           amount created_at
  --------------- ----------- ----------------- ----------------- -------------- ------------
  set-101         group-1     amit              rishitosh                    400 2026-08-01
                                                                                 10:30

  set-102         group-1     amit              rishitosh                    300 2026-08-01
                                                                                 11:15
  -------------------------------------------------------------------------------------------

Settlements are immutable history.

------------------------------------------------------------------------

# Relationships

expenses \| \| 1:N v expense_splits

Expense + ExpenseSplits create/update Balance.

Settlement reduces Balance.

------------------------------------------------------------------------

# APIs and Database Updates

## POST /expenses

Transaction

1.  Insert into `expenses`
2.  Insert rows into `expense_splits`
3.  Update/Insert corresponding `balances`
4.  Commit

Example:

Expense: - Rishitosh paid ₹3000

Splits: - Rishitosh ₹1000 - Amit ₹1000 - Neha ₹1000

Balance after transaction:

-   Amit -\> Rishitosh ₹1000
-   Neha -\> Rishitosh ₹1000

------------------------------------------------------------------------

## PUT /expenses/{expenseId}

Transaction

1.  Read existing expense
2.  Reverse previous balance impact
3.  Update expense
4.  Replace expense_splits
5.  Recalculate balances
6.  Commit

------------------------------------------------------------------------

## DELETE /expenses/{expenseId}

Transaction

1.  Read expense
2.  Reverse balance impact
3.  Soft delete expense
4.  Commit

------------------------------------------------------------------------

## POST /v1/settlements

Transaction

1.  Insert into `settlements`
2.  Reduce corresponding balance
3.  Commit

Example:

Before

Amit -\> Rishitosh ₹1000

Settlement:

Amit pays ₹400

After

Amit -\> Rishitosh ₹600

------------------------------------------------------------------------

## GET /v1/balances

Read from `balances`.

No calculation from expenses is performed during login.

------------------------------------------------------------------------

## GET /v1/groups/{groupId}/balances

Read group-specific balances from `balances`.

------------------------------------------------------------------------

## GET /v1/balances/users/{otherUserId}

Read pairwise balance between logged-in user and another user.

------------------------------------------------------------------------

# Current Simplifications

-   Exactly one payer per expense.
-   Split types:
    -   Equal
    -   Exact Amount
-   Multiple payers are out of scope.
-   Balance is maintained transactionally inside the Ledger Service.
-   Expense and Settlement are the source of truth.
-   Balance is maintained for fast reads.
