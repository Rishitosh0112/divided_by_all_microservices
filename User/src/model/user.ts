import mongoose from "mongoose";
import validator from "validator";

const userSchema = new mongoose.Schema(
  {
    firstName: {
      type: String,
      required: true,
      trim: true,
      minLength: 4,
      maxLength: 50,
    },
    lastName: {
      type: String,
      trim: true,
    },
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      validate: function(value: string) {
        if(!validator.isEmail(value)) {
          throw new Error("invalid email Id"+ value); 
        }
      }

    },
    password: {
      type: String,
      required: true,
      validate: function(value: string) {
        if(!validator.isStrongPassword(value)) {
          throw new Error("Enter strong password"); 
        }
      }
    },
    age: {
      type: Number,
      min: 18,
    },
    gender: {
      type: String,
      validate: function (g: string) {
        if (!["male", "female"].includes(g)) {
          throw new Error("nor valid gender type");
        }
      },
    },
    photoUrl: {
      type: String,
      validate: function(value: string) {
        if(!validator.isURL(value)) {
          throw new Error("invalid email Id"+ value); 
        }
      }
    },
    about: {
      type: String,
      default: "this is about the user",
    },
    skills: {
      type: [String],
    },
    
  },
  {
    timestamps: true,
  }
);

const Users = mongoose.model("User", userSchema);
export default Users;
