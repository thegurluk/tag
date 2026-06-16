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

  async search(query?: string) {
    const normalizedQuery = query?.trim();
    if (!normalizedQuery || normalizedQuery.length < 2) {
      throw new BadRequestException('Search query must be at least 2 characters');
    }

    const apiKey = this.config.get<string>('GOOGLE_MAPS_API_KEY');
    if (!apiKey || apiKey === 'change_me') {
      throw new ServiceUnavailableException('Google API key is not configured');
    }

    const searchText = `${normalizedQuery} İstanbul`;
    const params = new URLSearchParams({
      address: searchText,
      key: apiKey,
      language: 'tr',
      region: 'tr',
      components: 'country:TR',
    });

    const response = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?${params.toString()}`,
    );

    if (!response.ok) {
      throw new BadRequestException(`Google Geocoding API failed with ${response.status}`);
    }

    const data = (await response.json()) as {
      status?: string;
      results?: Array<{
        place_id?: string;
        formatted_address?: string;
        geometry?: { location?: { lat?: number; lng?: number } };
        address_components?: Array<{
          long_name: string;
          short_name: string;
          types: string[];
        }>;
      }>;
    };

    if (data.status && !['OK', 'ZERO_RESULTS'].includes(data.status)) {
      throw new BadRequestException(`Google Geocoding API returned ${data.status}`);
    }

    return (data.results ?? [])
      .slice(0, 5)
      .map((result) => {
        const location = result.geometry?.location;
        return {
          id: result.place_id ?? result.formatted_address ?? `${location?.lat},${location?.lng}`,
          title: this.pickResultTitle(result.address_components, result.formatted_address),
          formatted_address: result.formatted_address ?? '',
          latitude: location?.lat,
          longitude: location?.lng,
        };
      })
      .filter((result) => typeof result.latitude === 'number' && typeof result.longitude === 'number');
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

  private pickResultTitle(
    components?: Array<{ long_name: string; types: string[] }>,
    formattedAddress?: string,
  ): string {
    const preferred = components?.find((component) =>
      component.types.some((type) =>
        ['point_of_interest', 'establishment', 'route', 'neighborhood', 'locality'].includes(type),
      ),
    );

    return preferred?.long_name ?? formattedAddress?.split(',')[0] ?? 'Konum';
  }
}
