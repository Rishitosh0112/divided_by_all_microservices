import { Request, Response, NextFunction } from 'express';
import { AppError } from '../util/error';



export const errorHandler = (
  error: Error | AppError,
  req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars -- Express requires 4 params (arity) to recognize this as error-handling middleware
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
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>
) => (req: Request, res: Response, next: NextFunction) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};