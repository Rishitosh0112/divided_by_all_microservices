import express from "express";
import * as groupController from "../controllers/group-controller";

const groupRouter = express.Router();

groupRouter.post("/", groupController.createGroup);
groupRouter.get("/:groupId", groupController.getGroup);
groupRouter.get("/", groupController.listUserGroups);
groupRouter.patch("/:groupId", groupController.updateGroup);
groupRouter.delete("/:groupId", groupController.deleteGroup);

groupRouter.post("/:groupId/invite", groupController.inviteToGroup);

groupRouter.patch("/:groupId/invitation/:invitationId/respondToInvitation", groupController.resolveGroupInvitation);

export default groupRouter;