import { Body, Controller, Headers, Post, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CreateTelegramMessageDto } from './dto/create-telegram-message.dto';
import { TelegramService } from './telegram.service';

@Controller('telegram')
export class TelegramController {
  constructor(
    private readonly config: ConfigService,
    private readonly telegramService: TelegramService,
  ) {}

  @Post('message')
  async createMessage(
    @Headers('x-telegram-webhook-secret') secret: string | undefined,
    @Body() dto: CreateTelegramMessageDto,
  ) {
    const expectedSecret = this.config.get<string>('TELEGRAM_WEBHOOK_SECRET');
    if (expectedSecret && expectedSecret !== 'change_me' && secret !== expectedSecret) {
      throw new UnauthorizedException('Invalid Telegram webhook secret');
    }

    const message = await this.telegramService.saveAndQueue(dto);
    return {
      success: true,
      message_id: message.id,
      queued: true,
    };
  }
}
