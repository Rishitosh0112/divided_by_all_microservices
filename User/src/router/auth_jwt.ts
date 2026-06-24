import express  from "express";
import User from "../model/user";
import { validateSignupData } from "../utils/validation";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import { Request, Response } from "express";

const authRouter = express.Router();

function skillsSanitization(data: any) {
    if (data?.skills?.length > 10) {
      throw new Error("Skills cannot be more than 10");
    }
  }

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
  
      skillsSanitization(userData);
      await user.save();
      res.send("user saved successfully");
    } catch (e) {
      res.send("error occured"+ e);
    }
  });
  
  /** login */
authRouter.post("/login", async (req: Request, res: Response) => {
    try {
      const {email, password} = req.body;
      if(!email || !password) {
        throw new Error();
      }
      const user = await User.findOne({email: email});
      if (!user) {
        throw new Error("email Id is not present");
      } 
  
      const isPasswordValid = await bcrypt.compare(password, user.password);
  
      if(isPasswordValid) {
  
        const token = jwt.sign({_id: user._id}, "DEV@Tinder@5569")
        res.cookie("token", token, {expires: new Date(Date.now() + 86400000)});
  
        res.send("Login successful from jet");
      } else {
        res.status(401).send("Invalid credentials");
      }
  
    }
    catch (e) {
      res.send("error occured during login" + e);
    }
  }); 

  authRouter.post("/logout", (req: Request, res: Response) => {
    res.clearCookie("token");
    res.send("Logged out successfully");
  })


export default authRouter;
