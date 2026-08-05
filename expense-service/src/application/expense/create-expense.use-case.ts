import { Inject, Injectable } from '@nestjs/common';
import { Expense } from '../../domain/expense/expense.js';
import {
  SplitParticipant,
  SplitType,
  splitStrategyFor,
} from '../../domain/expense/split-strategy.js';
import { Money } from '../../domain/expense/money.js';
import { DomainValidationError } from '../../domain/shared/domain-validation.error.js';
import {
  EXPENSE_LEDGER_REPOSITORY,
} from '../ports/expense-ledger.repository.js';
import type { ExpenseLedgerRepository } from '../ports/expense-ledger.repository.js';

export interface CreateExpenseCommand {
  groupId: string;
  description: string;
  paidByUserId: string;
  amountMinor: number;
  currency: string;
  splitType: SplitType;
  participants: SplitParticipant[];
}

@Injectable()
export class CreateExpenseUseCase {
  constructor(
    @Inject(EXPENSE_LEDGER_REPOSITORY)
    private readonly repository: ExpenseLedgerRepository,
  ) {}

  /**
   * Coordinates split calculation, expense creation, balance changes, and atomic persistence.
   * @param command Validated HTTP input for the new expense.
   * @returns The saved domain Expense.
   */
  async execute(command: CreateExpenseCommand): Promise<Expense> {
    const totalAmount = new Money(command.amountMinor, command.currency);
    if (totalAmount.amountMinor === 0) {
      throw new DomainValidationError('expense total amount must be greater than zero');
    }

    const splits = splitStrategyFor(command.splitType).calculate(
      totalAmount,
      command.participants,
    );
    const expense = Expense.create({
      groupId: command.groupId,
      description: command.description,
      paidByUserId: command.paidByUserId,
      totalAmount,
      splitType: command.splitType,
      splits,
    });

    await this.repository.saveCreatedExpense(expense, expense.balanceChanges());
    return expense;
  }
}
