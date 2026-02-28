import { Request, Response } from 'express';
import { groupService } from '../services/group-service';

import { validateGroupCreate, validateGroupUpdate, validateUUID } from '../util/validator';
import { asyncHandler } from '../middleware/errorHandler';

export const createGroup = asyncHandler(async (req: Request, res: Response) => {
  validateGroupCreate(req.body);
  const group = await groupService.createGroup(req.body.name, req.body.description, req.userId!);
  res.status(201).json({ statusCode: 201, data: group });
});

export const getGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  const group = await groupService.getGroup(req.params.groupId as string, req.userId!);
  res.status(200).json({ statusCode: 200, data: group });
});

export const listUserGroups = asyncHandler(async (req: Request, res: Response) => {
  const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
  const offset = parseInt(req.query.offset as string) || 0;
  const result = await groupService.listUserGroups(req.userId!, limit, offset);
  res.status(200).json({ statusCode: 200, data: result });
});

export const updateGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  validateGroupUpdate(req.body);
  const group = await groupService.updateGroup(req.params.groupId as string, req.userId!, req.body);
  res.status(200).json({ statusCode: 200, data: group });
});

export const deleteGroup = asyncHandler(async (req: Request, res: Response) => {
  validateUUID(req.params.groupId as string);
  await groupService.deleteGroup(req.params.groupId as string, req.userId!);
  res.status(204).send();
});