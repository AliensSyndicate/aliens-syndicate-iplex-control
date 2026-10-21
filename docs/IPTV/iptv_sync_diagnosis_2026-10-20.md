# Sincronização IPTV — diagnóstico, correções e validação (20/10/2026)

Sem deploy, commit ou push. O projeto de referência (Dream+TV) foi usado somente para leitura.

## 1. Causa da falha em produção

O código **implantado** em `iplex-2c8fc` (codebase `iplex-gestor`) foi executado localmente contra as mesmas entradas e falha em dois pontos, antes de qualquer item do catálogo ser gravado:

1. **Resolução DNS fixada** — no Node ≥ 20 o `lookup` é chamado com `{all: true}` (happy eyeballs) e precisa devolver uma lista; a versão implantada devolve um endereço único e a conexão aborta com `ERR_INVALID_IP_ADDRESS`.
2. **Transação de publicação** — lê documentos depois de escrever; o Firestore rejeita (`all reads must be executed before all writes`). O job termina como `catalog-sync-failed`, com 1 tentativa e **sem log útil**, e o Control mostrava apenas uma mensagem genérica.

Ambos já estão corrigidos no código local. **A correção só chega à produção com deploy das funções.**

## 2. Como o Dream+TV sincroniza (análise do APK, somente leitura)

- O aplicativo é um shell WebView; a interface e o parser IPTV ficam no site remoto do produto, não no APK.
- A ponte nativa faz **um GET simples por recurso** (`OkHttpClient` padrão, sem cabeçalhos especiais) e devolve o corpo bruto para o JavaScript.
- Para listas grandes, o **dispositivo baixa** o arquivo (`HttpURLConnection`) e **envia por upload multipart** ao servidor do produto: o servidor nunca acessa o provedor diretamente, evitando bloqueio de IPs de nuvem.
- Código proprietário: **nada foi copiado**. Reaproveitados apenas os padrões: um download por URL, User-Agent de player (`okhttp`) como alternativa, e a recomendação de download pelo dispositivo + upload (item 9).

## 3. Mudanças no backend (`functions/`)

| Área | Arquivo | Mudança |
|---|---|---|
| Download | `src/catalog.ts` | `createProviderFetch`: redirecionamentos, gzip/deflate/br, charset com fallback Windows‑1252, fallback de User‑Agent em 401/403, limites (64 MB, 30 s ocioso, 180 s total, 100 000 itens), erros classificados (`invalid-credentials`, `provider-rate-limited`, `http-<status>`, `tls-certificate`, `host-not-found`, `connection-failed`, `provider-time-budget`, `download-failed`, `catalog-too-large`) e log `fetch-ok`/`fetch-failed` só com host |
| M3U | `src/catalog.ts` | `parseM3uDetailed`: tolerante (pula entradas inválidas, deduplica por URL), classifica canal/filme/série por `type`, caminho `/live|movie|series/` ou extensão; agrupa episódios `SxxEyy` em uma série com temporadas |
| Xtream | `src/catalog.ts`, `src/iptv_adapters.ts` | linhas malformadas/duplicadas ignoradas; respostas vazias/`[]`/HTML classificadas; 1 nova tentativa por ação; 400/404/405/501 = tipo vazio; episódios buscados sob demanda (`get_series_info`) com cache de 6 h em Storage |
| Ingestão | `src/iptv_ingestion.ts` | um download por URL e sincronização (detecção, validação e extração compartilham) |
| Reprodução | `src/iptv_sync.ts`, `src/iptv_catalog_access.ts` | índice de streams **criptografado** (AES‑256‑GCM) em `stream_index/`; a TV resolve canal/filme/episódio sem baixar a lista de novo |
| Estado | `src/iptv_sync.ts` | `channelCount`/`movieCount`/`seriesCount`, `errorReason` técnico (sem credenciais), 400/404/410 definitivos (sem novas tentativas) |
| Remoção | `src/iptv_sources.ts`, `src/iptv_cleanup.ts` | índice de streams removido com a fonte |
| Testes | `package.json` | integração com `--test-concurrency=1` (os arquivos disputavam locks do emulador e falhavam com `Transaction lock timeout`) |

## 4. Control (Flutter)

- `iptv_page.dart` e `iptv_source_card.dart`: estados reais — sincronizando, **nova tentativa agendada**, pronto e erro com mensagem específica, “catálogo anterior preservado” e detalhe técnico.
- Contagem de canais, filmes e séries após a sincronização.
- Textos novos em pt/en/es.

## 5. Web e App

- **Web**: `catalogStore.categories()` agrupa a mesma categoria vinda de várias fontes (antes apareciam chips duplicados). Nenhuma mudança de contrato.
- **App Samsung**: nenhuma mudança.

## 6. Testes

| Suíte | Resultado |
|---|---|
| Backend unitários (`npm run check`) | 88/88 |
| Regras (emulador) | 14/14 |
| Integração (emulador, inclui `iptv_sync_http`) | 67/67 |
| `flutter analyze` / `flutter test` | limpo / 238/238 |
| Web `npm test` / `tsc -b` | 164/164 / ok (lint: 0 erros; 14 avisos preexistentes em arquivos não alterados) |

Servidor controlado (`test/support/fake_iptv_server.ts`, HTTP real, sem mocks de `fetch`): Xtream válido, M3U Plus válido (gzip, Windows‑1252, redirecionamento, filtro por cliente), credenciais erradas em 4 formatos, servidor indisponível/500/404, lento, interrompido (1× recupera, 2× agenda nova tentativa), vazio, 60 000 itens, acima do limite, ressincronização com IDs estáveis, troca de senha, remoção.

## 7. Evidência com listas reais (internet, emuladores, trigger real)

| Fonte | Resultado |
|---|---|
| Lista M3U pública de Portugal | 476 canais em 1,5 s |
| Índice M3U global | 11 365 itens (11 364 canais, 1 filme) em ~1,1 s |
| Xtream apontado para servidor que não é Xtream | `provider-unavailable (http-404)`, definitivo |
| Host inexistente | `provider-unavailable (host-not-found)`, com novas tentativas |

## 8. Web consulta e reproduz o catálogo

Pela callable `player` (TV pareada, perfil com PIN): espaços listados, 46 categorias distintas, busca por título. Reprodução na rota `/assistir`: canal `+MaisUm (720p)` tocando em 1280×720.

Os canais da RTP não tocaram **no navegador**: a URL é resolvida corretamente (`https`, servidor alcançável), mas o provedor não envia cabeçalho CORS, que o hls.js exige; são também streams marcados “Not 24/7”. Limitação da fonte, não do iPlex; o AVPlay da Samsung não aplica CORS.

## 9. Pendências que exigem provedor real

- Xtream real com credenciais autorizadas (validado apenas no servidor controlado).
- Fonte real do usuário em produção, após o deploy.
- Provedores que bloqueiam IPs de nuvem: recomendado o modelo de download no dispositivo + upload autenticado (padrão observado no Dream+TV), não implementado.
- Reprodução na Samsung de canal da fonte real (a TV foi validada na integração anterior com o mesmo contrato).

## 10. Riscos de publicação

- **Deploy obrigatório** do codebase de funções; sem ele a produção continua falhando.
- Fontes M3U existentes só ganham o índice de streams na primeira sincronização após o deploy; até lá a reprodução usa o caminho antigo (baixa a lista).
- Memória da função de sincronização com listas próximas de 64 MB/100 000 itens; acima disso o erro é explícito (`catalog-too-large`).
- `series_cache/` cresce por série consultada (TTL lógico de 6 h); considerar regra de ciclo de vida no bucket.
- Rollback: reimplantar a versão anterior das funções; os documentos novos (`errorReason`, contagens, `stream_index/`) são ignorados pelo código antigo.

## Atualização — finalização (20/10/2026, noite)

- **Produção reproduzida de novo**: os 14 jobs recentes de `iplex-2c8fc` estão em `catalog-sync-failed` (1 tentativa). O código publicado (18/10) falha nas mesmas entradas com “Firestore transactions require all reads to be executed before all writes”; o local conclui (476 canais por URL, 2 por arquivo).
- **Novo defeito encontrado e corrigido (DNS)**: o código local fixava só o primeiro endereço resolvido. Com um registro AAAA primeiro e sem saída IPv6 (padrão do Cloud Run), a conexão falhava. Agora todos os endereços verificados contra SSRF são oferecidos, IPv4 primeiro (`pinnedLookup`, `createProviderFetch`). Teste de regressão por nome de host (`localhost` → `::1`, `127.0.0.1`).
- **Fallback Xtream → M3U Plus** (`iptv_adapters.ts`): se o `player_api.php` falha por HTTP de erro, resposta inesperada, JSON inválido, download interrompido ou tempo ocioso, a conta é lida de `get.php?type=m3u_plus&output=ts` no mesmo servidor. Nunca em credencial inválida, limite de taxa, host inseguro/inexistente, TLS ou tamanho. Se a exportação responder 401/403, vale `invalid-credentials`; se falhar de outro modo, o erro original da API é mantido. Canais e filmes mantêm os IDs da API; a reprodução usa o índice selado (sem depender da API); quando a API volta, o índice antigo é apagado. Log `iptv-xtream m3u-plus-fallback` só com código e motivo.
- **Cadeia validada nos emuladores**: Control (script contra `manager` e regras) → trigger → Firestore/Storage → `player` → iPlex Web: arquivo (6 itens), M3U real (476 canais), Xtream com API em 503 (2 canais, 2 filmes, 1 série, URLs de canal/filme/episódio resolvidas), senha errada (`invalid-credentials`, sem catálogo publicado) e reprodução de canal real (1280×720). A TV Samsung estava desligada (sem resposta em 26101/8001): não validada nesta rodada.
- **App Check (sem alterar configuração)**: as 35 falhas de 19/10 às 14h vieram do build de debug do Control antes do registro do token de debug (registrado às 14:56). Depois disso, as falhas do aparelho aparecem em pares a 3 s: o Control renovava só o token de login ao receber `unauthenticated` e repetia a chamada com o mesmo token de App Check vencido/provisório. Corrigido em `lib/core/data/firebase_repository.dart` (renova também o token de App Check antes da nova tentativa; o servidor continua verificando). Não validado contra produção. O Web publicado chama a `manager` (com App Check); o Web local usa a `player`.
- Plano de implantação: `docs/Firebase/deploy_plan_2026-10-20.md`.
