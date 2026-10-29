/// Port of the TV's category de-para (aliens-syndicate-iplex-web
/// `src/services/catalog/categoryLabels.ts`): the Control groups the catalog
/// tabs exactly as the TV does. Changes go to the TV first and are copied
/// here with the same tables and rules.
///
/// Providers send dirty names: all caps, without accents ("AÇAO"), in another
/// language ("Action"), with a prefix ("FILMES | Ação") or adult variants.
/// [categoryLabel] returns the shown text (fixed, in Portuguese, sentence
/// case); names that become the same text are one category ([categoryKey]).
/// Every adult variant becomes exactly "Adulto".
library;

const adultLabel = 'Adulto';

final _adultName = RegExp(
  r'(^|[^a-z0-9])(adult[oa]?s?|xxx|\+\s?18|18\s?\+|er[óo]tic[oa]s?|porn[oô]?s?|sexo|sexy|hentai|playboy)([^a-z0-9]|$)',
  caseSensitive: false,
);

/// Adult category of the provider (any variant).
bool isAdultName(String name) =>
    _adultName.hasMatch(name) || name.trim() == adultLabel;

const _accents = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
  'ý': 'y',
  'ÿ': 'y',
};

String _stripAccents(String text) =>
    text.split('').map((c) => _accents[c] ?? c).join();

/// Comparison key: lower case, no accents, no punctuation (keeps "+").
String foldName(String name) =>
    _stripAccents(name.toLowerCase())
        .replaceAll('&', ' e ')
        .replaceAll(RegExp(r'[^a-z0-9+]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Folded key → shown text.
const _categoryTable = {
  'acao': 'Ação',
  'action': 'Ação',
  'accion': 'Ação',
  'acao e aventura': 'Ação e aventura',
  'action adventure': 'Ação e aventura',
  'aventura': 'Aventura',
  'adventure': 'Aventura',
  'animacao': 'Animação',
  'animation': 'Animação',
  'animacion': 'Animação',
  'animes': 'Animes',
  'anime': 'Animes',
  'desenho': 'Desenhos',
  'desenhos': 'Desenhos',
  'desenhos animados': 'Desenhos',
  'cartoon': 'Desenhos',
  'cartoons': 'Desenhos',
  'comedia': 'Comédia',
  'comedy': 'Comédia',
  'comedia romantica': 'Comédia romântica',
  'crime': 'Crime',
  'policial': 'Policial',
  'documentario': 'Documentário',
  'documentarios': 'Documentários',
  'documentary': 'Documentário',
  'documentaries': 'Documentários',
  'documental': 'Documentário',
  'drama': 'Drama',
  'dramas': 'Drama',
  'familia': 'Família',
  'family': 'Família',
  'fantasia': 'Fantasia',
  'fantasy': 'Fantasia',
  'ficcao cientifica': 'Ficção científica',
  'ficcao e fantasia': 'Ficção e fantasia',
  'ficcao fantasia': 'Ficção e fantasia',
  'youtube': 'YouTube',
  'sci fi': 'Ficção científica',
  'scifi': 'Ficção científica',
  'science fiction': 'Ficção científica',
  'ciencia ficcao': 'Ficção científica',
  'guerra': 'Guerra',
  'war': 'Guerra',
  'historia': 'História',
  'history': 'História',
  'historico': 'Histórico',
  'infantil': 'Infantil',
  'infantis': 'Infantil',
  'kids': 'Infantil',
  'children': 'Infantil',
  'criancas': 'Infantil',
  'musical': 'Musical',
  'musicais': 'Musical',
  'musica': 'Música',
  'music': 'Música',
  'misterio': 'Mistério',
  'mystery': 'Mistério',
  'romance': 'Romance',
  'romantico': 'Romance',
  'suspense': 'Suspense',
  'thriller': 'Suspense',
  'terror': 'Terror',
  'horror': 'Terror',
  'faroeste': 'Faroeste',
  'western': 'Faroeste',
  'biografia': 'Biografia',
  'biography': 'Biografia',
  'esporte': 'Esportes',
  'esportes': 'Esportes',
  'sport': 'Esportes',
  'sports': 'Esportes',
  'religioso': 'Religioso',
  'religiosos': 'Religiosos',
  'religiao': 'Religião',
  'gospel': 'Gospel',
  'nacional': 'Nacional',
  'nacionais': 'Nacionais',
  'brasileiro': 'Brasileiro',
  'brasileiros': 'Brasileiros',
  'lancamento': 'Lançamentos',
  'lancamentos': 'Lançamentos',
  'novos lancamentos': 'Lançamentos',
  'new releases': 'Lançamentos',
  'novidades': 'Novidades',
  'classicos': 'Clássicos',
  'classico': 'Clássicos',
  'legendado': 'Legendados',
  'legendados': 'Legendados',
  'dublado': 'Dublados',
  'dublados': 'Dublados',
  'novela': 'Novelas',
  'novelas': 'Novelas',
  'dorama': 'Doramas',
  'doramas': 'Doramas',
  'serie': 'Séries',
  'series': 'Séries',
  'series tv': 'Séries TV',
  'filme': 'Filmes',
  'filmes': 'Filmes',
  'movies': 'Filmes',
  '4k': '4K',
  'uhd': 'UHD',
  'uhd 4k': 'UHD 4K',
  '4k uhd': 'UHD 4K',
  'fhd': 'FHD',
  'hd': 'HD',
  'sem categoria': 'Sem categoria',
  'abertos': 'Canais abertos',
  'canais abertos': 'Canais abertos',
  'tv aberta': 'Canais abertos',
  'noticias': 'Notícias',
  'news': 'Notícias',
  'jornalismo': 'Notícias',
  'variedades': 'Variedades',
  'entretenimento': 'Entretenimento',
  'reality': 'Reality',
  'filmes e series': 'Filmes e séries',
  'canais de filmes': 'Filmes',
  'canais de esportes': 'Esportes',
  'premiere': 'Premiere',
  'amazon prime video': 'Amazon Prime Video',
  'prime video': 'Amazon Prime Video',
  'amazon': 'Amazon Prime Video',
  'apple tv+': 'Apple TV+',
  'apple tv': 'Apple TV+',
  'appletv+': 'Apple TV+',
  'appletv': 'Apple TV+',
  'crunchyroll': 'Crunchyroll',
  'discovery+': 'Discovery+',
  'discovery': 'Discovery+',
  'disney+': 'Disney+',
  'disney': 'Disney+',
  'globoplay': 'Globoplay',
  'hbo max': 'HBO Max',
  'max': 'Max',
  'hbo': 'HBO',
  'netflix': 'Netflix',
  'paramount+': 'Paramount+',
  'paramount': 'Paramount+',
  'star+': 'Star+',
  'star': 'Star+',
  'brasil paralelo': 'Brasil Paralelo',
  'especial de natal': 'Especial de Natal',
  'natal': 'Natal',
};

/// Word without accents → correct form (generic rule).
const _wordFixes = {
  'acao': 'ação',
  'aventura': 'aventura',
  'animacao': 'animação',
  'comedia': 'comédia',
  'documentario': 'documentário',
  'documentarios': 'documentários',
  'ficcao': 'ficção',
  'cientifica': 'científica',
  'serie': 'série',
  'series': 'séries',
  'musica': 'música',
  'familia': 'família',
  'historia': 'história',
  'historico': 'histórico',
  'noticias': 'notícias',
  'lancamento': 'lançamento',
  'lancamentos': 'lançamentos',
  'misterio': 'mistério',
  'religiao': 'religião',
  'classicos': 'clássicos',
  'criancas': 'crianças',
  'romantico': 'romântico',
  'romantica': 'romântica',
  'epico': 'épico',
  'epicos': 'épicos',
  'tematico': 'temático',
  'tematicos': 'temáticos',
  'atualidades': 'atualidades',
  'educacao': 'educação',
  'educativo': 'educativo',
  'cultura': 'cultura',
  'esportes': 'esportes',
  'variedade': 'variedade',
  'gastronomia': 'gastronomia',
  'turismo': 'turismo',
  'saude': 'saúde',
  'ciencia': 'ciência',
  'tecnologia': 'tecnologia',
  'pais': 'país',
  'paises': 'países',
  'juridico': 'jurídico',
  'policia': 'polícia',
};

const _acronyms = {
  'tv',
  'hd',
  'fhd',
  'uhd',
  'hbo',
  'dc',
  'sbt',
  'cnn',
  'bbc',
  'vod',
  'uk',
  'usa',
  'eua',
  'dj',
  'ufc',
  'nba',
  'nfl',
  'wwe',
  'mtv',
  'gnt',
  'rpc',
};

/// Brands written their own way inside names without a rule.
const _brandWords = {
  'youtube': 'YouTube',
  'reelshort': 'ReelShort',
  'hbo': 'HBO',
  'globoplay': 'Globoplay',
  'netflix': 'Netflix',
  'disney': 'Disney',
};
const _prefixes = {
  'filmes',
  'filme',
  'series',
  'serie',
  'canais',
  'canal',
  'movies',
  'vod',
  'tv',
  'categoria',
};

String _capitalize(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

/// Sentence case (like "Continuar assistindo"): first letter upper case, the
/// rest lower case; acronyms and brands kept.
String _sentenceCase(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[|_/\\·•:;\[\]{}()<>]+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—.]+|[\s\-–—.]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final words = cleaned.split(' ').where((w) => w.isNotEmpty).toList();
  // All caps (common in lists): only known acronyms or words with a digit
  // stay upper case.
  final allCaps = cleaned == cleaned.toUpperCase();
  final digit = RegExp(r'\d');
  return [
    for (final (index, original) in words.indexed)
      () {
        final folded = foldName(original);
        final fixed = _wordFixes[folded];
        if (fixed != null) return index == 0 ? _capitalize(fixed) : fixed;
        final table = _categoryTable[folded];
        if (table != null && RegExp(r'\d|\+').hasMatch(folded)) return table;
        // Short acronyms and brands (HBO, TV, UHD, 4K).
        final isAcronym = digit.hasMatch(original)
            ? original == original.toUpperCase()
            : original.length <= 3 &&
                  original == original.toUpperCase() &&
                  (!allCaps || _acronyms.contains(folded));
        if (isAcronym) return original;
        final brand = _brandWords[folded];
        if (brand != null) return brand;
        final lower = original.toLowerCase();
        return index == 0 ? _capitalize(lower) : lower;
      }(),
  ].join(' ');
}

/// Shown text of a category (fixed, translated and standardized).
String categoryLabel(String name) {
  final raw = name.trim();
  if (raw.isEmpty) return _categoryTable['sem categoria']!;
  if (isAdultName(raw)) return adultLabel;
  final folded = foldName(raw);
  final direct = _categoryTable[folded];
  if (direct != null) return direct;
  // "FILMES | AÇÃO", "Canais - Esportes": tries without generic prefixes.
  final parts = folded.split(' ');
  for (var i = 1; i < parts.length && _prefixes.contains(parts[i - 1]); i++) {
    final rest = _categoryTable[parts.skip(i).join(' ')];
    if (rest != null) return rest;
  }
  return _sentenceCase(raw);
}

/// Identity of the category: names that become the same text are one group.
String categoryKey(String name) => foldName(categoryLabel(name));
