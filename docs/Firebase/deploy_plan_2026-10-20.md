# Plano de implantação coordenada — iplex-2c8fc (preparado em 20/10/2026)

**Nada deste plano foi executado.** Cada etapa precisa de aprovação explícita. App Check fica como está (enforcement e prazos inalterados).

## 1. Estado publicado × local

| Peça | Publicado | Local | Diferença |
|---|---|---|---|
| Functions `iplex-gestor` | 18/10 18:35–18:38 UTC | este repositório | 12 módulos novos (`player`, `play_requests`, `parental`, `play_billing`, `device_identity`, `family_*`, `iptv_adapters`, `iptv_detection`, `iptv_errors`, `account_identity`, `content_audience`); ~1 600 linhas alteradas em `service`, `catalog`, `iptv_sync`, `iptv_catalog_access`, `iptv_ingestion`, `index`, `iptv_workspace`, `iptv_sources` |
| Funções exportadas | 9 | 11 | **novas:** `player` (callable, sem App Check, credencial de TV) e `playBillingNotifications` (Pub/Sub); `manager` passa de 256 MiB para 1 GiB, `cpu:1`, `concurrency:8` |
| Dependências | — | — | `google-auth-library` (novo, cobrança Play) |
| `iplexWebTmdb` (`iplex-web`) | 20/10 12:50 UTC | sem mudança local depois disso | nenhuma |
| Regras Firestore | ruleset `544a1b8e…` (19/10 13:38) | `firestore.rules` | TV perde leitura direta de família/catálogo (só via `player`); `credentialVersion` exigido quando o dispositivo tem um; `commands` (controle remoto) removido; `play_requests`, `app_config`, `play_purchases` adicionados |
| Regras Storage | ruleset `0c7ee16b…` | `storage.rules` | só uma linha em branco |
| Índices | 18 compostos | 18 compostos | iguais; local acrescenta **6 TTL** (`identity_attempts`, `link_tokens`, `device_pairing_sessions`, `device_pairing_codes`, `player_requests`, `play_requests` por `expireAt`) |
| Hosting (Web) | 20/10 13:20 UTC — chama `manager` com App Check | chama `player` | precisa do `player` publicado antes |
| Secret `IPTV_CREDENTIAL_KEY` | existe (17/10) | mesmo nome | sem rotação (rotacionar invalidaria fontes salvas) |

Correções de sincronização incluídas: resolução DNS com todos os endereços (IPv4 primeiro), transação de publicação com leituras antes das escritas, download robusto, parsers tolerantes, fallback Xtream → `get.php?type=m3u_plus` (só quando a API falha sem ser por credencial), índice selado de streams, erros com motivo técnico. Ver `docs/IPTV/iptv_sync_diagnosis_2026-10-20.md`.

## 2. Pré-requisitos (bloqueiam o deploy)

1. Aprovação explícita por etapa.
2. `playBillingNotifications`: **fora deste deploy** até o tópico RTDN do Play e a conta de serviço estarem configurados. Publicar só as funções listadas no passo 4.2.
3. Build de release do Web (`npm run build`) com a configuração de produção revisada.
4. Janela com baixo uso (a TV recarrega o Web na próxima abertura).

## 3. Backup (antes de qualquer etapa)

```bash
gcloud firestore export gs://iplex-2c8fc-firestore-backups/pre-deploy-$(date +%Y%m%d-%H%M) --project iplex-2c8fc
```
- Código publicado das funções: já guardado pelo GCF em `gs://gcf-v2-sources-59148444884-us-central1/<função>/function-source.zip`; copiar para `gs://iplex-2c8fc-firestore-backups/functions-2026-10-18/`.
- Regras: anotar os rulesets ativos (`544a1b8e-679c-4e1a-9662-ba3001315bb7`, `0c7ee16b-dadf-44a8-a50e-d0921333bd3e`).
- Hosting: anotar a versão ativa (`firebase hosting:channel:list` / console → Hosting → histórico de versões).

## 4. Ordem de implantação

1. **Verificação local final** — `npm --prefix functions run check`; emuladores com `test:rules` e `test:integration`; `flutter analyze && flutter test`; Web `npm test && npx tsc -b`.
2. **Functions (Control)** — só as necessárias:
   ```bash
   firebase deploy --project iplex-2c8fc --only functions:iplex-gestor:manager,functions:iplex-gestor:player,functions:iplex-gestor:processIptvSyncJobTrigger,functions:iplex-gestor:recoverIptvJobs,functions:iplex-gestor:cleanupIptv,functions:iplex-gestor:deliverIptvNotification,functions:iplex-gestor:recoverIptvNotifications,functions:iplex-gestor:purgeDeletedAccounts,functions:iplex-gestor:synchronizeCatalogs
   ```
   Verificar: `gcloud functions list` mostra `player`; no Control, “Sincronizar” numa fonte M3U → job `completed`, log `iptv-sync completed` com contagens; nenhuma URL/senha nos logs.
3. **Hosting (Web)** — no repositório Web: `npm run build && firebase deploy --project iplex-2c8fc --only hosting`. Verificar: TV/navegador pareia, lista espaços, abre catálogo e reproduz um canal.
4. **Regras e índices** — no Control: `firebase deploy --project iplex-2c8fc --only firestore:rules,firestore:indexes,storage`. Só depois do passo 3 (as regras removem leituras diretas que o Web antigo usa).
5. **Control (app)** — build de release para testadores (Play interno / TestFlight). Builds antigos continuam funcionando com o backend novo, exceto a tela de controle remoto removida.
6. **Samsung** — sem novo pacote: o shell carrega o Web publicado. Abrir a TV, confirmar pareamento existente e reprodução.

## 5. Verificações pós-deploy (30 min)

- Logs `manager`/`player`/`processIptvSyncJobTrigger` sem `ERROR`; `iptv-sync failed` com `reason` legível.
- `iptv_sync_jobs` novos em `completed`; fontes antigas em `error` voltam a `ready` após “Sincronizar” (o erro antigo `catalog-sync-failed` não tem nova tentativa automática).
- Taxa de 401 da `manager` igual ou menor que antes.

## 6. Rollback

| Peça | Como voltar |
|---|---|
| Functions | redeploy a partir do código guardado (zip do GCF de 18/10, descompactado) com o mesmo `--only`; `player` pode ficar (não é chamado pelo Web antigo) ou ser removida com `firebase functions:delete player` |
| Hosting | console → Hosting → versão anterior → “Rollback”, ou `firebase hosting:clone iplex-2c8fc@<versão> iplex-2c8fc:live` |
| Regras | republicar os rulesets anotados (console → Regras → histórico) |
| Índices/TTL | remover as políticas TTL no console (documentos já apagados não voltam — são tokens expirados) |
| Dados | campos novos (`errorReason`, contagens, `stream_index/`, `series_cache/`) são ignorados pelo código antigo; restaurar o export só em último caso |

## 7. Impactos em usuários e dados existentes

- **Catálogos IPTV**: nenhum catálogo foi publicado em produção (`catalogs` vazio), então não há favoritos/progresso de itens IPTV a perder. As 3 fontes em `error` precisam de “Sincronizar” após o deploy.
- **TVs pareadas**: continuam válidas (o `credentialVersion` só é exigido de dispositivos que já o têm). O Web antigo em cache passa a falhar nas leituras diretas após o passo 4 até recarregar.
- **Control antigo**: controle remoto deixa de existir no backend.
- **TTL**: documentos expirados das 6 coleções efêmeras passam a ser apagados automaticamente.
- **Custo**: `manager` e `player` com 1 GiB; sincronização de listas grandes usa até 1 GiB / 540 s.
- **Fallback Xtream**: contas cuja API falha passam a sincronizar pela lista M3U Plus; canais e filmes mantêm os mesmos IDs da API; séries mudam de ID entre os dois caminhos (agrupadas por título).
- **App Check**: sem mudança de configuração. O Web deixa de chamar a `manager` (passa à `player`).

## 8. Execução — 21/10/2026 (autorizada)

| Etapa | Resultado |
|---|---|
| Backup | `gs://iplex-2c8fc-firestore-backups/pre-deploy-20261021T1018Z/` — export Firestore (`SUCCESSFUL`, 69 docs), zips das 9 funções publicadas, regras e índices anteriores. Hosting anterior: versão `1672b64fbc1d2db6`. Storage vazio. |
| Functions 10:22 UTC | `player` criada; `manager`, `processIptvSyncJobTrigger`, `recoverIptvJobs`, `cleanupIptv`, `deliverIptvNotification`, `recoverIptvNotifications`, `purgeDeletedAccounts`, `synchronizeCatalogs` atualizadas. `playBillingNotifications` **não** publicada. Todas `ACTIVE`; `manager` continua exigindo App Check. |
| Hosting 10:32 UTC | versão `0b10e7fafc31b163` (Web chama `player`; sem segredos no `dist`). Carrega e gera código de pareamento. |
| Regras/índices 10:35 UTC | Firestore ruleset `4fd9e1ca-5d70-4510-8785-538557715ff9`; índices iguais + 6 TTL (`CREATING`); Storage sem mudança. Sem login: 403 em famílias, fontes, segredos, catálogos e jobs. |
| Sincronização real | lista pública de teste (`c13f25…`, sem credenciais) no espaço IPTV do dono: `ready`, 476 canais, ≤ 4 s; ressincronização com a mesma versão, 2 jobs `completed`, sem duplicação. |
| Fontes antigas | `94a974…` (url) e `db6e36…` (m3u): reprocessadas, agora `provider-unavailable (host-not-found)` — o domínio do provedor não existe (NXDOMAIN também no 8.8.8.8). `3d03cd…`: órfã (família, fonte e segredo inexistentes), não recuperável. |
| Pendente | pareamento do Web de produção (confirmação pelo Control: celular bloqueado), consulta/reprodução pelo Web de produção, Samsung (desligada), build de release do Control (sem keystore). |

Rollback não foi necessário.

## 9. Validação ponta a ponta com S10 e Samsung — 21/10/2026 (autorizada)

| Achado | Correção | Publicação |
|---|---|---|
| `finishDevicePair` → HTTP 500 sem log: a conta de serviço das funções não podia assinar custom tokens (`iam.serviceAccounts.signBlob`) | `roles/iam.serviceAccountTokenCreator` concedido à conta `59148444884-compute@…` **somente sobre ela mesma**; erros inesperados das callables passam a ser registrados (sem URLs/tokens) | IAM 10:53 UTC; `manager`+`player` 10:55 UTC |
| Conta sem família (espaço `personalIptv`): TV vinculada ficava em "Perfil indisponível" (sem perfis) | `linkDevice` cria o perfil `admin` do dono no primeiro vínculo de TV a um espaço pessoal | `manager`+`player` 11:15 UTC |
| Web gerava novo código de pareamento a cada mudança de visibilidade/rede (o código confirmado no Gestor deixava de valer) | pedido de pareamento depende só da identidade da plataforma | Hosting `d4edba4aa118497b` 11:43 UTC |
| Web no navegador não reproduzia em produção: o Clappr compila templates com `Function()`, bloqueado pela CSP (sem `unsafe-eval`, exigência Samsung) | adaptador `<video>` + hls.js 1.7.3 (sem worker), Clappr removido | Hosting `d4edba4aa118497b` |
| Control: navegador rotulado "Android TV"; estado vazio de perfis sem ação | rótulo "Navegador"; botão real "Novo perfil de visualização" | build de teste instalado no S10 (sem loja) |

Resultados em produção: Control (S10, App Check `VALID`) → pareamento da Samsung e do navegador → perfil do dono → catálogo (476 canais) no Web e na TV → **Samsung reproduziu** (+MaisUm, pedido `started`, `player.open/getTracks/pause/play ok`) → **navegador reproduziu** após a publicação (1280×720, sem violação de CSP). Rollback do Hosting: versão `0b10e7fafc31b163`.
