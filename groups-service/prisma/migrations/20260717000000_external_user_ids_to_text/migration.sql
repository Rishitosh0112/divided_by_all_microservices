-- User IDs originate in the User service, which currently uses MongoDB ObjectIds.
-- They are external references in this bounded context, not PostgreSQL UUIDs.
-- Keep Groups-owned IDs as UUID; store User-owned references as text.

ALTER TABLE "groups"
  ALTER COLUMN "createdBy" TYPE TEXT USING "createdBy"::text;

ALTER TABLE "group_members"
  ALTER COLUMN "userId" TYPE TEXT USING "userId"::text;

ALTER TABLE "group_invitations"
  ALTER COLUMN "invitedUserId" TYPE TEXT USING "invitedUserId"::text,
  ALTER COLUMN "invitedBy" TYPE TEXT USING "invitedBy"::text;
