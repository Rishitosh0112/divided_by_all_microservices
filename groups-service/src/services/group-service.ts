import { NotFound } from "../util/error";
import { Forbidden } from "../util/error";
import { Pool } from "pg";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "@prisma/client";

class GroupService {
  private prisma;
  constructor() {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      throw new Error("DATABASE_URL is missing");
    }

    // 1. Create the connection pool
    const pool = new Pool({ connectionString });

    // 2. Setup the Prisma adapter
    const adapter = new PrismaPg(pool);

    // 3. Instantiate the client with the adapter
    this.prisma = new PrismaClient({ adapter });
  }
  async createGroup(name: string, description: string, userId: string) {
    return this.prisma.$transaction(async (tx: any) => {
      const group = await tx.group.create({
        data: {
          name,
          description: description || null,
          createdBy: userId,
        },
      });

      await tx.groupMember.create({
        data: {
          groupId: group.id,
          userId,
          role: "admin",
        },
      });
      return group;
    });
  }

  async getGroup(groupId: string, userId: string) {
    const group = await this.prisma.group.findUnique({
      where: { id: groupId },
    });

    if (!group || !group.isActive) {
      throw new NotFound("Group not found");
    }

    const member = await this.prisma.groupMember.findUnique({
      where: { groupId_userId: { groupId, userId } },
    });

    if (!member) {
      throw new Forbidden("You are not a member of this group");
    }

    return group;
  }

  async listUserGroups(userId: string, limit: number, offset: number) {
    const groups = await this.prisma.group.findMany({
      where: {
        members: { some: { userId } },
      },
      orderBy: { createdAt: "desc" },
      take: limit,
      skip: offset,
    });

    const total = await this.prisma.group.count({
      where: { members: { some: { userId } } },
    });

    return { data: groups, total, limit, offset };
  }

  async updateGroup(
    groupId: string,
    userId: string,
    data: { name?: string; description?: string },
  ) {
    const group = await this.prisma.group.findUnique({
      where: { id: groupId },
    });

    if (!group) throw new NotFound("Group not found");
    if (group.createdBy !== userId)
      throw new Forbidden("Only creator can update");

    return this.prisma.group.update({ where: { id: groupId }, data });
  }

  async deleteGroup(groupId: string, userId: string) {
    const group = await this.prisma.group.findUnique({
      where: { id: groupId },
    });

    if (!group) throw new NotFound("Group not found");
    if (group.createdBy !== userId)
      throw new Forbidden("Only creator can delete");

    return this.prisma.group.update({
      where: { id: groupId },
      data: { isActive: false },
    });
  }

  /** Group Invitation   */
  async createGroupInvitation(
    groupId: string,
    invitedUserId: string,
    inviterUserId: string,
    status: string,
  ) {
    await this.prisma.groupInvitation.create({
      data: {
        groupId,
        invitedUserId,
        invitedBy: inviterUserId,
        status,
      },
    });
  }

  async resolveGroupInvitation(
    groupId: string,
    invitationId: string,
    userId: string,
    accept: boolean,
  ) {
    await this.prisma.$transaction(async (tx: any) => {

      const invitation = await tx.groupInvitation.findUnique({
        where: { id: invitationId },
      });

      if (!invitation) {
        throw new NotFound("Invitation not found");
      }

     
      if (invitation.groupId !== groupId) {
        throw new Forbidden("Wrong group");
      }

      console.log("check invitedUserId", invitation.invitedUserId);
      console.log("check userId", userId);

      if (invitation.invitedUserId !== userId) {
        throw new Forbidden("You are not invited to this group");
      }

      if (invitation.status !== "pending") {
        throw new Forbidden("Invitation already resolved");
      }

      if (accept) {
        await tx.groupInvitation.update({
          where: {id: invitationId},
          data: {
            status: accept ? "accepted": "rejected",
            respondedAt: new Date(),
          }
        })
        await tx.groupMember.create({
          data: {
            groupId: invitation.groupId,
            userId,
            role: "member",
          },
        });
      }
    });
  }
}

export const groupService = new GroupService();
