import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  getHealth() {
    return {
      status: 'ok',
      service: 'location-alert-backend',
      timestamp: new Date().toISOString(),
    };
  }
}
