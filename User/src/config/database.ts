import mongoose from "mongoose";

export const connectDB = async () => {
  const mongoDbConnectionString = process.env.MONGO_URL;

  if (!mongoDbConnectionString) {
    throw new Error("MONGO_URL is required");
  }

  await mongoose.connect(mongoDbConnectionString, {
    maxPoolSize: 10,
    minPoolSize: 2,
    serverSelectionTimeoutMS: 5000,
    socketTimeoutMS: 45000
  });
};

export const isDatabaseConnected = () => mongoose.connection.readyState === 1;
