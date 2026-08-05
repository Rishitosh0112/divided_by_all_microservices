import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { DomainValidationFilter } from './interface/http/domain-validation.filter.js';

/**
 * Starts NestJS, enables request validation, and begins listening for HTTP requests.
 * @returns A promise that resolves after the HTTP server starts.
 */
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.useGlobalFilters(new DomainValidationFilter());
  await app.listen(Number(process.env.PORT ?? 4003));
}

void bootstrap();
