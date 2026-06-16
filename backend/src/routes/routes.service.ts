import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { CalculateRouteDto } from './dto/calculate-route.dto';

@Injectable()
export class RoutesService {
  constructor(private readonly config: ConfigService) {}

  async calculate(dto: CalculateRouteDto) {
    const apiKey = this.config.get<string>('GOOGLE_MAPS_API_KEY');
    if (!apiKey || apiKey === 'change_me') {
      throw new ServiceUnavailableException('Google Routes API key is not configured');
    }

    const preferredMode = dto.mode === 'motorcycle' ? 'TWO_WHEELER' : 'DRIVE';
    const route = await this.requestRoute(dto, preferredMode, apiKey);

    if (!route && preferredMode === 'TWO_WHEELER') {
      return this.requestRoute(dto, 'DRIVE', apiKey);
    }

    if (!route) {
      throw new BadRequestException('Route could not be calculated');
    }

    return route;
  }

  private async requestRoute(
    dto: CalculateRouteDto,
    travelMode: 'DRIVE' | 'TWO_WHEELER',
    apiKey: string,
  ) {
    const response = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': apiKey,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline',
      },
      body: JSON.stringify({
        origin: {
          location: {
            latLng: {
              latitude: dto.origin.latitude,
              longitude: dto.origin.longitude,
            },
          },
        },
        destination: {
          location: {
            latLng: {
              latitude: dto.destination.latitude,
              longitude: dto.destination.longitude,
            },
          },
        },
        travelMode,
        routingPreference: travelMode === 'DRIVE' ? 'TRAFFIC_UNAWARE' : undefined,
        polylineQuality: 'OVERVIEW',
      }),
    });

    if (!response.ok) {
      if (travelMode === 'TWO_WHEELER') return null;
      throw new BadRequestException(`Google Routes API failed with ${response.status}`);
    }

    const data = (await response.json()) as {
      routes?: Array<{
        distanceMeters?: number;
        duration?: string;
        polyline?: { encodedPolyline?: string };
      }>;
    };
    const route = data.routes?.[0];
    if (!route?.polyline?.encodedPolyline) return null;

    return {
      distance_meters: route.distanceMeters ?? 0,
      duration_seconds: this.parseGoogleDuration(route.duration),
      polyline: route.polyline.encodedPolyline,
      travel_mode_used: travelMode,
    };
  }

  private parseGoogleDuration(duration?: string): number {
    if (!duration) return 0;
    return Number(duration.replace('s', '')) || 0;
  }
}
