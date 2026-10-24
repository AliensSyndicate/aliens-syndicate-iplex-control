# Rollback — seis conjuntos do catálogo (23/10/2026)

Deploy autorizado pelo usuário: Functions `player`, `manager`, `processIptvSyncJobTrigger`, `recoverIptvJobs`
(codebase `iplex-gestor`) e regras do Firestore. Mudança aditiva: novos dados em `catalogs/{versão}/{meta,sets,deltas}`;
nada existente é apagado ou alterado (o JSON do Storage continua sendo gravado e lido).

## Estado anterior (antes do deploy)
Revisões Cloud Run em produção (região us-central1):

| Função | Revisão anterior |
|---|---|
| manager | manager-00012-xuh |
| player | player-00006-tet |
| processIptvSyncJobTrigger | processiptvsyncjobtrigger-00009-wok |
| recoverIptvJobs | recoveriptvjobs-00009-tan |

Regras do Firestore anteriores: ruleset `projects/iplex-2c8fc/rulesets/4101f06a-0f5c-40fd-8ff5-3b1a06599a5d`
(cópia do conteúdo em `firestore.rules.deployed`, idêntica ao commit `e25129f`).
Backup do Firestore: `gs://iplex-2c8fc-firestore-backups/pre-deploy-20261023-catalog-sets/`.

## Reverter as Functions (instantâneo, sem rebuild)
```bash
for pair in manager=manager-00012-xuh player=player-00006-tet processiptvsyncjobtrigger=processiptvsyncjobtrigger-00009-wok recoveriptvjobs=recoveriptvjobs-00009-tan; do
  gcloud run services update-traffic "${pair%%=*}" --region us-central1 --project iplex-2c8fc --to-revisions "${pair##*=}=100"
done
```

## Reverter as regras
```bash
cp docs/IPTV/rollback_2026-10-23/firestore.rules.deployed /tmp/firestore.rules && firebase deploy --only firestore:rules --project iplex-2c8fc
```
(ou reaplicar o ruleset 4101f06a… no console).

## Observações
- Os documentos `catalogs/*/{meta,sets,deltas}` ficam inertes para o código antigo.
- A prova do parser Xtream passou a `parser-7`: a primeira sincronização de cada fonte Xtream reconstrói o catálogo uma vez.

## Atualização (impressão digital de permissões no manifesto)
Revisões anteriores a este segundo deploy (ainda com os seis conjuntos, sem `viewerKey`): manager-00013-xiw, player-00007-mil.
```bash
for pair in manager=manager-00013-xiw player=player-00007-mil; do
  gcloud run services update-traffic "${pair%%=*}" --region us-central1 --project iplex-2c8fc --to-revisions "${pair##*=}=100"
done
```
