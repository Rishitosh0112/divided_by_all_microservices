-- CreateTable
CREATE TABLE "group_invitations" (
    "id" UUID NOT NULL,
    "groupId" UUID NOT NULL,
    "invitedUserId" UUID NOT NULL,
    "invitedBy" UUID NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "respondedAt" TIMESTAMP(3),

    CONSTRAINT "group_invitations_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "group_invitations_groupId_invitedUserId_key" ON "group_invitations"("groupId", "invitedUserId");

-- AddForeignKey
ALTER TABLE "group_invitations" ADD CONSTRAINT "group_invitations_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "groups"("id") ON DELETE CASCADE ON UPDATE CASCADE;
