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

const SKIP_PATTERNS = [
  /\btemiz\b/u,
  /\bteyit\b/u,
  /\bdevam\s*m[ıi]\b/u,
  /\bnas[ıi]l\b/u,
  /\bneresi\b/u,
  /\bhay[ıi]r\b/u,
  /\baynen\b/u,
  /\bbirazdan\b/u,
  /\bhaz[ıi]rlan/u,
  /\binan\b/u,
  /\bbahsediyor\b/u,
  /\bkonumunu\s+att[ıi]/u,
  /\bolmas[ıi]n\b/u,
  /\bpayla[şs]\b/u,
  /\bboş\s+bildirim/u,
  /\bolmayan\s+yer/u,
  /\badam\s+atmay/u,
  /\bilgilen/u,
];

@Injectable()
export class MessageCleaningService {
  shouldSkip(rawText: string): boolean {
    const text = this.normalizeForMatching(rawText);
    return SKIP_PATTERNS.some((pattern) => pattern.test(text));
  }

  clean(rawText: string): string {
    let text = this.normalizeForMatching(rawText);

    for (const term of NOISE_TERMS) {
      text = text.replace(new RegExp(`(^|\\s)${this.escapeRegExp(term)}(?=\\s|$)`, 'gu'), ' ');
    }

    return text
      .replace(/\s+/g, ' ')
      .trim()
      .toLocaleUpperCase('tr-TR');
  }

  isLikelyLocation(cleanedText: string): boolean {
    const words = cleanedText.split(/\s+/).filter(Boolean);
    return words.length >= 2 && words.length <= 10 && cleanedText.length <= 90;
  }

  private escapeRegExp(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private normalizeForMatching(rawText: string): string {
    return rawText
      .replace(/[^\p{L}\p{N}\s.'-]/gu, ' ')
      .toLocaleLowerCase('tr-TR')
      .replace(/\s+/g, ' ')
      .trim();
  }
}
