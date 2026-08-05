export class DomainValidationError extends Error {
  /**
   * Creates a business-rule validation error that the HTTP layer returns as 400.
   * @param message Human-readable explanation of the invalid business rule.
   */
  constructor(message: string) {
    super(message);
    this.name = 'DomainValidationError';
  }
}
