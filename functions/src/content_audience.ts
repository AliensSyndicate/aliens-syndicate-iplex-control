/**
 * Conservative kids classification. A kids profile sees an item only when it is
 * positively identified as children's content:
 *  1. An explicit provider age rating decides first: only ratings suitable for
 *     young children qualify; any other explicit rating excludes the item, even
 *     inside a kids category.
 *  2. Without a rating, only categories that are explicitly for children qualify.
 *  3. Adult signals in title or category always exclude.
 * Anything else (genres such as "Animação"/"Family", missing data) is excluded.
 * The administrator cannot override this result.
 */
export type Audience = 'kids' | 'general';
const fold = (value: unknown) => String(value ?? '').normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

const ADULT = /(^|[^a-z0-9])(xxx|adult[oa]?s?|adults?|porn\w*|erotic\w*|erotik\w*|hentai|playboy|sexy|18\s*\+|\+\s*18|for adults)([^a-z0-9]|$)/;
// Category names only (same as the TV's adult category labels): "Sexo" names a category, not a title.
const ADULT_CATEGORY = /(^|[^a-z0-9])sexo([^a-z0-9]|$)/;
const KIDS_CATEGORY = /(^|[^a-z0-9])(infantil|infantis|infantiles|kids?|criancas?|children|childrens|ninos|ninas|desenhos?( animados)?|dibujos( animados)?|cartoons?|toddlers?|preschool|pre-escolar|disney junior|disney jr|nick jr|nickelodeon junior|discovery kids|cartoon network|cartoonito|gloob|gloobinho|baby ?tv|zoomoo|tooncast)([^a-z0-9]|$)/;
// Ratings that mean "suitable for all ages / young children".
const KIDS_RATINGS = new Set(['l', 'livre', 'al', 'all', 'g', 'tv-y', 'tvy', 'tv-y7', 'tvy7', 'tv-y7-fv', 'tv-g', 'tvg', 'u', 'fsk 0', 'fsk0', 'pegi 3', 'pegi3', 'atp', 'apta', 'apta para todos', 'todos', 'tp', '0', '0+', '3', '3+', '6', '6+', '7', '7+']);

/** Parses provider age metadata; returns undefined when the field carries no rating. */
export function normalizeAgeRating(value: unknown): string | undefined {
  const text = fold(value).replace(/^(rated|classificacao|clasificacion|age|idade|edad)[:\s]*/, '').replace(/\s+anos?$|\s+years?$/, '').trim();
  return text && text.length <= 20 ? text : undefined;
}

/** Adult content (title/category signals or an 18 rating): hidden when a profile's
 * "conteúdo adulto" is off (administrator limit or the member's own preference). */
export function isAdultContent(item: {title?: string; category?: string; ageRating?: string; isAdult?: boolean}): boolean {
  // Marca explícita do provedor (Xtream `is_adult`): sinal adicional, nunca reduz a proteção.
  if (item.isAdult === true) return true;
  if (ADULT.test(fold(item.title)) || ADULT.test(fold(item.category)) || ADULT_CATEGORY.test(fold(item.category))) return true;
  const rating = normalizeAgeRating(item.ageRating);
  return rating !== undefined && /^(18|18\+|r18|nc-17|nc17|x|xxx|pegi 18|pegi18|fsk 18|fsk18)$/.test(rating);
}

export function classifyAudience(item: {title?: string; category?: string; ageRating?: string}): Audience {
  const title = fold(item.title), category = fold(item.category);
  if (ADULT.test(title) || ADULT.test(category) || ADULT_CATEGORY.test(category)) return 'general';
  const rating = normalizeAgeRating(item.ageRating);
  if (rating) return KIDS_RATINGS.has(rating) ? 'kids' : 'general';
  return KIDS_CATEGORY.test(category) ? 'kids' : 'general';
}
