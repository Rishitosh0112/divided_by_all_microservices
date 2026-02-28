import prisma from "@prisma/client";


export const createGroup = async (
    name: string,
    createdBy: string,
    userIds: String []
) => {
    return prisma.$transaction(async (tx: any) => {
        const group = await tx.group.create({
            data: {
                name,
                createdBy
            }
        })
   });

   const mem
}