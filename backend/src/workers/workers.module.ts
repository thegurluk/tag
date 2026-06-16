import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { GoogleGeocodingService } from './google-geocoding.service';
import { LocationProcessor } from './location.processor';
import { MessageCleaningService } from './message-cleaning.service';
import { ExpirationWorker } from './expiration.worker';

@Module({
  imports: [
    BullModule.registerQueue({ name: 'telegram-messages' }),
    ScheduleModule.forRoot(),
  ],
  providers: [
    MessageCleaningService,
    GoogleGeocodingService,
    LocationProcessor,
    ExpirationWorker,
  ],
})
export class WorkersModule {}
