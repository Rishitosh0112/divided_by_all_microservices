import express from "express";
import { errorHandler } from "./src/middleware/errorHandler";
import groupRouter from "./src/routers/group-route";

const app = express();
app.use(express.json());

app.get("/health", (req, res) => [
  res.json({status: 'ok', service: 'group-service'})
])

app.use((req, res) => {
  res.status(404).json({
    statusCode: 404,
    error: {message: "Not Found"}
  })
});

app.use(errorHandler)

app.use("/group", groupRouter);

const PORT = process.env.PORT || 6000;

app.listen(PORT, () => {
  console.log(`Group Service running on port ${PORT}`);
});