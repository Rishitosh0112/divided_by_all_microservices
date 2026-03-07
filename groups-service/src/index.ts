import "./config";
import express from "express";
import { errorHandler } from "./middleware/errorHandler";
import groupRouter from "./routers/group-route";

const app = express();
app.use(express.json());

app.get("/health", (req, res) => [
  res.json({status: 'ok', service: 'group-service'})
])
console.log("Group Service initialized");
app.use("/groups", groupRouter);

app.use((req, res) => {
  res.status(404).json({
    statusCode: 404,
    error: {message: "Not Found"}
  })
});

app.use(errorHandler)

const PORT = process.env.PORT || 4002;

app.listen(PORT, () => {
  console.log(`Group Service running on port ${PORT}`);
});