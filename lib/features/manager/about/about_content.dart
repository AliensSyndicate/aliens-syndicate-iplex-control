/// Content of the About page, per language (same topics as the other
/// Aliens Syndicate apps). Keep it faithful to what the app does.
class AboutContent {
  const AboutContent({
    required this.tagline,
    required this.versionTitle,
    required this.loading,
    required this.build,
    required this.sections,
  });
  final String tagline, versionTitle, loading, build;

  /// (title, body) pairs; the version section goes after the second one.
  final List<(String, String)> sections;
}

/// Content for [languageCode] (`pt`, `es`; anything else gets English).
AboutContent aboutContent(String languageCode) => switch (languageCode) {
  'pt' => _pt,
  'es' => _es,
  _ => _en,
};

const _pt = AboutContent(
  tagline: 'Suas listas IPTV organizadas para toda a família, na sua TV.',
  versionTitle: 'Versão',
  loading: 'Carregando…',
  build: 'build',
  sections: [
    (
      'Sobre o app',
      'O iPlex organiza as listas IPTV que você adiciona e leva o conteúdo para a sua TV. Pelo celular você administra a família, os perfis, as TVs vinculadas e as listas. A reprodução acontece no iPlex da TV. O iPlex é somente um player: não oferece, vende nem indica listas IPTV.',
    ),
    ('Desenvolvido por', 'Aliens Syndicate Inc.'),
    (
      'Tecnologia',
      'Desenvolvido com Flutter e Dart, com serviços do Google Firebase para conta, sincronização e segurança, oferecendo uma experiência rápida e consistente no celular e na TV.',
    ),
    (
      'Armazenamento',
      'Conta, família, perfis, TVs, listas IPTV e a atividade de cada perfil ficam no servidor do iPlex, sincronizados entre os seus aparelhos. Usuário e senha das listas são guardados criptografados. No celular ficam apenas preferências e o cache de imagens.',
    ),
    (
      'Privacidade',
      'O iPlex não exibe publicidade e não vende dados pessoais. A câmera é usada só para ler QR Codes, e as notificações só avisam sobre a sincronização das listas. Os detalhes estão na Política de Privacidade.',
    ),
    (
      'Compatibilidade',
      'O gestor está disponível para Android e iOS. Na TV, o conteúdo é reproduzido pelo iPlex Player em Smart TVs compatíveis. A disponibilidade do conteúdo depende das listas e dos provedores que você usa.',
    ),
  ],
);

const _en = AboutContent(
  tagline: 'Your IPTV lists organized for the whole family, on your TV.',
  versionTitle: 'Version',
  loading: 'Loading…',
  build: 'build',
  sections: [
    (
      'About the app',
      'iPlex organizes the IPTV lists you add and brings the content to your TV. On the phone you manage your family, profiles, linked TVs and lists. Playback happens in iPlex on the TV. iPlex is only a player: it does not offer, sell or recommend IPTV lists.',
    ),
    ('Developed by', 'Aliens Syndicate Inc.'),
    (
      'Technology',
      'Built with Flutter and Dart, with Google Firebase services for accounts, syncing and security, for a fast and consistent experience on the phone and the TV.',
    ),
    (
      'Storage',
      'Account, family, profiles, TVs, IPTV lists and each profile’s activity are kept on the iPlex server and synced across your devices. List usernames and passwords are stored encrypted. The phone keeps only preferences and the image cache.',
    ),
    (
      'Privacy',
      'iPlex shows no ads and does not sell personal data. The camera is used only to scan QR codes, and notifications only report list syncing. Details are in the Privacy Policy.',
    ),
    (
      'Compatibility',
      'The manager is available for Android and iOS. On the TV, content is played by iPlex Player on compatible smart TVs. Content availability depends on the lists and providers you use.',
    ),
  ],
);

const _es = AboutContent(
  tagline: 'Tus listas IPTV organizadas para toda la familia, en tu televisor.',
  versionTitle: 'Versión',
  loading: 'Cargando…',
  build: 'build',
  sections: [
    (
      'Acerca de la app',
      'iPlex organiza las listas IPTV que agregas y lleva el contenido a tu televisor. Desde el celular administras la familia, los perfiles, los televisores vinculados y las listas. La reproducción ocurre en iPlex del televisor. iPlex es solo un reproductor: no ofrece, vende ni recomienda listas IPTV.',
    ),
    ('Desarrollado por', 'Aliens Syndicate Inc.'),
    (
      'Tecnología',
      'Desarrollado con Flutter y Dart, con servicios de Google Firebase para cuentas, sincronización y seguridad, para una experiencia rápida y consistente en el celular y el televisor.',
    ),
    (
      'Almacenamiento',
      'La cuenta, la familia, los perfiles, los televisores, las listas IPTV y la actividad de cada perfil se guardan en el servidor de iPlex y se sincronizan entre tus dispositivos. El usuario y la contraseña de las listas se guardan cifrados. En el celular solo quedan las preferencias y la caché de imágenes.',
    ),
    (
      'Privacidad',
      'iPlex no muestra publicidad ni vende datos personales. La cámara se usa solo para escanear códigos QR y las notificaciones solo avisan sobre la sincronización de las listas. Los detalles están en la Política de Privacidad.',
    ),
    (
      'Compatibilidad',
      'El gestor está disponible para Android e iOS. En el televisor, el contenido se reproduce con iPlex Player en Smart TV compatibles. La disponibilidad del contenido depende de las listas y los proveedores que uses.',
    ),
  ],
);
