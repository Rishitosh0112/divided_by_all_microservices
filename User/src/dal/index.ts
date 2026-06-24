abstract class Discount {
  abstract calculate(amount: number): number;
}

class RegularDiscount extends Discount {
  calculate(amount: number): number {
    return amount * 0.10;
  }
}

class PremiumDiscount extends Discount {
  calculate(amount: number): number {
    return amount * 0.20;
  }
}

class DiscountCalculation {
  calculateDiscount(discount: Discount, amount: number): number {
    return discount.calculate(amount);
  }
}