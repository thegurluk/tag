import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { Queue } from 'bullmq';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTelegramMessageDto } from './dto/create-telegram-message.dto';

@Injectable()
export class TelegramService {
  constructor(
    private readonly prisma: PrismaService,
    @InjectQueue('telegram-messages') private readonly queue: Queue,
  ) {}

  async saveAndQueue(dto: CreateTelegramMessageDto) {
    const message = await this.prisma.telegramMessage.upsert({
      where: {
        telegramMessageId_telegramGroupId: {
          telegramMessageId: dto.telegram_message_id,
          telegramGroupId: dto.telegram_group_id,
        },
      },
      update: {
        rawText: dto.raw_text,
        senderId: dto.sender_id ?? null,
        receivedAt: new Date(dto.received_at),
      },
      create: {
        telegramMessageId: dto.telegram_message_id,
        telegramGroupId: dto.telegram_group_id,
        senderId: dto.sender_id ?? null,
        rawText: dto.raw_text,
        receivedAt: new Date(dto.received_at),
      },
    });

    await this.queue.add('process-message', { messageId: message.id }, { jobId: message.id });
    return message;
  }
}
