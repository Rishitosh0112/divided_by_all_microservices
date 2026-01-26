import express from "express";
import User from "../model/user";
import { Request, Response } from "express";
import { validateEditProfileData } from "../utils/validation";
import { requireAuth } from "../middleware/auth";

const profileRouter = express.Router();
/** profile */

profileRouter.post("/", async (req, res) => {
  try {
    const user = new User(req.body);
    await user.save();
    res.status(201).json(user);
  } catch (err: any) {
    res.status(400).json({ error: err.message });
  }
});

profileRouter.patch("/:userId", requireAuth, async (req: any, res) => {
  try {
    const userId = req.params?.userId;
    const data = req.body;
    const isAllowedUpdates = validateEditProfileData(data);
    if (!isAllowedUpdates) {
      throw new Error("Invalid updates!");
    }

    Object.keys(data).forEach((a) => {
      req.user[a] = data[a];
    });
    await req.user.save();


   await User.updateOne({ _id: userId }, { $set: data });
   
   const user =  await User.findById({_id: userId});


    res.send("user " + user + " updated successfully");
  } catch (e) {
    res.send("error occured during patch" + e);
  }
});

/** get user */
profileRouter.get("/:userId", async (req, res) => {
  const userId = req.params?.userId;
  try {
    const users = await User.find({ _id: userId });
    if (users.length === 0) {
      res.send(404).send("User not found");
    } else {
      res.send(users);
    }
  } catch (e) {
    res.send(400).send("Something went wrong");
  }
});

/** GET all Users*/

profileRouter.get("/", async (req, res) => {
  console.log("get profile called");
  const currentUserId = req.headers["x-user-id"];

  if (!currentUserId) {
    res.status(400).json({ error: "User id missing" });
    return;
  }

  const users = await User.find({
    _id: { $ne: currentUserId }
  })
    .select("-password") // 🔐 never send password
    .limit(50);          // safety limit

  res.json(users);
});

profileRouter.get("/user", async (req, res) => {
  const userEmail = req.body.emailId;
  try {
    const users = await User.find({ emailId: userEmail });
    if (users.length === 0) {
      res.send(404).send("User not found");
    } else {
      res.send(users);
    }
  } catch (e) {
    res.send(400).send("Something went wrong");
  }
});

export default profileRouter;
