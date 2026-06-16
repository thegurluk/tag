import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Job } from 'bullmq';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { GoogleGeocodingService } from './google-geocoding.service';
import { MessageCleaningService } from './message-cleaning.service';

interface ProcessMessageJob {
  messageId: string;
}

@Processor('telegram-messages')
export class LocationProcessor extends WorkerHost {
  private readonly logger = new Logger(LocationProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly cleaner: MessageCleaningService,
    private readonly geocoder: GoogleGeocodingService,
    private readonly config: ConfigService,
  ) {
    super();
  }

  async process(job: Job<ProcessMessageJob>) {
    const message = await this.prisma.telegramMessage.findUnique({
      where: { id: job.data.messageId },
    });

    if (!message) {
      this.logger.warn(`Telegram message not found: ${job.data.messageId}`);
      return;
    }

    const cleanedText = this.cleaner.clean(message.rawText);
    if (!cleanedText) {
      await this.prisma.telegramMessage.update({
        where: { id: message.id },
        data: { processed: false, processingError: 'Message did not contain a usable location' },
      });
      return;
    }

    const geocoding = await this.geocoder.geocode(cleanedText);
    if (!geocoding) {
      await this.prisma.telegramMessage.update({
        where: { id: message.id },
        data: {
          processed: false,
          processingError: 'No geocoding result found or Google key is not configured',
        },
      });
      return;
    }

    const minConfidence = Number(this.config.get<string>('GOOGLE_MIN_CONFIDENCE', '0.65'));
    const status = geocoding.confidenceScore >= minConfidence ? 'active' : 'pending_review';
    const expiresAt = new Date(Date.now() + 9 * 60 * 60 * 1000);

    await this.prisma.$transaction(async (tx) => {
      await tx.activeLocation.create({
        data: {
          telegramMessageId: message.id,
          title: cleanedText,
          rawMessage: message.rawText,
          cleanedLocationText: cleanedText,
          latitude: geocoding.latitude,
          longitude: geocoding.longitude,
          formattedAddress: geocoding.formattedAddress,
          googlePlaceId: geocoding.placeId,
          confidenceScore: geocoding.confidenceScore,
          expiresAt,
          status,
        },
      });

      await tx.$executeRaw(Prisma.sql`
        UPDATE active_locations
        SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
        WHERE telegram_message_id = ${message.id}::uuid
          AND geom IS NULL
      `);

      await tx.telegramMessage.update({
        where: { id: message.id },
        data: { processed: true, processingError: null },
      });
    });
  }
}
