import { Body, Controller, Post } from '@nestjs/common';
import { CreateExpenseUseCase } from '../../application/expense/create-expense.use-case.js';
import { CreateExpenseDto } from './dto/create-expense.dto.js';

@Controller('expenses')
export class ExpenseController {
  constructor(private readonly createExpense: CreateExpenseUseCase) {}

  /**
   * Receives a create-expense HTTP request and delegates it to the application use case.
   * @param request Validated request body containing the new expense details.
   * @returns The newly saved Expense response.
   */
  @Post()
  create(@Body() request: CreateExpenseDto) {
    return this.createExpense.execute(request);
  }
}
