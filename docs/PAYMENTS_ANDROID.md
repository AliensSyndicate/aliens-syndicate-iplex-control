# Pagamentos Android — Google Play Billing

Estado em 19/10/2026. Regras permanentes em `AGENTS.md` §15.

## Arquitetura

```
App (in_app_purchase)            Backend (Cloud Functions)                 Google
─────────────────────            ─────────────────────────                 ──────
getPaymentsConfig ─────────────▶ app_config/payments (false se ausente)
queryProductDetails ─────────────────────────────────────────────────────▶ Play Billing
buyNonConsumable(obfuscatedAccountId) ───────────────────────────────────▶ Play Billing
purchaseStream: purchased ─────▶ verifyPlayPurchase ──────────────────────▶ subscriptionsv2.get
                                  ├ produto/plano/conta/família                ▲
                                  ├ families/{fid}/private/subscription        │
                                  └ acknowledge ───────────────────────────────┘
completePurchase (só após o backend)
                                 playBillingNotifications ◀── Pub/Sub ◀── RTDN
                                  └ relê subscriptionsv2 e reaplica o estado
```

| Peça | Arquivo |
|---|---|
| Flag, validação, RTDN, mapeamento de estado | `functions/src/play_billing.ts`, `functions/src/index.ts` |
| Abstração de loja (Google Play agora, iOS depois) | `lib/core/payments/store_billing.dart` |
| Controlador de checkout e flag no app | `lib/core/payments/subscription_checkout.dart` |
| Tela | `lib/features/manager/subscription_page.dart` |

## Identificadores

| Item | Valor |
|---|---|
| Pacote | `com.alienssyndicate.iplex_control` (configurável no backend por `PLAY_PACKAGE_NAME`) |
| Produto de assinatura | `iplex_playback` |
| Planos-base | `monthly` (P1M, renovação automática), `annual` (P1Y, renovação automática) |
| Ofertas | nenhuma (sem teste gratuito, sem promoções) |
| Tópico RTDN | `projects/iplex-2c8fc/topics/play-billing-notifications` |
| Conta de serviço das Functions | `59148444884-compute@developer.gserviceaccount.com` |

## Mapeamento de estado (Play → `subscription.status`)

| Play | iPlex | Reproduz? |
|---|---|---|
| ACTIVE, IN_GRACE_PERIOD | `active` até `expiryTime` | sim |
| CANCELED | `cancelled` até `expiryTime` | sim, até o fim do período pago |
| PENDING | `pending` | não |
| ON_HOLD, PAUSED, EXPIRED | `expired` | não |
| Revogada (RTDN 12) ou reembolso/chargeback (voided) | `expired` imediato | não |

Eventos fora de ordem: o estado é sempre relido na API e gravado com `storeFetchedAt`; um retrato mais antigo nunca sobrescreve um mais novo. Troca de plano: o token novo traz `linkedPurchaseToken`; eventos tardios do token antigo não rebaixam a família.

## Configurado no Google Cloud (verificado)

- `androidpublisher.googleapis.com` habilitada em `iplex-2c8fc`.
- Tópico `play-billing-notifications` criado; `google-play-developer-notifications@system.gserviceaccount.com` com `roles/pubsub.publisher` somente nesse tópico.

## Ações necessárias na Play Console (responsável)

1. ~~Confirmar o pacote~~ — confirmado em 19/10/2026: app "iPlex - Control", `com.alienssyndicate.iplex_control`. Firebase Android app `1:59148444884:android:c2af001a99cf61f6f20741` registrado com o SHA-1/SHA-256 da chave de debug; faltam os SHA da chave de upload e do Play App Signing.
2. **Acesso da conta de serviço:** *Usuários e permissões* › *Convidar novos usuários* › e-mail `59148444884-compute@developer.gserviceaccount.com` › permissões do app: **Ver dados financeiros** e **Gerenciar pedidos e assinaturas**. Confirmar em *Usuários e permissões* que aparece como ativo.
3. **Notificações em tempo real:** *Monetizar* › *Configuração da monetização* › *Notificações do desenvolvedor em tempo real* › tópico `projects/iplex-2c8fc/topics/play-billing-notifications` › *Enviar mensagem de teste*. Só é recebida depois do deploy de `playBillingNotifications`.
4. **Produto:** *Monetizar* › *Produtos* › *Assinaturas* › *Criar assinatura* › ID `iplex_playback`; planos-base `monthly` (Mensal, renovação automática, R$ 9,90 no Brasil) e `annual` (Anual, renovação automática, R$ 99,90 no Brasil). Não criar ofertas. Requer um AAB com a biblioteca de faturamento já enviado a uma faixa.
5. **Testadores de licença:** *Configurações* › *Teste de licença* › adicionar as contas Google de teste (compras de teste, sem cobrança real).
6. **Faixa de teste interno:** enviar o AAB assinado com a chave de upload.

## Planos

| Plano | Como é obtido | Estado em `subscription` |
|---|---|---|
| Teste de 7 dias | Automático no primeiro `linkDevice`, uma vez por família | `trial` até `trialEndsAt` |
| Mensal / Anual | Google Play (`iplex_playback`, planos-base `monthly`/`annual`) | `active`/`cancelled` até `paidUntil` |
| Vitalício | Cupom (`redeemCoupon`) ou concessão do operador | `lifetime`, sem vencimento |

Vitalício nunca é sobrescrito por estado da Play; uma compra feita por família vitalícia é recusada (`already-lifetime`) e fica sem confirmação, então a Play a reembolsa.

### Cupons

- `coupons/{sha256('iplex-coupon:' + código normalizado)}`: `{plan: 'lifetime', maxRedemptions, redemptions, expiresAt?, disabled?, note?}`. O código não é guardado; maiúsculas, espaços e hífens são ignorados.
- Resgate: administrador do escopo, uma vez por família, tentativas limitadas (20/h por usuário). Registro em `coupons/{id}/redemptions/{familyId}`. Regras negam qualquer acesso do cliente.
- Operação (`functions/`, credenciais ADC do operador):
  - `npx tsx scripts/coupons.ts create --uses 1 [--expires AAAA-MM-DD] [--note texto]` — imprime o código uma vez.
  - `npx tsx scripts/coupons.ts disable <código>`
  - `npx tsx scripts/coupons.ts grant <email> [--apply]` — concede vitalício direto na família do usuário (sem `--apply` só simula).

## Ativação futura (exige autorização explícita)

- Teste isolado: incluir UIDs em `app_config/payments.testerUids` (checkout só para eles; `paymentsEnabled` continua `false`).
- Público: `app_config/payments.paymentsEnabled = true`.
