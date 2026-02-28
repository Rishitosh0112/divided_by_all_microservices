import { Request, Response, NextFunction } from 'express';
import { AppError } from '../util/error';

declare global {
  namespace Express {
    interface Request {
      userId?: string;
    }
  }
}

export const errorHandler = (
  error: Error | AppError,
  req: Request,
  res: Response,
  next: NextFunction
) => {
  console.error('Error:', error);

  if (error instanceof AppError) {
    return res.status(error.statusCode).json({
      statusCode: error.statusCode,
      error: {
        message: error.message,
      },
    });
  }

  return res.status(500).json({
    statusCode: 500,
    error: {
      message: 'Internal Server Error',
    },
  });
};

export const asyncHandler = (
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>
) => (req: Request, res: Response, next: NextFunction) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};