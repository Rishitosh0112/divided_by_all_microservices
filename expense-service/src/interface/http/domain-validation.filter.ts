import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpStatus,
} from '@nestjs/common';
import type { Response } from 'express';
import { DomainValidationError } from '../../domain/shared/domain-validation.error.js';

@Catch(DomainValidationError)
export class DomainValidationFilter implements ExceptionFilter {
  /**
   * Converts domain validation errors into consistent HTTP 400 responses.
   * @param exception The business-rule error raised by the domain.
   * @param host NestJS context used to access the HTTP response.
   * @returns Nothing; writes the HTTP response directly.
   */
  catch(exception: DomainValidationError, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();
    response.status(HttpStatus.BAD_REQUEST).json({
      statusCode: HttpStatus.BAD_REQUEST,
      message: exception.message,
      error: 'Bad Request',
    });
  }
}
