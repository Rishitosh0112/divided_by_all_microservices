import { Request, Response, NextFunction } from "express";

import redis from "../config/redis";

export async function requireAuth(
  req: any,
  res: Response,
  next: NextFunction
) {
  const sessionId = req.cookies?.session_id;

  if (!sessionId) {
    res.sendStatus(401);
    return;
  }

  const session = await redis.get(`session:${sessionId}`);

  if (!session) {
    res.sendStatus(401);
    return;
  }

  req.user = JSON.parse(session); // { userId }
  next();
}