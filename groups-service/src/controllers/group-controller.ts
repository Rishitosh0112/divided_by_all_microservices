declare global {
  namespace Express {
    interface Request {
      userId: string;
    }
  }
}

import { Request, Response } from "express";
import { groupService } from "../services/group-service";

import {
  validateGroupCreate,
  validateGroupUpdate,
  validateUUID,
} from "../util/validator";
import { asyncHandler } from "../middleware/errorHandler";

export const createGroup = asyncHandler(async (req: Request, res: Response) => {
  validateGroupCreate(req.body);
  const group = await groupService.createGroup(
    req.body.name,
    req.body.description,
    req.userId,
  );
  res.status(201).json({ statusCode: 201, data: group });
});

export const getGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  const group = await groupService.getGroup(
    req.params.groupId as string,
    req.userId!,
  );
  res.status(200).json({ statusCode: 200, data: group });
});

export const listUserGroups = asyncHandler(
  async (req: Request, res: Response) => {
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
    const offset = parseInt(req.query.offset as string) || 0;
    const result = await groupService.listUserGroups(
      req.userId!,
      limit,
      offset,
    );
    res.status(200).json({ statusCode: 200, data: result });
  },
);

export const updateGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  validateGroupUpdate(req.body);
  const group = await groupService.updateGroup(
    req.params.groupId as string,
    req.userId!,
    req.body,
  );
  res.status(200).json({ statusCode: 200, data: group });
});

export const deleteGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  await groupService.deleteGroup(req.params.groupId as string, req.userId!);
  res.status(204).send();
});

/**
 *   Group Invitation Controller
 * - Validates input
 * - Calls service to create invitation
 * - Returns appropriate response
 * @param request
 * @param response
 */
export const inviteToGroup = asyncHandler(
  async (req: Request, res: Response) => {
    console.log("inviteToGroup called with body", req.body);
    console.log("userId", req.userId);
    console.log("groupId", req.params.groupId);
    validateUUID(req.params.groupId as string);
    const { invitedUserId, status } = req.body;
    if (!invitedUserId) {
      res.status(400).json({
        statusCode: 400,
        error: { message: "invitedUserId is required" },
      });
      return;
    }
    await groupService.createGroupInvitation(
      req.params.groupId as string,
      invitedUserId,
      req.userId,
      status || "pending",
    );
    res.status(200).json({ statusCode: 200, message: "Invitation sent" });
  },
);

/**
 *  invitationId: string,
    userId: string,
    accept: boolean,

    /http://localhost:PORT/group/:invitationId/invite
 */

export const resolveGroupInvitation = asyncHandler(
  async (req: Request, res: Response) => {
    console.log("inviteToGroup called with body", req.body);
    console.log("groupId", req.params);
    const userId = req.userId;
    const { status } = req.body;
    const { groupId, invitationId } = req.params;
    await groupService.resolveGroupInvitation(
      groupId as string,
      invitationId as string,
      userId,
      status === "accepted",
    );

     res.status(200).json({ statusCode: 200, message: "you are part of group" });
  },
);
