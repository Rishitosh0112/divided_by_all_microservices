require("./config/database");
import express, { Request, Response } from "express";
import cookieParser from "cookie-parser";
import authRouter from "./router/auth_session";
import profileRouter from "./router/profile";


const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(cookieParser());

app.use((req, res, next) => {
  console.log("GLOBAL:", req.method, req.url);
  next();
});

app.use("/auth", authRouter);
app.use("/user", profileRouter);

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Server listening at http://localhost:${PORT}`);
});
