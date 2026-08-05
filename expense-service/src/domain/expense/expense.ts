import { randomUUID } from 'node:crypto';
import { Money } from './money.js';
import { ExpenseSplit } from './expense-split.js';
import { Balance } from '../balance/balance.js';
import { SplitType } from './split-strategy.js';
import { DomainValidationError } from '../shared/domain-validation.error.js';

export interface CreateExpenseInput {
  groupId: string;
  description: string;
  paidByUserId: string;
  totalAmount: Money;
  splitType: SplitType;
  splits: ExpenseSplit[];
}

export class Expense {
  private constructor(
    public readonly id: string,
    public readonly groupId: string,
    public readonly description: string,
    public readonly paidByUserId: string,
    public readonly totalAmount: Money,
    public readonly splitType: SplitType,
    public readonly splits: ExpenseSplit[],
    public readonly createdAt: Date,
  ) {}

  /**
   * Validates domain invariants and creates one new expense aggregate.
   * @param input Expense details and its already-calculated participant splits.
   * @returns A new Expense with an ID and creation time.
   */
  static create(input: CreateExpenseInput): Expense {
    if (!input.groupId.trim()) {
      throw new DomainValidationError('groupId is required');
    }
    if (!input.paidByUserId.trim()) {
      throw new DomainValidationError('paidByUserId is required');
    }
    if (!input.description.trim()) {
      throw new DomainValidationError('description is required');
    }
    if (input.splits.length === 0) {
      throw new DomainValidationError('an expense requires at least one split');
    }
    if (!input.splits.some((split) => split.userId === input.paidByUserId)) {
      throw new DomainValidationError('payer must be a participant');
    }

    const splitTotal = input.splits.reduce(
      (sum, split) => sum + split.owedAmount.amountMinor,
      0,
    );
    if (splitTotal !== input.totalAmount.amountMinor) {
      throw new DomainValidationError('split amounts must equal the total amount');
    }
    if (input.splits.some((split) => split.owedAmount.currency !== input.totalAmount.currency)) {
      throw new DomainValidationError('all split currencies must match the total amount currency');
    }

    return new Expense(
      randomUUID(),
      input.groupId,
      input.description,
      input.paidByUserId,
      input.totalAmount,
      input.splitType,
      input.splits,
      new Date(),
    );
  }

  /**
   * Converts non-payer splits into debt changes that increase group balances.
   * @returns One Balance change per participant who owes the payer money.
   */
  balanceChanges(): Balance[] {
    return this.splits
      .filter((split) => split.userId !== this.paidByUserId)
      .filter((split) => split.owedAmount.amountMinor > 0)
      .map((split) =>
        Balance.createDebt({
          groupId: this.groupId,
          debtorUserId: split.userId,
          creditorUserId: this.paidByUserId,
          amount: split.owedAmount,
        }),
      );
  }
}
