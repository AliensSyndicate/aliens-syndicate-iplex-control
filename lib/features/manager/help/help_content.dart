/// Frequently asked questions of the Help and support page, per language.
/// Every answer describes the real screens of the app; keep them in sync
/// when a flow changes.
class HelpTopic {
  const HelpTopic(this.title, this.items);
  final String title;
  final List<HelpItem> items;
}

class HelpItem {
  const HelpItem(this.question, this.answer);
  final String question, answer;
}

/// Topics for [languageCode] (`pt`, `es`; anything else gets English).
List<HelpTopic> helpTopics(String languageCode) => switch (languageCode) {
  'pt' => _pt,
  'es' => _es,
  _ => _en,
};

const _pt = [
  HelpTopic('Primeiros passos', [
    HelpItem(
      'O que é o iPlex?',
      'O iPlex tem duas partes: este aplicativo de celular, gratuito, onde você administra família, perfis, TVs e listas IPTV, e o iPlex na TV, onde o conteúdo é reproduzido.',
    ),
    HelpItem(
      'O iPlex fornece canais ou listas IPTV?',
      'Não. O iPlex é somente um player. Não oferecemos, vendemos nem indicamos listas IPTV. Você adiciona as listas que já tem com o seu provedor e é o responsável pelo conteúdo delas.',
    ),
    HelpItem(
      'Como eu entro no aplicativo?',
      'Com sua conta Google ou Apple, na tela inicial. Não é preciso criar senha.',
    ),
    HelpItem(
      'Preciso pagar para usar o aplicativo no celular?',
      'Não. Tudo no celular é gratuito: família, perfis, TVs, listas IPTV e configurações. A assinatura libera somente a reprodução no iPlex da TV.',
    ),
  ]),
  HelpTopic('Listas IPTV', [
    HelpItem(
      'Como adiciono uma lista IPTV?',
      'Abra a aba IPTV e toque em “+”. Escolha Xtream Codes (servidor, usuário e senha), URL (endereço M3U, M3U8 ou HLS) ou Arquivo (uma lista salva no celular). Dê um nome e salve. A sincronização começa sozinha.',
    ),
    HelpItem(
      'Quais formatos são aceitos?',
      'M3U, M3U8, Xtream Codes, HLS e arquivos de lista M3U salvos no aparelho.',
    ),
    HelpItem(
      'Quanto tempo demora a sincronização?',
      'Depende do tamanho da lista e da velocidade do provedor. Você acompanha o progresso na aba IPTV. Se as notificações estiverem ativadas, o iPlex avisa quando terminar ou se falhar.',
    ),
    HelpItem(
      'Como atualizo uma lista manualmente?',
      'Na aba IPTV, abra a lista e toque em Sincronizar agora. A TV também pode pedir a mesma atualização.',
    ),
    HelpItem(
      'A sincronização falhou. O que faço?',
      'A lista mostra o motivo do erro. Confira o endereço, o usuário, a senha e se a assinatura com o seu provedor está ativa. O catálogo anterior continua disponível, e o iPlex faz novas tentativas automáticas.',
    ),
    HelpItem(
      'Minha senha IPTV fica segura?',
      'Sim. Usuário e senha do provedor ficam criptografados no servidor, são usados só para baixar o catálogo e reproduzir na sua TV e nunca são exibidos de volta no aplicativo.',
    ),
    HelpItem(
      'Como edito ou excluo uma lista?',
      'Na aba IPTV, abra a lista e use editar ou excluir. Ao excluir, o catálogo dela sai de todos os perfis e TVs da família.',
    ),
  ]),
  HelpTopic('TVs', [
    HelpItem(
      'Como vinculo minha TV?',
      'Abra o iPlex na TV: ela mostra um QR Code e um código de 6 dígitos. No celular, vá em Dispositivos, toque em “+” e leia o QR Code ou digite o código.',
    ),
    HelpItem(
      'O código da TV expirou. E agora?',
      'Os códigos de vinculação valem por pouco tempo e só podem ser usados uma vez. Aguarde a TV mostrar um novo código e tente de novo.',
    ),
    HelpItem(
      'Quantas TVs posso vincular?',
      'Quantas quiser. Não há limite de TVs vinculadas.',
    ),
    HelpItem(
      'Como renomeio ou desvinculo uma TV?',
      'Em Dispositivos, abra a TV. Lá você edita o nome ou toca em Desvincular dispositivo. A TV é desconectada na hora.',
    ),
    HelpItem(
      'O que é “Assistir na TV”?',
      'Na tela de um filme ou série, toque em Assistir na TV e escolha a TV (e o episódio, nas séries). O pedido chega à TV com o iPlex aberto, e você acompanha a situação pelo celular.',
    ),
  ]),
  HelpTopic('Família e membros', [
    HelpItem(
      'O que é a família?',
      'Toda conta já nasce com a própria família, da qual é a administradora. A família tem um administrador, até 4 membros e um visitante opcional, e cada conta participa de uma única família.',
    ),
    HelpItem(
      'Como adiciono um membro?',
      'Na aba Família, toque em “+”. Digite o código de 12 caracteres da pessoa ou leia o QR Code dela, escolha se a conta será Membro ou Infantil e envie a solicitação. A pessoa aceita pela aba Família no celular dela.',
    ),
    HelpItem(
      'Onde encontro o meu código?',
      'Em Conta, toque no botão de QR Code no topo. Ali estão o seu QR Code e o código de 12 caracteres, com a opção de copiar. Ele serve só para receber convites, não é senha.',
    ),
    HelpItem(
      'Recebi um convite. Como aceito?',
      'Abra a aba Família, toque na solicitação e escolha aceitar ou recusar. Se a sua família atual já tiver listas, TVs ou perfis, é preciso removê-los antes de aceitar.',
    ),
    HelpItem(
      'Posso participar de duas famílias?',
      'Não. Cada conta pertence a uma única família por vez.',
    ),
    HelpItem(
      'Como saio de uma família?',
      'Na aba Família, abra o seu cartão e toque em Sair da família. Você volta para a sua família individual. O administrador não pode sair da própria família.',
    ),
    HelpItem(
      'Como removo um membro?',
      'Na aba Família, abra o cartão do membro e toque em Remover da família. O perfil e os dados dele são mantidos. Para liberar a vaga, exclua o perfil.',
    ),
    HelpItem(
      'Posso criar um perfil para quem não tem conta?',
      'Sim. O administrador cria o perfil, e depois a pessoa pode vincular uma conta: no cartão do perfil, toque em Vincular com conta para gerar um código temporário, válido por 10 minutos. A pessoa digita o código em Família › Vincular a um perfil.',
    ),
    HelpItem(
      'O que é a conta visitante?',
      'Um perfil extra para convidados, ligado e desligado pelo botão no topo da aba Família. Ele não ocupa vaga de membro e não guarda favoritos, assistidos nem progresso.',
    ),
  ]),
  HelpTopic('Infantil e PIN', [
    HelpItem(
      'O que é um perfil Infantil?',
      'Um perfil que recebe somente conteúdo classificado como infantil pelo servidor do iPlex. Conteúdo adulto nunca aparece nele. A classificação depende das informações enviadas pelo provedor da lista.',
    ),
    HelpItem(
      'Como transformo um perfil em Infantil?',
      'Somente o administrador pode fazer isso: na aba Família, abra o cartão do membro e ative Conta infantil. Favoritos, histórico e vínculos são mantidos.',
    ),
    HelpItem(
      'O que é o PIN pessoal?',
      'Um PIN de 4 dígitos que protege o seu perfil. Na aba Família, abra o seu cartão e toque em PIN pessoal para ativar, alterar ou desativar. Com ele ativo, a TV pede o PIN para abrir o seu perfil e para tocar conteúdo adulto. Somente você pode definir.',
    ),
    HelpItem(
      'Como escolho o que cada membro pode ver?',
      'Na aba Família, abra o cartão do membro. Em Conteúdo, o administrador liga ou desliga Canais, Filmes, Séries e Conteúdo adulto, valendo para todas as listas. O próprio membro pode desligar Canais, Filmes ou Séries para si, mas só o administrador decide sobre o conteúdo adulto.',
    ),
  ]),
  HelpTopic('Favoritos e histórico', [
    HelpItem(
      'Onde ficam meus favoritos e o que estou assistindo?',
      'Na Home do celular e na TV, nas seções Favoritos, Continuar assistindo e Lista de desejos. Tudo é salvo no seu perfil e sincronizado entre os aparelhos.',
    ),
    HelpItem(
      'Como apago favoritos, assistidos ou o progresso?',
      'Na aba Família, abra o cartão do perfil e toque na lista: Continuar assistindo, Favoritos, Lista de desejos ou Assistidos. No topo, toque no botão de limpar e confirme. O administrador limpa as listas de qualquer perfil, e cada membro limpa as próprias. A exclusão é definitiva e chega a todas as TVs.',
    ),
  ]),
  HelpTopic('Assinatura', [
    HelpItem(
      'Existe teste grátis?',
      'Sim. São 7 dias de reprodução grátis, que começam na primeira TV vinculada com sucesso. O teste é concedido uma única vez.',
    ),
    HelpItem(
      'Como assino?',
      'Em Conta › Assinatura do Player aparecem os planos disponíveis, mensal ou anual, cobrados pelo Google Play com renovação automática. O preço exibido é sempre o da loja. A assinatura é feita pelo administrador e vale para a família.',
    ),
    HelpItem(
      'Quantas pessoas podem assistir ao mesmo tempo?',
      'Até 3 reproduções simultâneas por família, com no máximo 1 por perfil.',
    ),
    HelpItem(
      'Como cancelo a assinatura?',
      'No Google Play, em Pagamentos e assinaturas › Assinaturas. O acesso continua até o fim do período pago. Excluir a conta não cancela a assinatura na loja.',
    ),
    HelpItem(
      'Tenho um cupom. Onde uso?',
      'Em Conta › Assinatura do Player, toque em Resgatar cupom e digite o código. Cupons válidos liberam o acesso vitalício.',
    ),
    HelpItem(
      'Troquei de celular. Como recupero a assinatura?',
      'Entre com a mesma conta e, em Conta › Assinatura do Player, toque em Restaurar compras.',
    ),
  ]),
  HelpTopic('Conta', [
    HelpItem(
      'Como mudo o idioma?',
      'Em Conta, no campo Idioma, escolha Português, English, Español ou o idioma do sistema.',
    ),
    HelpItem(
      'Por que não consigo fazer algumas ações?',
      'Membros não fazem ações administrativas, como convidar pessoas, mudar permissões ou gerenciar a assinatura. Peça ao administrador da sua família.',
    ),
    HelpItem(
      'Como compartilho o aplicativo?',
      'Em Conta, toque em Compartilhar aplicativo e escolha WhatsApp, Telegram, e-mail ou outro app. Isso não é um convite para a família: para adicionar alguém, use o código ou o QR Code.',
    ),
    HelpItem(
      'Como excluo minha conta?',
      'Em Conta, toque em Excluir conta e entre novamente para confirmar. O administrador precisa remover os membros antes. Os dados são excluídos permanentemente, mas a assinatura do Google Play deve ser cancelada na loja.',
    ),
  ]),
];

const _en = [
  HelpTopic('Getting started', [
    HelpItem(
      'What is iPlex?',
      'iPlex has two parts: this free phone app, where you manage your family, profiles, TVs and IPTV lists, and iPlex on the TV, where content is played.',
    ),
    HelpItem(
      'Does iPlex provide channels or IPTV lists?',
      'No. iPlex is only a player. We do not offer, sell or recommend IPTV lists. You add the lists you already have with your provider and you are responsible for their content.',
    ),
    HelpItem(
      'How do I sign in?',
      'With your Google or Apple account on the start screen. No password needs to be created.',
    ),
    HelpItem(
      'Do I have to pay to use the phone app?',
      'No. Everything on the phone is free: family, profiles, TVs, IPTV lists and settings. The subscription only unlocks playback in iPlex on the TV.',
    ),
  ]),
  HelpTopic('IPTV lists', [
    HelpItem(
      'How do I add an IPTV list?',
      'Open the IPTV tab and tap “+”. Choose Xtream Codes (server, username and password), URL (an M3U, M3U8 or HLS address) or File (a list saved on the phone). Give it a name and save. Syncing starts on its own.',
    ),
    HelpItem(
      'Which formats are supported?',
      'M3U, M3U8, Xtream Codes, HLS and M3U list files saved on the device.',
    ),
    HelpItem(
      'How long does syncing take?',
      'It depends on the size of the list and the speed of the provider. You can follow the progress in the IPTV tab. With notifications on, iPlex tells you when it finishes or fails.',
    ),
    HelpItem(
      'How do I refresh a list manually?',
      'In the IPTV tab, open the list and tap Sync now. The TV can request the same refresh.',
    ),
    HelpItem(
      'Syncing failed. What should I do?',
      'The list shows the reason. Check the address, username, password and whether your plan with the provider is active. The previous catalog stays available and iPlex retries automatically.',
    ),
    HelpItem(
      'Is my IPTV password safe?',
      'Yes. The provider username and password are encrypted on the server, used only to download the catalog and to play on your TV, and are never shown again in the app.',
    ),
    HelpItem(
      'How do I edit or delete a list?',
      'In the IPTV tab, open the list and use edit or delete. Deleting removes its catalog from every profile and TV of the family.',
    ),
  ]),
  HelpTopic('TVs', [
    HelpItem(
      'How do I link my TV?',
      'Open iPlex on the TV: it shows a QR code and a 6-digit code. On the phone, go to Devices, tap “+” and scan the QR code or type the code.',
    ),
    HelpItem(
      'The TV code expired. Now what?',
      'Pairing codes are short-lived and single-use. Wait for the TV to show a new code and try again.',
    ),
    HelpItem(
      'How many TVs can I link?',
      'As many as you want. There is no limit on linked TVs.',
    ),
    HelpItem(
      'How do I rename or unlink a TV?',
      'In Devices, open the TV. There you can edit its name or tap Unlink device. The TV is disconnected immediately.',
    ),
    HelpItem(
      'What is “Watch on TV”?',
      'On a movie or series page, tap Watch on TV and choose the TV (and the episode, for series). The request reaches the TV with iPlex open, and you can follow its status on the phone.',
    ),
  ]),
  HelpTopic('Family and members', [
    HelpItem(
      'What is the family?',
      'Every account starts with its own family, as its administrator. A family has one administrator, up to 4 members and an optional guest, and each account belongs to a single family.',
    ),
    HelpItem(
      'How do I add a member?',
      'In the Family tab, tap “+”. Type the person’s 12-character code or scan their QR code, choose Member or Child account, and send the request. The person accepts it in the Family tab on their phone.',
    ),
    HelpItem(
      'Where is my code?',
      'In Account, tap the QR code button at the top. It shows your QR code and your 12-character code, with a copy option. It is only used to receive invitations; it is not a password.',
    ),
    HelpItem(
      'I received an invitation. How do I accept it?',
      'Open the Family tab, tap the request and choose accept or decline. If your current family already has lists, TVs or profiles, remove them before accepting.',
    ),
    HelpItem(
      'Can I be in two families?',
      'No. Each account belongs to one family at a time.',
    ),
    HelpItem(
      'How do I leave a family?',
      'In the Family tab, open your card and tap Leave family. You return to your individual family. The administrator cannot leave their own family.',
    ),
    HelpItem(
      'How do I remove a member?',
      'In the Family tab, open the member’s card and tap Remove from family. Their profile and data are kept. Delete the profile to free the slot.',
    ),
    HelpItem(
      'Can I create a profile for someone without an account?',
      'Yes. The administrator creates the profile and the person can link an account later: on the profile card, tap Link to an account to get a temporary code valid for 10 minutes. The person types it in Family › Link to a profile.',
    ),
    HelpItem(
      'What is the guest account?',
      'An extra profile for visitors, turned on and off with the button at the top of the Family tab. It does not use a member slot and never saves favorites, watched titles or progress.',
    ),
  ]),
  HelpTopic('Kids and PIN', [
    HelpItem(
      'What is a Kids profile?',
      'A profile that only receives content classified as children’s content by the iPlex server. Adult content never appears there. The classification depends on the information sent by the list provider.',
    ),
    HelpItem(
      'How do I turn a profile into Kids?',
      'Only the administrator can: in the Family tab, open the member’s card and turn on Child account. Favorites, history and links are kept.',
    ),
    HelpItem(
      'What is the personal PIN?',
      'A 4-digit PIN that protects your profile. In the Family tab, open your card and tap Personal PIN to turn it on, change it or turn it off. When it is on, the TV asks for it to open your profile and to play adult content. Only you can set it.',
    ),
    HelpItem(
      'How do I choose what each member can see?',
      'In the Family tab, open the member’s card. Under Content, the administrator turns Channels, Movies, Series and Adult content on or off, for every list. Members can turn Channels, Movies or Series off for themselves, but only the administrator decides on adult content.',
    ),
  ]),
  HelpTopic('Favorites and history', [
    HelpItem(
      'Where are my favorites and what I am watching?',
      'On the Home screen of the phone and the TV, in Favorites, Continue watching and Wishlist. Everything is saved in your profile and synced across devices.',
    ),
    HelpItem(
      'How do I delete favorites, watched titles or progress?',
      'In the Family tab, open the profile card and tap the list: Continue watching, Favorites, Wishlist or Watched. At the top, tap the clear button and confirm. The administrator clears any profile’s lists, and each member clears their own. Deletion is permanent and reaches every TV.',
    ),
  ]),
  HelpTopic('Subscription', [
    HelpItem(
      'Is there a free trial?',
      'Yes. You get 7 days of free playback, starting when the first TV is linked successfully. The trial is granted only once.',
    ),
    HelpItem(
      'How do I subscribe?',
      'Account › Player subscription shows the available plans, monthly or annual, billed by Google Play with automatic renewal. The price shown is always the store price. The administrator subscribes for the whole family.',
    ),
    HelpItem(
      'How many people can watch at the same time?',
      'Up to 3 simultaneous streams per family, with at most 1 per profile.',
    ),
    HelpItem(
      'How do I cancel?',
      'In Google Play, under Payments & subscriptions › Subscriptions. Access continues until the end of the paid period. Deleting the account does not cancel the store subscription.',
    ),
    HelpItem(
      'I have a coupon. Where do I use it?',
      'In Account › Player subscription, tap Redeem coupon and type the code. Valid coupons unlock lifetime access.',
    ),
    HelpItem(
      'I changed phones. How do I get my subscription back?',
      'Sign in with the same account and, in Account › Player subscription, tap Restore purchases.',
    ),
  ]),
  HelpTopic('Account', [
    HelpItem(
      'How do I change the language?',
      'In Account, under Language, choose Português, English, Español or the system language.',
    ),
    HelpItem(
      'Why can’t I do some actions?',
      'Members cannot perform administrative actions such as inviting people, changing permissions or managing the subscription. Ask your family administrator.',
    ),
    HelpItem(
      'How do I share the app?',
      'In Account, tap Share application and choose WhatsApp, Telegram, email or another app. This is not a family invitation: to add someone, use their code or QR code.',
    ),
    HelpItem(
      'How do I delete my account?',
      'In Account, tap Delete account and sign in again to confirm. An administrator must remove the members first. Data is permanently deleted, but a Google Play subscription must be cancelled in the store.',
    ),
  ]),
];

const _es = [
  HelpTopic('Primeros pasos', [
    HelpItem(
      '¿Qué es iPlex?',
      'iPlex tiene dos partes: esta app gratuita para el celular, donde administras la familia, los perfiles, los televisores y las listas IPTV, e iPlex en el televisor, donde se reproduce el contenido.',
    ),
    HelpItem(
      '¿iPlex ofrece canales o listas IPTV?',
      'No. iPlex es solo un reproductor. No ofrecemos, vendemos ni recomendamos listas IPTV. Agregas las listas que ya tienes con tu proveedor y eres responsable de su contenido.',
    ),
    HelpItem(
      '¿Cómo inicio sesión?',
      'Con tu cuenta de Google o Apple en la pantalla inicial. No necesitas crear una contraseña.',
    ),
    HelpItem(
      '¿Tengo que pagar para usar la app del celular?',
      'No. Todo en el celular es gratis: familia, perfiles, televisores, listas IPTV y configuración. La suscripción solo habilita la reproducción en iPlex del televisor.',
    ),
  ]),
  HelpTopic('Listas IPTV', [
    HelpItem(
      '¿Cómo agrego una lista IPTV?',
      'Abre la pestaña IPTV y toca “+”. Elige Xtream Codes (servidor, usuario y contraseña), URL (una dirección M3U, M3U8 o HLS) o Archivo (una lista guardada en el celular). Ponle un nombre y guarda. La sincronización empieza sola.',
    ),
    HelpItem(
      '¿Qué formatos se admiten?',
      'M3U, M3U8, Xtream Codes, HLS y archivos de lista M3U guardados en el dispositivo.',
    ),
    HelpItem(
      '¿Cuánto tarda la sincronización?',
      'Depende del tamaño de la lista y de la velocidad del proveedor. Puedes seguir el progreso en la pestaña IPTV. Con las notificaciones activadas, iPlex te avisa cuando termina o falla.',
    ),
    HelpItem(
      '¿Cómo actualizo una lista manualmente?',
      'En la pestaña IPTV, abre la lista y toca Sincronizar ahora. El televisor también puede pedir la misma actualización.',
    ),
    HelpItem(
      'La sincronización falló. ¿Qué hago?',
      'La lista muestra el motivo. Revisa la dirección, el usuario, la contraseña y si tu plan con el proveedor está activo. El catálogo anterior sigue disponible e iPlex reintenta automáticamente.',
    ),
    HelpItem(
      '¿Mi contraseña IPTV está segura?',
      'Sí. El usuario y la contraseña del proveedor se guardan cifrados en el servidor, se usan solo para descargar el catálogo y reproducir en tu televisor y nunca se vuelven a mostrar en la app.',
    ),
    HelpItem(
      '¿Cómo edito o elimino una lista?',
      'En la pestaña IPTV, abre la lista y usa editar o eliminar. Al eliminarla, su catálogo desaparece de todos los perfiles y televisores de la familia.',
    ),
  ]),
  HelpTopic('Televisores', [
    HelpItem(
      '¿Cómo vinculo mi televisor?',
      'Abre iPlex en el televisor: muestra un código QR y un código de 6 dígitos. En el celular, ve a Dispositivos, toca “+” y escanea el código QR o escribe el código.',
    ),
    HelpItem(
      'El código del televisor expiró. ¿Y ahora?',
      'Los códigos de vinculación duran poco y son de un solo uso. Espera a que el televisor muestre un código nuevo e inténtalo otra vez.',
    ),
    HelpItem(
      '¿Cuántos televisores puedo vincular?',
      'Los que quieras. No hay límite de televisores vinculados.',
    ),
    HelpItem(
      '¿Cómo cambio el nombre o desvinculo un televisor?',
      'En Dispositivos, abre el televisor. Ahí puedes editar el nombre o tocar Desvincular dispositivo. El televisor se desconecta al instante.',
    ),
    HelpItem(
      '¿Qué es “Ver en la TV”?',
      'En la pantalla de una película o serie, toca Ver en la TV y elige el televisor (y el episodio, en las series). El pedido llega al televisor con iPlex abierto y puedes seguir su estado desde el celular.',
    ),
  ]),
  HelpTopic('Familia y miembros', [
    HelpItem(
      '¿Qué es la familia?',
      'Cada cuenta empieza con su propia familia, como administradora. Una familia tiene un administrador, hasta 4 miembros y un visitante opcional, y cada cuenta pertenece a una sola familia.',
    ),
    HelpItem(
      '¿Cómo agrego un miembro?',
      'En la pestaña Familia, toca “+”. Escribe el código de 12 caracteres de la persona o escanea su código QR, elige Miembro o Infantil y envía la solicitud. La persona la acepta en la pestaña Familia de su celular.',
    ),
    HelpItem(
      '¿Dónde está mi código?',
      'En Cuenta, toca el botón de código QR arriba. Ahí están tu código QR y tu código de 12 caracteres, con la opción de copiarlo. Solo sirve para recibir invitaciones; no es una contraseña.',
    ),
    HelpItem(
      'Recibí una invitación. ¿Cómo la acepto?',
      'Abre la pestaña Familia, toca la solicitud y elige aceptar o rechazar. Si tu familia actual ya tiene listas, televisores o perfiles, elimínalos antes de aceptar.',
    ),
    HelpItem(
      '¿Puedo estar en dos familias?',
      'No. Cada cuenta pertenece a una sola familia a la vez.',
    ),
    HelpItem(
      '¿Cómo salgo de una familia?',
      'En la pestaña Familia, abre tu tarjeta y toca Salir de la familia. Vuelves a tu familia individual. El administrador no puede salir de su propia familia.',
    ),
    HelpItem(
      '¿Cómo quito a un miembro?',
      'En la pestaña Familia, abre la tarjeta del miembro y toca Quitar de la familia. Su perfil y sus datos se conservan. Elimina el perfil para liberar el lugar.',
    ),
    HelpItem(
      '¿Puedo crear un perfil para alguien sin cuenta?',
      'Sí. El administrador crea el perfil y la persona puede vincular una cuenta después: en la tarjeta del perfil, toca Vincular con una cuenta para obtener un código temporal válido por 10 minutos. La persona lo escribe en Familia › Vincular a un perfil.',
    ),
    HelpItem(
      '¿Qué es la cuenta de visitante?',
      'Un perfil extra para visitas, que se activa y desactiva con el botón de arriba en la pestaña Familia. No ocupa lugar de miembro y nunca guarda favoritos, vistos ni progreso.',
    ),
  ]),
  HelpTopic('Infantil y PIN', [
    HelpItem(
      '¿Qué es un perfil Infantil?',
      'Un perfil que solo recibe contenido clasificado como infantil por el servidor de iPlex. El contenido adulto nunca aparece ahí. La clasificación depende de la información que envía el proveedor de la lista.',
    ),
    HelpItem(
      '¿Cómo convierto un perfil en Infantil?',
      'Solo el administrador puede hacerlo: en la pestaña Familia, abre la tarjeta del miembro y activa Cuenta infantil. Se conservan favoritos, historial y vínculos.',
    ),
    HelpItem(
      '¿Qué es el PIN personal?',
      'Un PIN de 4 dígitos que protege tu perfil. En la pestaña Familia, abre tu tarjeta y toca PIN personal para activarlo, cambiarlo o desactivarlo. Activado, el televisor lo pide para abrir tu perfil y para reproducir contenido adulto. Solo tú puedes definirlo.',
    ),
    HelpItem(
      '¿Cómo elijo qué puede ver cada miembro?',
      'En la pestaña Familia, abre la tarjeta del miembro. En Contenido, el administrador activa o desactiva Canales, Películas, Series y Contenido adulto, para todas las listas. Cada miembro puede desactivar Canales, Películas o Series para sí, pero solo el administrador decide sobre el contenido adulto.',
    ),
  ]),
  HelpTopic('Favoritos e historial', [
    HelpItem(
      '¿Dónde están mis favoritos y lo que estoy viendo?',
      'En el Inicio del celular y del televisor, en Favoritos, Seguir viendo y Lista de deseos. Todo se guarda en tu perfil y se sincroniza entre dispositivos.',
    ),
    HelpItem(
      '¿Cómo borro favoritos, vistos o el progreso?',
      'En la pestaña Familia, abre la tarjeta del perfil y toca la lista: Seguir viendo, Favoritos, Lista de deseos o Vistos. Arriba, toca el botón de borrar y confirma. El administrador borra las listas de cualquier perfil y cada miembro borra las suyas. El borrado es definitivo y llega a todos los televisores.',
    ),
  ]),
  HelpTopic('Suscripción', [
    HelpItem(
      '¿Hay prueba gratis?',
      'Sí. Son 7 días de reproducción gratis, que empiezan al vincular con éxito el primer televisor. La prueba se concede una sola vez.',
    ),
    HelpItem(
      '¿Cómo me suscribo?',
      'En Cuenta › Suscripción del Player aparecen los planes disponibles, mensual o anual, cobrados por Google Play con renovación automática. El precio mostrado es siempre el de la tienda. El administrador se suscribe para toda la familia.',
    ),
    HelpItem(
      '¿Cuántas personas pueden ver al mismo tiempo?',
      'Hasta 3 reproducciones simultáneas por familia, con un máximo de 1 por perfil.',
    ),
    HelpItem(
      '¿Cómo cancelo?',
      'En Google Play, en Pagos y suscripciones › Suscripciones. El acceso continúa hasta el final del período pagado. Eliminar la cuenta no cancela la suscripción en la tienda.',
    ),
    HelpItem(
      'Tengo un cupón. ¿Dónde lo uso?',
      'En Cuenta › Suscripción del Player, toca Canjear cupón y escribe el código. Los cupones válidos habilitan el acceso de por vida.',
    ),
    HelpItem(
      'Cambié de celular. ¿Cómo recupero mi suscripción?',
      'Inicia sesión con la misma cuenta y, en Cuenta › Suscripción del Player, toca Restaurar compras.',
    ),
  ]),
  HelpTopic('Cuenta', [
    HelpItem(
      '¿Cómo cambio el idioma?',
      'En Cuenta, en el campo Idioma, elige Português, English, Español o el idioma del sistema.',
    ),
    HelpItem(
      '¿Por qué no puedo hacer algunas acciones?',
      'Los miembros no realizan acciones administrativas, como invitar personas, cambiar permisos o gestionar la suscripción. Pídeselo al administrador de tu familia.',
    ),
    HelpItem(
      '¿Cómo comparto la app?',
      'En Cuenta, toca Compartir aplicación y elige WhatsApp, Telegram, correo u otra app. No es una invitación a la familia: para agregar a alguien, usa su código o su código QR.',
    ),
    HelpItem(
      '¿Cómo elimino mi cuenta?',
      'En Cuenta, toca Eliminar cuenta e inicia sesión de nuevo para confirmar. El administrador debe quitar a los miembros antes. Los datos se eliminan de forma permanente, pero una suscripción de Google Play debe cancelarse en la tienda.',
    ),
  ]),
];
