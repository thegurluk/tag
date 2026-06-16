import { Injectable } from '@nestjs/common';

const NOISE_TERMS = [
  'sivil trafik',
  'trafik',
  'polis',
  'çevirme',
  'cevirme',
  'kontrol',
  'ekip',
  'dendi',
  'denildi',
  'var',
  'görüldü',
  'goruldu',
];

@Injectable()
export class MessageCleaningService {
  clean(rawText: string): string {
    let text = rawText
      .replace(/[^\p{L}\p{N}\s.'-]/gu, ' ')
      .toLocaleLowerCase('tr-TR')
      .replace(/\s+/g, ' ')
      .trim();

    for (const term of NOISE_TERMS) {
      text = text.replace(new RegExp(`(^|\\s)${this.escapeRegExp(term)}(?=\\s|$)`, 'gu'), ' ');
    }

    return text
      .replace(/\s+/g, ' ')
      .trim()
      .toLocaleUpperCase('tr-TR');
  }

  private escapeRegExp(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
