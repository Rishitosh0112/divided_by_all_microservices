import express, { Request, Response } from "express";
import cookieParser from "cookie-parser";
import authRouter from "./router/auth_session";
import profileRouter from "./router/profile";
import { connectDB, isDatabaseConnected } from "./config/database";


const app = express();
const PORT = process.env.PORT || 8000;

app.use(express.json());
app.use(cookieParser());

app.use((req, res, next) => {
  console.log("GLOBAL:", req.method, req.url);
  next();
});

app.get("/health", (_req, res) => {
  const databaseConnected = isDatabaseConnected();
  res.status(databaseConnected ? 200 : 503).json({
    status: databaseConnected ? "ok" : "degraded",
    service: "user-service",
    databaseConnected,
  });
});

app.use("/auth", authRouter);
app.use("/profiles", profileRouter);

const start = async () => {
  try {
    await connectDB();
    console.log("Database connection successful");
    app.listen(PORT, () => {
      console.log(`User service listening on port ${PORT}`);
    });
  } catch (error) {
    console.error("Unable to start user service", error);
    process.exit(1);
  }
};

void start();
