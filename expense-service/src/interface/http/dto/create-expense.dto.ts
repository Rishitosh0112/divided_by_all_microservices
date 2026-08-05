import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  Length,
  Min,
  ValidateNested,
} from 'class-validator';
import type { SplitType } from '../../../domain/expense/split-strategy.js';

export class ExpenseParticipantDto {
  /**
   * if (typeof request.userId !== 'string') {
     throw new Error('userId must be a string');
   }
  */
  @IsString()
  @IsNotEmpty()
  userId!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  amountMinor?: number;
}

export class CreateExpenseDto {
  @IsString()
  @IsNotEmpty()
  groupId!: string;

  @IsString()
  @IsNotEmpty()
  description!: string;

  @IsString()
  @IsNotEmpty()
  paidByUserId!: string;

  @IsInt()
  @Min(1)
  amountMinor!: number;

  @IsString()
  @Length(3, 3)
  currency!: string;

  @IsIn(['EQUAL', 'EXACT'])
  splitType!: SplitType;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => ExpenseParticipantDto)
  participants!: ExpenseParticipantDto[];
}
