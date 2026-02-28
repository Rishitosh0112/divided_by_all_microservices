import { PrismaClient } from '@prisma/client';
import { NotFound } from "../util/error";
import { Forbidden } from "../util/error";



class GroupService {
  private prisma;
  constructor() {
    this.prisma = new (require('@prisma/client').PrismaClient)();
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

      await tx.groupMemeber.create({
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
    const group = await this.prisma.group.findUnique({ where: { id: groupId } });

    if (!group) throw new NotFound("Group not found");
    if (group.createdBy !== userId)
      throw new Forbidden("Only creator can update");

    return this.prisma.group.update({ where: { id: groupId }, data });
  }

  async deleteGroup(groupId: string, userId: string) {
    const group = await this.prisma.group.findUnique({ where: { id: groupId } });

    if (!group) throw new NotFound("Group not found");
    if (group.createdBy !== userId)
      throw new Forbidden("Only creator can delete");

    return this.prisma.group.update({
      where: { id: groupId },
      data: { isActive: false },
    });
  }

  
}

export const groupService = new GroupService();
