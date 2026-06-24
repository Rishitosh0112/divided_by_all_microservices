import dotenv from 'dotenv';
// import { PrismaClient } from '@prisma/client';

dotenv.config();

export const config = {
  PORT: process.env.PORT || 4002,
  NODE_ENV: process.env.NODE_ENV || 'development',
};

// export const prisma = new PrismaClient();