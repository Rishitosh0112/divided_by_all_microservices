import { Request, Response, NextFunction } from "express";

const userAuth = (req: any, res: Response, next: NextFunction) => {
  // Identity injected by NGINX after auth_request
  const userId = req.headers["x-user-id"];

  if (!userId) {
    res.status(401).json({
      error: "Unauthorized: user not authenticated",
    });
  }

  // Attach to request for downstream handlers
  req.userId = userId;

  next();
};

export default userAuth;