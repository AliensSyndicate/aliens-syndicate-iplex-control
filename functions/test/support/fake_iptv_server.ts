/**
 * Controlled IPTV provider for integration tests (real HTTP on 127.0.0.1).
 * Speaks the Xtream Codes player_api.php contract and serves M3U / M3U Plus
 * lists with the quirks of real providers. Fictitious data only.
 */
import http from 'node:http';
import zlib from 'node:zlib';
import type {AddressInfo} from 'node:net';

export type FakeProvider = {
  base: string;
  hits: Record<string, number>;
  credentials: {username: string; password: string};
  mode: {auth: 'ok' | 'zero' | 'empty' | 'html'; seriesInfo: boolean; flaky: number; latin1: boolean; apiStatus: number; m3uPlus: boolean};
  close: () => Promise<void>;
};

export function m3uPlus(base: string, u: string, p: string): string {
  return [
    '#EXTM3U x-tvg-url="http://example.invalid/epg.xml"',
    '#EXTINF:-1 tvg-id="news.br" tvg-name="Canal Notícias" tvg-logo="http://example.invalid/n.png" group-title="Notícias",Canal Notícias',
    `${base}/live/${u}/${p}/101.ts`,
    '#EXTINF:-1 tvg-id="news.br" group-title="Notícias",Canal Notícias (duplicado)',
    `${base}/live/${u}/${p}/101.ts`,
    '#EXTINF:-1 group-title="Antigos",Canal RTMP',
    'rtmp://example.invalid/live/stream',
    '#EXTINF:-1 group-title="Quebrado",Linha sem URL válida',
    'http://[bad',
    '#EXTINF:-1 tvg-name="Canal Sem Título" group-title="Esportes",',
    `${base}/live/${u}/${p}/102.ts`,
    '#EXTINF:-1 tvg-rating="16" group-title="Filmes | Ação",Missão Fictícia (2021)',
    `${base}/movie/${u}/${p}/201.mkv`,
    '#EXTINF:-1 tvg-rating="L" group-title="Filmes | Infantil",Aventura no Parque (2019)',
    `${base}/movie/${u}/${p}/202.mp4`,
    '#EXTINF:-1 group-title="Séries | Drama",Série Exemplo S01 E01 - Começo',
    `${base}/series/${u}/${p}/301.mkv`,
    '#EXTINF:-1 group-title="Séries | Drama",Série Exemplo S01 E02 - Meio',
    `${base}/series/${u}/${p}/302.mkv`,
    '#EXTINF:-1 group-title="Séries | Drama",Série Exemplo S02E01 Retorno',
    `${base}/series/${u}/${p}/303.mkv`,
    '',
  ].join('\r\n');
}

export async function startFakeProvider(): Promise<FakeProvider> {
  const state = {
    hits: {} as Record<string, number>,
    credentials: {username: 'assinante', password: 'senha-1'},
    mode: {auth: 'ok', seriesInfo: true, flaky: 0, latin1: false, apiStatus: 0, m3uPlus: true} as FakeProvider['mode'],
  };
  let base = '';
  const json = (res: http.ServerResponse, body: unknown) => { res.writeHead(200, {'content-type': 'application/json'}); res.end(JSON.stringify(body)); };
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', base);
    const key = `${url.pathname}${url.searchParams.get('action') ? `?${url.searchParams.get('action')}` : ''}`;
    state.hits[key] = (state.hits[key] ?? 0) + 1;
    const authorized = url.searchParams.get('username') === state.credentials.username && url.searchParams.get('password') === state.credentials.password;
    if (url.pathname === '/player_api.php') {
      // API down or blocked while the M3U Plus export still answers.
      if (state.mode.apiStatus) { res.writeHead(state.mode.apiStatus); res.end(); return; }
      if (!authorized || state.mode.auth !== 'ok') {
        if (state.mode.auth === 'empty') { res.writeHead(200); res.end(''); return; }
        if (state.mode.auth === 'html') { res.writeHead(200, {'content-type': 'text/html'}); res.end('<html><body>Painel</body></html>'); return; }
        return json(res, {user_info: {auth: 0, status: 'Disabled'}});
      }
      switch (url.searchParams.get('action')) {
        case null: return json(res, {user_info: {auth: 1, status: 'Active', exp_date: String(Math.floor(Date.now() / 1000) + 86400)}, server_info: {url: '127.0.0.1'}});
        case 'get_live_categories': return json(res, [{category_id: '1', category_name: 'Notícias'}, {category_id: '2', category_name: 'Infantil'}]);
        case 'get_live_streams': return json(res, [
          {stream_id: 101, name: 'Canal Notícias', category_id: '1', epg_channel_id: 'news.br', stream_icon: 'https://img.example.com/logos/noticias.png'},
          {stream_id: 102, name: 'Canal Infantil', category_id: '2', age: 'L'},
          {stream_id: 102, name: 'Canal Infantil (repetido)', category_id: '2'},
          {name: 'Linha sem stream_id', category_id: '1'},
          {stream_id: 103, name: 'x'.repeat(400), category_id: '1'},
        ]);
        case 'get_vod_categories': return json(res, [{category_id: '10', category_name: 'Filmes'}]);
        case 'get_vod_streams': return json(res, [
          {stream_id: 201, name: 'Missão Fictícia', category_id: '10', container_extension: 'mkv', year: '2021', rating: '7.1', added: '1700000000', stream_icon: 'https://img.example.com/p/missao.jpg'},
          {stream_id: 202, name: 'Aventura no Parque', category_id: '10', container_extension: 'mp4', age: 'L', added: '1710000000', stream_icon: 'https://img.example.com/p/aventura.jpg?token=segredo'},
        ]);
        case 'get_series_categories': return json(res, [{category_id: '20', category_name: 'Séries'}]);
        case 'get_series': return json(res, [{series_id: 301, name: 'Série Exemplo', category_id: '20', plot: 'Uma série fictícia.', last_modified: '1705000000', cover: 'http://img.example.com/s/serie.jpg'}]);
        case 'get_series_info':
          if (!state.mode.seriesInfo) { res.writeHead(501); res.end(); return; }
          return json(res, {seasons: [{id: 1, name: 'Temporada 1', season_number: 1, episode_count: 2}], info: {name: 'Série Exemplo'},
            episodes: {'1': [{id: '3011', title: 'Começo', episode_num: 1, season: 1, container_extension: 'mkv'}, {id: '3012', title: 'Meio', episode_num: 2, season: 1, container_extension: 'mkv'}]}});
        default: res.writeHead(404); res.end(); return;
      }
    }
    if (url.pathname === '/get.php') {
      if (!state.mode.m3uPlus) { res.writeHead(404); res.end(); return; }
      if (!authorized) { res.writeHead(403); res.end('forbidden'); return; }
      const body = m3uPlus(base, state.credentials.username, state.credentials.password);
      res.writeHead(200, {'content-type': 'audio/x-mpegurl', 'content-encoding': 'gzip'});
      res.end(zlib.gzipSync(state.mode.latin1 ? Buffer.from(body, 'latin1') : Buffer.from(body, 'utf8')));
      return;
    }
    if (url.pathname === '/redirect.m3u') { res.writeHead(302, {location: '/get.php' + url.search}); res.end(); return; }
    if (url.pathname === '/player-only.m3u') {
      // Panels that only answer known player clients (first UA refused).
      if (!/okhttp|VLC/.test(req.headers['user-agent'] ?? '')) { res.writeHead(403); res.end(); return; }
      res.writeHead(200); res.end(m3uPlus(base, 'a', 'b')); return;
    }
    if (url.pathname === '/flaky.m3u') {
      if (state.mode.flaky > 0) {
        state.mode.flaky--;
        res.writeHead(200, {'content-length': '100000'});
        res.write('#EXTM3U\n#EXTINF:-1,Parcial\n');
        setTimeout(() => res.destroy(), 20);
        return;
      }
      res.writeHead(200); res.end(m3uPlus(base, 'x', 'y')); return;
    }
    if (url.pathname === '/big.m3u') {
      const count = Number(url.searchParams.get('n') ?? 60000);
      res.writeHead(200, {'content-type': 'application/x-mpegURL'});
      const lines = ['#EXTM3U'];
      for (let i = 0; i < count; i++) lines.push(`#EXTINF:-1 tvg-id="c${i}" group-title="Grupo ${i % 50}",Canal ${i}`, `${base}/live/u/p/${i}.ts`);
      res.end(lines.join('\n'));
      return;
    }
    if (url.pathname === '/empty.m3u') { res.writeHead(200); res.end('#EXTM3U\n'); return; }
    if (url.pathname === '/slow.m3u') { res.writeHead(200); res.write('#EXTM3U\n'); return; /* never ends */ }
    if (url.pathname === '/error500.m3u') { res.writeHead(500); res.end('boom'); return; }
    res.writeHead(404); res.end();
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return Object.assign(state, {base, close: () => new Promise<void>(resolve => { server.closeAllConnections(); server.close(() => resolve()); })});
}
