import { Balance } from '../../domain/balance/balance.js';
import { Expense } from '../../domain/expense/expense.js';

export const EXPENSE_LEDGER_REPOSITORY = Symbol('EXPENSE_LEDGER_REPOSITORY');

/**
 * Persists the complete result of creating an expense as one database transaction.
 */
export interface ExpenseLedgerRepository {
  /**
   * Persists the complete result of creating an expense in one transaction.
   * @param expense The new Expense and all of its splits.
   * @param balanceChanges Debt increases caused by the expense.
   * @returns A promise that resolves after the transaction commits.
   */
  saveCreatedExpense(expense: Expense, balanceChanges: Balance[]): Promise<void>;
}
