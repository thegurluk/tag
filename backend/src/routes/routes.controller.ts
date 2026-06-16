import { Body, Controller, Post } from '@nestjs/common';
import { CalculateRouteDto } from './dto/calculate-route.dto';
import { RoutesService } from './routes.service';

@Controller('routes')
export class RoutesController {
  constructor(private readonly routesService: RoutesService) {}

  @Post('calculate')
  calculate(@Body() dto: CalculateRouteDto) {
    return this.routesService.calculate(dto);
  }
}
