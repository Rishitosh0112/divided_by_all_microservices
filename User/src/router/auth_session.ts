import * as express from "express";
import { validateSignupData } from "../utils/validation";
import { requireAuth } from "../middleware/auth";

import bcrypt from "bcrypt";
import crypto from "crypto";
import User from "../model/user";
import redis from "../config/redis";

const authRouter = express.Router();
console.log("🔥 AUTH ROUTER FILE LOADED 🔥");

authRouter.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;
    console.log("email", email);
    console.log("password", password);

    if (!email || !password) {
      res.status(400).json({ error: "Email and password required" });
      return
    }

    const user = await User.findOne({ email });

    debugger;
    if (!user) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }

    console.log("check user", user.password);
    console.log("check user", password)
    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }

    // ✅ 1. Create session ID
    const sessionId = crypto.randomUUID();
    debugger;
    // ✅ 2. Store session in Redis (7 days)
    await redis.set(
      `session:${sessionId}`,
      JSON.stringify({ userId: user._id.toString() }),
      "EX",
      60 * 60 * 24 * 7
    );

    // ✅ 3. Set secure cookie
    res.cookie("session_id", sessionId, {
      httpOnly: true,
      secure: true,        // true in prod (https)
      sameSite: "strict",
      maxAge: 1000 * 60 * 60 * 24 * 7
    });

    res.status(200).json({ message: "Login successful", userId: user._id.toString() });

  } catch (e) {
    res.status(500).json({ e: "Login failed" });
  }
});

authRouter.post("/logout", async (req, res) => {
  const sessionId = req.cookies.session_id;

  if (sessionId) {
    await redis.del(`session:${sessionId}`);
  }

  res.clearCookie("session_id");
  res.json({ message: "Logged out" });
});

authRouter.post("/signup", async (req, res) => {
    console.log("hitting user data");
    try {
      validateSignupData(req);
      console.log("req", req.body);
      const { firstName, lastName, email, password } = req.body;
      const passwordHash = await bcrypt.hash(password, 10);
      console.log("passwordHash", passwordHash);
  
      const userData = req.body;
      const user = new User({
        firstName,
        lastName,
        email,
        password: passwordHash,
      });
  
      await user.save();
      res.send("user saved successfully");
    } catch (e) {
      res.send("error occured"+ e);
    }
  });


authRouter.get("/validate", requireAuth, (req: any, res) => {
  console.log("verify called")
  res.set("X-User-Id", req.user.userId);
  res.sendStatus(200);
});


export default authRouter;
