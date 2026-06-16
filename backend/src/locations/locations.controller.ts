import { Controller, Delete, Get, Param, Query } from '@nestjs/common';
import { LocationsService } from './locations.service';

@Controller('locations')
export class LocationsController {
  constructor(private readonly locationsService: LocationsService) {}

  @Get('active')
  getActive() {
    return this.locationsService.getActiveLocations();
  }

  @Get('nearby')
  getNearby(
    @Query('lat') lat: string,
    @Query('lng') lng: string,
    @Query('radius') radius = '5000',
  ) {
    return this.locationsService.getNearbyLocations(
      Number(lat),
      Number(lng),
      Number(radius),
    );
  }

  @Get('archive')
  getArchive() {
    return this.locationsService.getArchive();
  }

  @Get(':id')
  getById(@Param('id') id: string) {
    return this.locationsService.getLocationDetail(id);
  }

  @Delete(':id')
  deleteById(@Param('id') id: string) {
    return this.locationsService.deleteActiveLocation(id);
  }
}
