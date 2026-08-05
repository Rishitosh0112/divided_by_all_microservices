import { Module } from '@nestjs/common';
import { CreateExpenseUseCase } from './application/expense/create-expense.use-case.js';
import { EXPENSE_LEDGER_REPOSITORY } from './application/ports/expense-ledger.repository.js';
import { PrismaExpenseLedgerRepository } from './infrastructure/persistence/prisma-expense-ledger.repository.js';
import { PrismaService } from './infrastructure/persistence/prisma.service.js';
import { ExpenseController } from './interface/http/expense.controller.js';

@Module({
  controllers: [ExpenseController],
  providers: [
    CreateExpenseUseCase,
    PrismaService,
    PrismaExpenseLedgerRepository,
    {
      provide: EXPENSE_LEDGER_REPOSITORY,
      useExisting: PrismaExpenseLedgerRepository,
    },
  ],
})
export class AppModule {}
