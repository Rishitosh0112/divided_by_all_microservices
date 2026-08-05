import { Money } from './money.js';

describe("Money", () => {
  it("creates a valid INR amount in minor units", () => {
    const money = new Money(1050, "INR");
    expect(money.amountMinor).toBe(1050);
    expect(money.currency).toBe("INR");
  });

  it("rejects a negative amount", () => {
    expect(() => new Money(-1, "INR")).toThrow(
      "amountMinor cannot be negative",
    );
  });

  it("rejects an empty currency", () => {
    expect(() => new Money(1050, "")).toThrow("currency is required");
  });
});
