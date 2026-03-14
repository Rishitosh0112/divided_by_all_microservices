import mongoose from "mongoose";

const mongoDbConnectionString = process.env.MONGO_URL || "mongodb+srv://rishitosh:Rishi1Neha2@cluster0.a102n.mongodb.net/?appName=Cluster0";

// mongodb+srv://Rishi:Sg42QWv23ZK3ty7z@clusterfree.weasj.mongodb.net/

const connectDB = async () => {
  await mongoose.connect(mongoDbConnectionString)
}

connectDB()
  .then(() => {
    console.log("DB connection successful")
  })
  .catch((e) => {
    console.log("DB connection unsuccessful", e);
  });
