import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface GeocodingResult {
  latitude: number;
  longitude: number;
  formattedAddress: string;
  placeId?: string;
  confidenceScore: number;
}

@Injectable()
export class GoogleGeocodingService {
  private readonly logger = new Logger(GoogleGeocodingService.name);

  constructor(private readonly config: ConfigService) {}

  async geocode(cleanedText: string): Promise<GeocodingResult | null> {
    const apiKey = this.config.get<string>('GOOGLE_MAPS_API_KEY');
    if (!apiKey || apiKey === 'change_me') {
      this.logger.warn('GOOGLE_MAPS_API_KEY is not configured; skipping geocoding');
      return null;
    }

    const cityContext = this.config.get<string>('GOOGLE_CITY_CONTEXT', 'Istanbul');
    const query = `${cleanedText} ${cityContext}`;
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('address', query);
    url.searchParams.set('key', apiKey);
    url.searchParams.set('language', 'tr');
    url.searchParams.set('region', 'tr');

    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Google Geocoding failed with ${response.status}`);
    }

    const data = (await response.json()) as {
      status: string;
      results?: Array<{
        formatted_address: string;
        place_id?: string;
        geometry: { location: { lat: number; lng: number }; location_type?: string };
      }>;
    };

    const first = data.results?.[0];
    if (data.status !== 'OK' || !first) {
      return null;
    }

    return {
      latitude: first.geometry.location.lat,
      longitude: first.geometry.location.lng,
      formattedAddress: first.formatted_address,
      placeId: first.place_id,
      confidenceScore: this.score(cleanedText, first.formatted_address, first.geometry.location_type),
    };
  }

  private score(cleanedText: string, formattedAddress: string, locationType?: string): number {
    let score = 0.35;
    const normalizedAddress = formattedAddress.toLocaleUpperCase('tr-TR');
    const words = cleanedText.split(/\s+/).filter((word) => word.length > 2);
    const matchedWords = words.filter((word) => normalizedAddress.includes(word)).length;

    if (words.length > 0) {
      score += Math.min(0.25, (matchedWords / words.length) * 0.25);
    }

    if (normalizedAddress.includes('İSTANBUL') || normalizedAddress.includes('ISTANBUL')) {
      score += 0.2;
    }

    if (locationType === 'ROOFTOP' || locationType === 'GEOMETRIC_CENTER') {
      score += 0.2;
    }

    return Math.min(1, Number(score.toFixed(2)));
  }
}
