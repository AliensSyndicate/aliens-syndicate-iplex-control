import {test} from 'node:test';
import assert from 'node:assert/strict';
import {classifyAudience, normalizeAgeRating} from '../src/content_audience';
import {parseM3u, parseXtream} from '../src/catalog';

test('kids only when positively identified; explicit rating beats category; adult signals always exclude', () => {
  const kids = [
    {title: 'Peppa', category: 'Infantil'}, {title: 'Bluey', category: 'KIDS | Séries'}, {title: 'Canal', category: 'Desenhos Animados'},
    {title: 'Filme', category: 'Filmes', ageRating: 'L'}, {title: 'Movie', category: 'Movies', ageRating: 'TV-Y7'}, {title: 'Cartoon', category: 'Niños'},
  ];
  const general = [
    {title: 'Drama', category: 'Infantil', ageRating: '16'}, {title: 'XXX Night', category: 'Infantil'}, {title: 'Show', category: 'Kids +18'},
    {title: 'Animado', category: 'Animação'}, {title: 'Família', category: 'Family'}, {title: 'Sem dados', category: ''},
    {title: 'PG', category: 'Kids', ageRating: 'PG'}, {title: 'Kidnap', category: 'Thriller'}, {title: 'Filme', category: 'Filmes', ageRating: '12'},
  ];
  for (const item of kids) assert.equal(classifyAudience(item), 'kids', JSON.stringify(item));
  for (const item of general) assert.equal(classifyAudience(item), 'general', JSON.stringify(item));
  assert.equal(normalizeAgeRating('Classificação: 12 anos'), '12');
  assert.equal(normalizeAgeRating(''), undefined);
});

test('provider age metadata is captured from M3U attributes and Xtream rows', () => {
  const m3u = parseM3u('#EXTM3U\n#EXTINF:-1 tvg-rating="L" group-title="Filmes",Turma\nhttps://example.com/a.ts\n#EXTINF:-1 group-title="Filmes",Outro\nhttps://example.com/b.ts');
  assert.equal(m3u.items[0]!.ageRating, 'l');
  assert.equal(m3u.items[1]!.ageRating, undefined);
  const xtream = parseXtream([{name: 'A', stream_id: 1, age: 16}, {name: 'B', stream_id: 2, mpaa_rating: 'G'}, {name: 'C', stream_id: 3}], 'movie');
  assert.deepEqual(xtream.map(i => i.ageRating), ['16', 'g', undefined]);
});
