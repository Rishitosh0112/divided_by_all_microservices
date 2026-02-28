import express from "express";
import * as groupController from "../controllers/group-controller";

const groupRouter = express.Router();

groupRouter.post("/", groupController.createGroup);
groupRouter.get("/:groupId", groupController.getGroup);
groupRouter.get("/", groupController.listUserGroups);
groupRouter.patch("/:groupId", groupController.updateGroup);
groupRouter.delete("/:groupId", groupController.deleteGroup);

export default groupRouter;