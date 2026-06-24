import { BadRequest } from './error';

export const validateGroupCreate = (body: any) => {
  console.log("body", body);
  if (!body.name || body.name.trim().length === 0) {
    throw new BadRequest('Group name is required');
  }

  if (body.name.length > 255) {
    throw new BadRequest('Group name must be less than 255 characters');
  }

  if (body.description && body.description.length > 1000) {
    throw new BadRequest('Description must be less than 1000 characters');
  }
};

export const validateGroupUpdate = (body: any) => {
  if (body.name && body.name.length > 255) {
    throw new BadRequest('Group name must be less than 255 characters');
  }

  if (body.description && body.description.length > 1000) {
    throw new BadRequest('Description must be less than 1000 characters');
  }
};

export const validateUUID = (id: string) => {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  
  if (!uuidRegex.test(id)) {
    throw new BadRequest(`Invalid UUID format: ${id}`);
  }
};

export const validateInvitation = (body: any) => {
  if (!body.invitedUserId) {
    throw new BadRequest('invitedUserId is required');
  }

  validateUUID(body.invitedUserId);
};