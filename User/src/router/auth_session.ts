import * as express from "express";
import { validateSignupData } from "../utils/validation";
import { requireAuth } from "../middleware/auth";

import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import User from "../model/user";

const authRouter = express.Router();

const JWT_SECRET = process.env.JWT_SECRET!;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || "7d";

authRouter.post("/login", async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      res.status(400).json({ error: "Email and password required" });
      return;
    }

    const user = await User.findOne({ email });
    if (!user) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }

    const isPasswordValid = await bcrypt.compare(password, user.password);
    if (!isPasswordValid) {
      res.status(401).json({ error: "Invalid credentials" });
      return;
    }

    const token = jwt.sign({ userId: user._id.toString() }, JWT_SECRET, {
      expiresIn: JWT_EXPIRES_IN,
    });

    res.cookie("token", token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      maxAge: 1000 * 60 * 60 * 24 * 7,
    });

    res.status(200).json({ message: "Login successful", userId: user._id.toString() });
  } catch {
    res.status(500).json({ error: "Login failed" });
  }
});

authRouter.post("/logout", (req, res) => {
  res.clearCookie("token");
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
