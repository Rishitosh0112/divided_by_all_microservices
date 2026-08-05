import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  /** Opens Prisma's database connection when Nest initializes this provider. @returns A promise that resolves after connecting. */
  async onModuleInit(): Promise<void> {
    await this.$connect();
  }

  /** Closes Prisma's database connection when Nest shuts down. @returns A promise that resolves after disconnecting. */
  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
  }
}
