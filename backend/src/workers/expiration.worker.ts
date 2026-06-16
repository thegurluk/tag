import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class ExpirationWorker {
  private readonly logger = new Logger(ExpirationWorker.name);

  constructor(private readonly prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async expireLocations() {
    const expired = await this.prisma.activeLocation.findMany({
      where: {
        expiresAt: { lte: new Date() },
      },
      take: 100,
    });

    if (expired.length === 0) return;

    await this.prisma.$transaction(async (tx) => {
      for (const location of expired) {
        await tx.locationArchive.create({
          data: {
            originalLocationId: location.id,
            telegramMessageId: location.telegramMessageId,
            title: location.title,
            rawMessage: location.rawMessage,
            cleanedLocationText: location.cleanedLocationText,
            latitude: location.latitude,
            longitude: location.longitude,
            formattedAddress: location.formattedAddress,
            googlePlaceId: location.googlePlaceId,
            confidenceScore: location.confidenceScore,
            originalCreatedAt: location.createdAt,
          },
        });

        await tx.$executeRaw(Prisma.sql`
          UPDATE location_archive
          SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
          WHERE original_location_id = ${location.id}::uuid
            AND geom IS NULL
        `);

        await tx.activeLocation.delete({ where: { id: location.id } });
      }
    });

    this.logger.log(`Archived ${expired.length} expired location(s)`);
  }
}
