export type LocationColor = 'red' | 'yellow' | 'blue' | 'expired';

export function getLocationAgeMinutes(createdAt: Date, now = new Date()): number {
  return Math.max(0, Math.floor((now.getTime() - createdAt.getTime()) / 60000));
}

export function getLocationColor(createdAt: Date, now = new Date()): LocationColor {
  const ageMinutes = getLocationAgeMinutes(createdAt, now);

  if (ageMinutes <= 180) return 'red';
  if (ageMinutes <= 360) return 'yellow';
  if (ageMinutes <= 540) return 'blue';
  return 'expired';
}
