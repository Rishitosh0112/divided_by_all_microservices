import { Request, Response, NextFunction } from 'express';

export const extractUserId = (req: Request, res: Response, next: NextFunction) => {
  
  console.log("userId", req.headers['x-user-id']);
  const userId = req.headers['x-user-id'] as string;

  if (!userId) {
    res.status(401).json({ statusCode: 401, error: { message: 'Unauthorized' } });
    return;
  }

  req.userId = userId;
  next();
};
