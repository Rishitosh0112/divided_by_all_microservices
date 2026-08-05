import { randomUUID } from 'node:crypto';
import { Money } from '../expense/money.js';
import { DomainValidationError } from '../shared/domain-validation.error.js';

export interface CreateBalanceProps {
  groupId: string;
  debtorUserId: string;
  creditorUserId: string;
  amount: Money;
}

export class Balance {
  private constructor(
    public readonly id: string,
    public readonly groupId: string,
    public readonly debtorUserId: string,
    public readonly creditorUserId: string,
    public readonly amount: Money,
  ) {}

  /**
   * Creates a new debt change from one user to another within a group.
   * @param input Group, debtor, creditor, and positive debt amount.
   * @returns A new Balance representing that debt increase.
   */
  static createDebt(input: CreateBalanceProps): Balance {
    if (input.debtorUserId === input.creditorUserId) {
      throw new DomainValidationError('a user cannot owe money to themselves');
    }
    if (input.amount.amountMinor === 0) {
      throw new DomainValidationError('a balance amount must be greater than zero');
    }
    return new Balance(
      randomUUID(),
      input.groupId,
      input.debtorUserId,
      input.creditorUserId,
      input.amount,
    );
  }
}
