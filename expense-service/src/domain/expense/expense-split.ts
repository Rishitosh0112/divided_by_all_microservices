import { Money } from './money.js';
import { DomainValidationError } from '../shared/domain-validation.error.js';

export class ExpenseSplit {
  /**
   * Creates one participant's owed share within a parent expense.
   * @param userId ID of the participant who owes this share.
   * @param owedAmount Money amount owed by the participant.
   */
  constructor(
    public readonly userId: string,
    public readonly owedAmount: Money,
  ) {
    if (!userId.trim()) {
      throw new DomainValidationError('split userId is required');
    }
  }
}
