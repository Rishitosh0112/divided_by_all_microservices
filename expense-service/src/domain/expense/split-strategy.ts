import { ExpenseSplit } from './expense-split.js';
import { Money } from './money.js';
import { DomainValidationError } from '../shared/domain-validation.error.js';

export type SplitType = 'EQUAL' | 'EXACT';

export interface SplitParticipant {
  userId: string;
  amountMinor?: number;
}

export interface SplitStrategy {
  /**
   * Calculates one share for every participant using this strategy's rule.
   * @param totalAmount Complete amount being divided.
   * @param participants Users to include; exact splits also provide their amount.
   * @returns One calculated ExpenseSplit for each participant.
   */
  calculate(totalAmount: Money, participants: SplitParticipant[]): ExpenseSplit[];
}

/**
 * Ensures split participants exist, have IDs, and are not duplicated.
 * @param participants Users supplied for a split calculation.
 * @returns Nothing; throws DomainValidationError when the participant list is invalid.
 */
function validateParticipants(participants: SplitParticipant[]): void {
  if (participants.length === 0) {
    throw new DomainValidationError('at least one participant is required');
  }

  const userIds = participants.map(({ userId }) => userId);
  if (userIds.some((userId) => !userId.trim())) {
    throw new DomainValidationError('participant userId is required');
  }
  if (new Set(userIds).size !== userIds.length) {
    throw new DomainValidationError('participants must be unique');
  }
}

export class EqualSplitStrategy implements SplitStrategy {
  /**
   * Divides the total equally and distributes leftover minor units in participant order.
   * @param totalAmount Complete amount to divide equally.
   * @param participants Users receiving equal shares.
   * @returns Equal ExpenseSplit values whose total exactly matches totalAmount.
   */
  calculate(totalAmount: Money, participants: SplitParticipant[]): ExpenseSplit[] {
    validateParticipants(participants);

    const amountPerParticipant = Math.floor(
      totalAmount.amountMinor / participants.length,
    );
    let remainder = totalAmount.amountMinor % participants.length;

    return participants.map(({ userId }) => {
      const amountMinor = amountPerParticipant + (remainder > 0 ? 1 : 0);
      remainder -= 1;
      return new ExpenseSplit(userId, new Money(amountMinor, totalAmount.currency));
    });
  }
}

export class ExactSplitStrategy implements SplitStrategy {
  /**
   * Creates supplied shares only when their total exactly equals the expense total.
   * @param totalAmount Complete amount that all supplied shares must total.
   * @param participants Users and their exact minor-unit amounts.
   * @returns ExpenseSplit values using the supplied exact amounts.
   */
  calculate(totalAmount: Money, participants: SplitParticipant[]): ExpenseSplit[] {
    validateParticipants(participants);

    const splits = participants.map(({ userId, amountMinor }) => {
      if (!Number.isSafeInteger(amountMinor) || amountMinor === undefined || amountMinor < 0) {
        throw new DomainValidationError('exact split amounts must be non-negative safe integers');
      }
      return new ExpenseSplit(userId, new Money(amountMinor, totalAmount.currency));
    });

    const splitTotal = splits.reduce(
      (sum, split) => sum + split.owedAmount.amountMinor,
      0,
    );
    if (splitTotal !== totalAmount.amountMinor) {
      throw new DomainValidationError('exact split amounts must equal the total amount');
    }

    return splits;
  }
}

/**
 * Selects the domain strategy that knows how to calculate the requested split type.
 * @param splitType EQUAL or EXACT.
 * @returns The strategy that calculates that split type.
 */
export function splitStrategyFor(splitType: SplitType): SplitStrategy {
  return splitType === 'EQUAL'
    ? new EqualSplitStrategy()
    : new ExactSplitStrategy();
}
