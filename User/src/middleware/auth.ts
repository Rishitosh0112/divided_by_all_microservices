import { Request, Response, NextFunction } from "express";

import redis from "../config/redis";

export async function requireAuth(
  req: any,
  res: Response,
  next: NextFunction
) {

  debugger;
  console.log("require auth called", req.cookies?.session_id);
  const sessionId = req.cookies?.session_id;

  if (!sessionId) {
    res.sendStatus(401);
    return;
  }

  const session = await redis.get(`session:${sessionId}`);
  console.log("session", session);
  if (!session) {
    res.sendStatus(401);
    return;
  }

  req.user = JSON.parse(session); // { userId }
  next();
}