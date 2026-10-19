import * as admin from 'firebase-admin';

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: 'iplex-2c8fc',
  });
}

const db = admin.firestore();

interface MigrationStats {
  familiesCount: number;
  usersCount: number;
  membersCount: number;
  profilesCount: number;
  devicesCount: number;
  sourcesCount: number;
  favoritesCount: number;
  progressCount: number;
  subscriptionsCount: number;
}

export async function runMigration(dryRun: boolean = true) {
  console.log(`=======================================================`);
  console.log(`[iPlex Migration] Mode: ${dryRun ? 'DRY-RUN (SIMULAÇÃO - NENHUMA ESCRITA)' : 'EXECUÇÃO REAL'}`);
  console.log(`[iPlex Migration] Project: iplex-2c8fc`);
  console.log(`=======================================================\n`);

  const stats: MigrationStats = {
    familiesCount: 0,
    usersCount: 0,
    membersCount: 0,
    profilesCount: 0,
    devicesCount: 0,
    sourcesCount: 0,
    favoritesCount: 0,
    progressCount: 0,
    subscriptionsCount: 0,
  };

  // 1. Inspecionar usuários
  const usersSnap = await db.collection('users').get();
  stats.usersCount = usersSnap.size;
  console.log(`[Users] Encontrados ${usersSnap.size} usuários em /users:`);
  for (const uDoc of usersSnap.docs) {
    const uData = uDoc.data();
    console.log(`  - User: ${uDoc.id} | Email: ${uData.email || 'N/A'} | Nome: ${uData.displayName || uData.name || 'N/A'} | Família: ${uData.primaryFamilyId || uData.familyId || 'Nenhuma'}`);
  }
  console.log('');

  // 2. Inspecionar famílias
  const familiesSnap = await db.collection('families').get();
  stats.familiesCount = familiesSnap.size;
  console.log(`[Families] Encontradas ${familiesSnap.size} famílias em /families:`);

  for (const familyDoc of familiesSnap.docs) {
    const familyId = familyDoc.id;
    const familyData = familyDoc.data();
    const adminUid = familyData.adminUid || familyData.adminId || '';

    console.log(`\n-------------------------------------------------------`);
    console.log(`Família ID: ${familyId}`);
    console.log(`  Nome: "${familyData.name || 'Sem nome'}" | Admin UID: ${adminUid} | Status: ${familyData.status || 'active'}`);

    // 2.1 Migrar/Validar Membros
    const membersSnap = await familyDoc.ref.collection('members').get();
    console.log(`  Subcoleção /members: ${membersSnap.size} membros`);
    for (const mDoc of membersSnap.docs) {
      const mData = mDoc.data();
      const userUid = mDoc.id;
      const membershipId = `${familyId}_${userUid}`;
      const role = userUid === adminUid ? 'admin' : (mData.role || 'member');

      console.log(`    -> Membro [${membershipId}]: userUid=${userUid}, role=${role}, status=active`);

      if (!dryRun) {
        await db.collection('family_members').doc(membershipId).set({
          familyId,
          userUid,
          role,
          status: 'active',
          joinedAt: mData.joinedAt || familyData.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      stats.membersCount++;
    }

    // 2.2 Migrar/Validar Perfis
    const profilesSnap = await familyDoc.ref.collection('profiles').get();
    console.log(`  Subcoleção /profiles: ${profilesSnap.size} perfis`);
    for (const pDoc of profilesSnap.docs) {
      const pData = pDoc.data();
      const profileId = pDoc.id;

      console.log(`    -> Perfil [${profileId}]: "${pData.name || 'Sem nome'}", avatarKey=${pData.avatarKey || 'avatar-01'}`);

      if (!dryRun) {
        await db.collection('profiles').doc(profileId).set({
          familyId,
          name: pData.name || 'Perfil',
          avatarKey: pData.avatarKey || 'avatar-01',
          status: 'active',
          createdByUid: pData.createdByUid || adminUid,
          createdAt: pData.createdAt || admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: pData.updatedAt || admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      stats.profilesCount++;

      // 2.2.1 Favoritos do perfil
      const favSnap = await pDoc.ref.collection('favorites').get();
      if (favSnap.size > 0) {
        console.log(`       Favoritos (${favSnap.size}):`);
        for (const fDoc of favSnap.docs) {
          const fData = fDoc.data();
          const contentId = fDoc.id;
          const favId = `${profileId}_${contentId}`;
          console.log(`         * Favorito [${favId}]: "${fData.title || contentId}"`);

          if (!dryRun) {
            await db.collection('profile_favorites').doc(favId).set({
              familyId,
              profileId,
              contentId,
              title: fData.title || '',
              catalogId: fData.catalogId || null,
              createdAt: fData.createdAt || admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: fData.updatedAt || admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          stats.favoritesCount++;
        }
      }

      // 2.2.2 Progresso do perfil
      const progSnap = await pDoc.ref.collection('watch_progress').get();
      if (progSnap.size > 0) {
        console.log(`       Progresso de Reprodução (${progSnap.size}):`);
        for (const prDoc of progSnap.docs) {
          const prData = prDoc.data();
          const contentId = prDoc.id;
          const progId = `${profileId}_${contentId}`;
          console.log(`         * Progresso [${progId}]: pos=${prData.position}/${prData.duration}`);

          if (!dryRun) {
            await db.collection('profile_progress').doc(progId).set({
              familyId,
              profileId,
              contentId,
              position: prData.position || 0,
              duration: prData.duration || 0,
              updatedAt: prData.updatedAt || admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          stats.progressCount++;
        }
      }
    }

    // 2.3 Migrar/Validar Dispositivos (TVs)
    const devicesSnap = await familyDoc.ref.collection('devices').get();
    console.log(`  Subcoleção /devices: ${devicesSnap.size} dispositivos`);
    for (const dDoc of devicesSnap.docs) {
      const dData = dDoc.data();
      const deviceId = dDoc.id;

      console.log(`    -> Dispositivo [${deviceId}]: "${dData.name || dData.displayName || 'Smart TV'}" | Plataforma: ${dData.platform || 'android_tv'}`);

      if (!dryRun) {
        await db.collection('devices').doc(deviceId).set({
          familyId,
          displayName: dData.name || dData.displayName || 'Smart TV',
          platform: dData.platform || 'android_tv',
          status: 'linked',
          lastSeenAt: dData.lastSeenAt ? admin.firestore.Timestamp.fromMillis(dData.lastSeenAt) : null,
          linkedAt: dData.createdAt ? admin.firestore.Timestamp.fromMillis(dData.createdAt) : admin.firestore.FieldValue.serverTimestamp(),
          linkedByUid: dData.linkedByUid || adminUid,
        }, { merge: true });
      }
      stats.devicesCount++;
    }

    // 2.4 Migrar/Validar Fontes IPTV
    const sourcesSnap = await familyDoc.ref.collection('sources').get();
    console.log(`  Subcoleção /sources: ${sourcesSnap.size} fontes IPTV`);
    for (const sDoc of sourcesSnap.docs) {
      const sData = sDoc.data();
      const sourceId = sDoc.id;
      const rawType = sData.type || sData.format || 'url';
      const normalizedType = rawType === 'other_m3u8' ? 'm3u8_alternative' : (rawType === 'm3u' ? 'url' : rawType);

      console.log(`    -> Fonte [${sourceId}]: "${sData.name || 'IPTV'}" | Tipo: ${normalizedType} | Status: ${sData.status || 'ready'}`);

      if (!dryRun) {
        await db.collection('iptv_sources').doc(sourceId).set({
          familyId,
          name: sData.name || 'IPTV',
          type: normalizedType,
          status: sData.status || 'ready',
          catalogId: sData.catalogId || null,
          credentialsRef: `source_secrets/${familyId}_${sourceId}`,
          epgEnabled: !!sData.hasEpg,
          pinProtected: !!sData.isProtected,
          contentCount: sData.contentCount || 0,
          createdByUid: adminUid,
          updatedByUid: adminUid,
          createdAt: sData.createdAt ? admin.firestore.Timestamp.fromMillis(sData.createdAt) : admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: sData.updatedAt ? admin.firestore.Timestamp.fromMillis(sData.updatedAt) : admin.firestore.FieldValue.serverTimestamp(),
          lastSyncAt: sData.lastAttemptAt ? admin.firestore.Timestamp.fromMillis(sData.lastAttemptAt) : null,
          errorCode: sData.errorCode || null,
        }, { merge: true });
      }
      stats.sourcesCount++;
    }

    // 2.5 Migrar/Validar Assinatura
    const subDoc = await familyDoc.ref.collection('private').doc('subscription').get();
    if (subDoc.exists) {
      const sData = subDoc.data()!;
      const subStatus = sData.status === 'trial' ? 'trialing' : (sData.status || 'not_started');
      console.log(`  Subdocumento /private/subscription: status="${subStatus}", plan="monthly"`);

      if (!dryRun) {
        await db.collection('subscriptions').doc(familyId).set({
          familyId,
          status: subStatus,
          plan: 'monthly',
          trialStartedAt: sData.trialStartedAt ? admin.firestore.Timestamp.fromMillis(sData.trialStartedAt) : null,
          trialEndsAt: sData.trialEndsAt ? admin.firestore.Timestamp.fromMillis(sData.trialEndsAt) : null,
          currentPeriodEndsAt: sData.paidUntil ? admin.firestore.Timestamp.fromMillis(sData.paidUntil) : null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      stats.subscriptionsCount++;
    }
  }

  console.log(`\n=======================================================`);
  console.log(`[iPlex Migration] Resumo do Processamento:`);
  console.log(`  - Usuários verificados: ${stats.usersCount}`);
  console.log(`  - Famílias processadas: ${stats.familiesCount}`);
  console.log(`  - Membros a migrar (family_members): ${stats.membersCount}`);
  console.log(`  - Perfis a migrar (profiles): ${stats.profilesCount}`);
  console.log(`  - Dispositivos a migrar (devices): ${stats.devicesCount}`);
  console.log(`  - Fontes IPTV a migrar (iptv_sources): ${stats.sourcesCount}`);
  console.log(`  - Favoritos a migrar (profile_favorites): ${stats.favoritesCount}`);
  console.log(`  - Registros de Progresso (profile_progress): ${stats.progressCount}`);
  console.log(`  - Assinaturas familiares (subscriptions): ${stats.subscriptionsCount}`);
  console.log(`=======================================================`);

  if (dryRun) {
    console.log(`\n>>> SUCESSO: Dry-run concluído sem alterações. O banco permanece idêntico.`);
  } else {
    console.log(`\n>>> SUCESSO: Migração executada e persistida em coleções de primeiro nível.`);
  }
}

// Execução direta
const isDryRun = process.argv.includes('--execute') ? false : true;
runMigration(isDryRun).catch(err => {
  console.error('[iPlex Migration Error]', err);
  process.exit(1);
});
