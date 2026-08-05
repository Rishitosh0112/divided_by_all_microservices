import { DomainValidationError } from '../shared/domain-validation.error.js';

export class Money {
  /**
   * Creates an immutable money value after validating its minor-unit amount and currency.
   * @param amountMinor Whole-number currency units, such as paise for INR.
   * @param currency Three-letter uppercase ISO currency code, such as INR.
   */
  constructor(
    public readonly amountMinor: number,
    public readonly currency: string,
  ) {
    if (!Number.isSafeInteger(amountMinor)) {
      throw new DomainValidationError('amountMinor must be a safe integer');
    }
    if (amountMinor < 0) {
      throw new DomainValidationError('amountMinor cannot be negative');
    }

    if (!currency) {
      throw new DomainValidationError('currency is required');
    }
    if (!/^[A-Z]{3}$/.test(currency)) {
      throw new DomainValidationError('currency must be a three-letter uppercase ISO code');
    }
  }
}
