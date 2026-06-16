import { Body, Controller, Get, Post, Query } from '@nestjs/common';
import { CalculateRouteDto } from './dto/calculate-route.dto';
import { RoutesService } from './routes.service';

@Controller('routes')
export class RoutesController {
  constructor(private readonly routesService: RoutesService) {}

  @Post('calculate')
  calculate(@Body() dto: CalculateRouteDto) {
    return this.routesService.calculate(dto);
  }

  @Get('search')
  search(@Query('q') query: string) {
    return this.routesService.search(query);
  }
}
