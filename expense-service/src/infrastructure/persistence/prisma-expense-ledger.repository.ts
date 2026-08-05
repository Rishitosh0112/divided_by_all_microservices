import { Injectable } from '@nestjs/common';
import { Balance } from '../../domain/balance/balance.js';
import { Expense } from '../../domain/expense/expense.js';
import { ExpenseLedgerRepository } from '../../application/ports/expense-ledger.repository.js';
import { PrismaService } from './prisma.service.js';

@Injectable()
export class PrismaExpenseLedgerRepository implements ExpenseLedgerRepository {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Saves an expense, its splits, and all balance increases in one PostgreSQL transaction.
   * @param expense The Expense to insert with its child splits.
   * @param balanceChanges Debt increases to insert or add to existing balances.
   * @returns A promise that resolves only after the transaction commits.
   */
  async saveCreatedExpense(expense: Expense, balanceChanges: Balance[]): Promise<void> {
    await this.prisma.$transaction(async (transaction) => {
      await transaction.expense.create({
        data: {
          id: expense.id,
          groupId: expense.groupId,
          description: expense.description,
          paidByUserId: expense.paidByUserId,
          amountMinor: expense.totalAmount.amountMinor,
          currency: expense.totalAmount.currency,
          splitType: expense.splitType,
          createdAt: expense.createdAt,
          splits: {
            create: expense.splits.map((split) => ({
              userId: split.userId,
              amountMinor: split.owedAmount.amountMinor,
            })),
          },
        },
      });

      for (const balance of balanceChanges) {
        await transaction.balance.upsert({
          where: {
            groupId_debtorUserId_creditorUserId_currency: {
              groupId: balance.groupId,
              debtorUserId: balance.debtorUserId,
              creditorUserId: balance.creditorUserId,
              currency: balance.amount.currency,
            },
          },
          create: {
            id: balance.id,
            groupId: balance.groupId,
            debtorUserId: balance.debtorUserId,
            creditorUserId: balance.creditorUserId,
            amountMinor: balance.amount.amountMinor,
            currency: balance.amount.currency,
          },
          update: {
            amountMinor: { increment: balance.amount.amountMinor },
          },
        });
      }
    });
  }
}
