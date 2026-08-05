import { Expense } from './expense.js';
import { ExpenseSplit } from './expense-split.js';
import { Money } from './money.js';

describe('Expense', () => {
  it('creates an expense with an equal split', () => {
    const expense = Expense.create({
      groupId: 'group-1',
      paidByUserId: 'user-a',
      description: 'Dinner',
      totalAmount: new Money(10_000, 'INR'),
      splitType: 'EQUAL',
      splits: [
        new ExpenseSplit('user-a', new Money(5_000, 'INR')),
        new ExpenseSplit('user-b', new Money(5_000, 'INR')),
      ],
    });

    expect(expense.splits).toEqual([
      new ExpenseSplit('user-a', new Money(5_000, 'INR')),
      new ExpenseSplit('user-b', new Money(5_000, 'INR')),
    ]);
  });
});
