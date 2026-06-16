import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { getLocationAgeMinutes, getLocationColor } from '../common/time/location-color';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class LocationsService {
  constructor(private readonly prisma: PrismaService) {}

  async getActiveLocations() {
    const rows = await this.prisma.activeLocation.findMany({
      where: {
        status: 'active',
        expiresAt: { gt: new Date() },
      },
      orderBy: { createdAt: 'desc' },
    });

    return rows.map((location) => ({
      id: location.id,
      title: location.title ?? location.cleanedLocationText,
      latitude: location.latitude,
      longitude: location.longitude,
      formatted_address: location.formattedAddress,
      created_at: location.createdAt,
      expires_at: location.expiresAt,
      color: getLocationColor(location.createdAt),
      age_minutes: getLocationAgeMinutes(location.createdAt),
    }));
  }

  async getNearbyLocations(lat: number, lng: number, radiusMeters: number) {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(radiusMeters)) {
      throw new BadRequestException('lat, lng, and radius must be valid numbers');
    }

    const rows = await this.prisma.$queryRaw<
      Array<{
        id: string;
        title: string | null;
        cleaned_location_text: string;
        latitude: number;
        longitude: number;
        formatted_address: string | null;
        created_at: Date;
        expires_at: Date;
        distance_meters: number;
      }>
    >(Prisma.sql`
      SELECT
        id,
        title,
        cleaned_location_text,
        latitude,
        longitude,
        formatted_address,
        created_at,
        expires_at,
        ST_Distance(
          geom,
          ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography
        ) AS distance_meters
      FROM active_locations
      WHERE status = 'active'
        AND expires_at > NOW()
        AND geom IS NOT NULL
        AND ST_DWithin(
          geom,
          ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography,
          ${radiusMeters}
        )
      ORDER BY distance_meters ASC
    `);

    return rows.map((location) => ({
      id: location.id,
      title: location.title ?? location.cleaned_location_text,
      latitude: location.latitude,
      longitude: location.longitude,
      formatted_address: location.formatted_address,
      created_at: location.created_at,
      expires_at: location.expires_at,
      distance_meters: Number(location.distance_meters),
      color: getLocationColor(location.created_at),
      age_minutes: getLocationAgeMinutes(location.created_at),
    }));
  }

  async getArchive() {
    return this.prisma.locationArchive.findMany({
      orderBy: { expiredAt: 'desc' },
      take: 100,
    });
  }
}
