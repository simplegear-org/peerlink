const supportedLanguages = ['en', 'ru', 'es', 'zh', 'fr'];
const fallbackLanguage = 'en';
const payload = new URLSearchParams(window.location.search).get('payload');
const openInviteLinks = Array.from(document.querySelectorAll('#open-invite-link'));
const inviteCard = document.getElementById('invite-card');
const trustCard = document.getElementById('trust-card');
const inviteMessage = document.getElementById('invite-message');
const page = document.body.dataset.page || 'home';

const strings = {
  en: {
    common: {
      languageAria: 'Language',
      download: 'Download',
      sourceCode: 'Source code',
      openPeerLink: 'Open PeerLink',
      aboutPeerLink: 'About PeerLink',
      appRepository: 'PeerLink app repository',
      serverRepository: 'PeerLink servers repository',
      appStore: 'App Store',
      googlePlay: 'Google Play',
      comingSoon: 'coming soon',
    },
    home: {
      metaTitle: 'PeerLink Messenger',
      metaDescription: 'PeerLink is an open-source messenger for private chats, calls, media, and self-hosted communication infrastructure.',
      heroEyebrow: 'Open-source secure messenger',
      lead: 'Private direct and group messaging, calls, media sharing, and self-hosted communication servers.',
      trustTitle: 'Nothing hidden',
      trustBody: 'PeerLink keeps the app and server code public so anyone can inspect how communication works.',
      privateTitle: 'Private by design',
      privateBody: 'PeerLink focuses on peer identity, encrypted messaging, calls, and media without hiding the implementation.',
      selfHostTitle: 'Self-host friendly',
      selfHostBody: 'Run your own bootstrap, relay, and TURN servers when you want control over the infrastructure path.',
      resilientTitle: 'Resilient delivery',
      resilientBody: 'Relay-assisted messages and media help peers reconnect and recover across network changes.',
      aboutTitle: 'About PeerLink',
      aboutBody: 'PeerLink is a private open-source messenger for direct chats, group chats, calls, media, and self-hosted network servers.',
      sourceEyebrow: 'Open source',
      sourceTitle: 'Inspect the code yourself',
      sourceBody: 'We do not ask users to trust a black box. The mobile app and server stack are public.',
      downloadEyebrow: 'Download',
      downloadTitle: 'Store links',
      downloadBody: 'App Store and Google Play pages are coming. The buttons are placeholders for now.',
    },
    invite: {
      metaTitle: 'PeerLink Invite',
      metaDescription: 'Open a PeerLink invite or learn about the open-source PeerLink messenger.',
      heroEyebrow: 'PeerLink invite',
      title: 'Open PeerLink',
      lead: 'This page opens a PeerLink invite and also explains what the messenger does.',
      detectedTitle: 'Invite detected',
      openingMessage: 'Opening PeerLink. If nothing happens, tap the button.',
      missingMessage: 'No invite payload was found in this link.',
      missingButton: 'Go to PeerLink',
      sourceBody: 'The app and server repositories are public so the communication stack can be inspected.',
    },
    fallback: {
      metaTitle: 'PeerLink',
      metaDescription: 'Open a PeerLink invite or return to the PeerLink landing page.',
      eyebrow: 'PeerLink',
      title: 'Opening invite',
      lead: 'If this was an invite link, PeerLink will open automatically.',
      checkingTitle: 'Checking link',
      checkingMessage: 'Looking for an invite payload.',
      homeButton: 'Home',
    },
  },
  ru: {
    common: {
      languageAria: 'Язык',
      download: 'Скачать',
      sourceCode: 'Исходный код',
      openPeerLink: 'Открыть PeerLink',
      aboutPeerLink: 'О PeerLink',
      appRepository: 'Репозиторий приложения PeerLink',
      serverRepository: 'Репозиторий серверов PeerLink',
      appStore: 'App Store',
      googlePlay: 'Google Play',
      comingSoon: 'скоро',
    },
    home: {
      metaTitle: 'Мессенджер PeerLink',
      metaDescription: 'PeerLink — мессенджер с открытым исходным кодом для приватных чатов, звонков, медиа и собственной коммуникационной инфраструктуры.',
      heroEyebrow: 'Безопасный open-source мессенджер',
      lead: 'Личные и групповые сообщения, звонки, обмен медиа и собственные коммуникационные серверы.',
      trustTitle: 'Ничего не скрываем',
      trustBody: 'Код приложения и серверов PeerLink открыт, чтобы любой мог проверить, как устроена связь.',
      privateTitle: 'Приватность в основе',
      privateBody: 'PeerLink строится вокруг peer-идентичности, шифрованных сообщений, звонков и медиа без закрытой реализации.',
      selfHostTitle: 'Готов к self-host',
      selfHostBody: 'Можно поднять собственные bootstrap, relay и TURN-серверы, если нужен контроль над инфраструктурой.',
      resilientTitle: 'Устойчивая доставка',
      resilientBody: 'Relay-помощь для сообщений и медиа помогает пирам переподключаться и восстанавливаться после смены сети.',
      aboutTitle: 'О PeerLink',
      aboutBody: 'PeerLink — приватный мессенджер с открытым исходным кодом для личных и групповых чатов, звонков, медиа и собственных сетевых серверов.',
      sourceEyebrow: 'Open source',
      sourceTitle: 'Проверь код сам',
      sourceBody: 'Мы не просим доверять черному ящику. Код мобильного приложения и серверной части открыт.',
      downloadEyebrow: 'Скачать',
      downloadTitle: 'Ссылки на магазины',
      downloadBody: 'Страницы App Store и Google Play появятся позже. Пока кнопки работают как заглушки.',
    },
    invite: {
      metaTitle: 'Приглашение PeerLink',
      metaDescription: 'Откройте приглашение PeerLink или узнайте больше об open-source приватном мессенджере.',
      heroEyebrow: 'Приглашение PeerLink',
      title: 'Открыть PeerLink',
      lead: 'Эта страница открывает приглашение PeerLink и объясняет, что умеет мессенджер.',
      detectedTitle: 'Приглашение найдено',
      openingMessage: 'Открываем PeerLink. Если ничего не произошло, нажмите кнопку.',
      missingMessage: 'В этой ссылке не найден payload приглашения.',
      missingButton: 'Перейти к PeerLink',
      sourceBody: 'Репозитории приложения и серверов открыты, чтобы коммуникационный стек можно было проверить.',
    },
    fallback: {
      metaTitle: 'PeerLink',
      metaDescription: 'Откройте приглашение PeerLink или вернитесь на главную страницу PeerLink.',
      eyebrow: 'PeerLink',
      title: 'Открываем приглашение',
      lead: 'Если это была invite-ссылка, PeerLink откроется автоматически.',
      checkingTitle: 'Проверяем ссылку',
      checkingMessage: 'Ищем payload приглашения.',
      homeButton: 'Главная',
    },
  },
  es: {
    common: {
      languageAria: 'Idioma',
      download: 'Descargar',
      sourceCode: 'Código fuente',
      openPeerLink: 'Abrir PeerLink',
      aboutPeerLink: 'Acerca de PeerLink',
      appRepository: 'Repositorio de la app PeerLink',
      serverRepository: 'Repositorio de servidores PeerLink',
      appStore: 'App Store',
      googlePlay: 'Google Play',
      comingSoon: 'próximamente',
    },
    home: {
      metaTitle: 'Mensajero PeerLink',
      metaDescription: 'PeerLink es un mensajero de código abierto para chats privados, llamadas, multimedia e infraestructura de comunicación autoalojada.',
      heroEyebrow: 'Mensajero seguro de código abierto',
      lead: 'Mensajes directos y grupales, llamadas, multimedia y servidores de comunicación autoalojados.',
      trustTitle: 'Nada oculto',
      trustBody: 'PeerLink mantiene público el código de la app y los servidores para que cualquiera pueda revisar cómo funciona la comunicación.',
      privateTitle: 'Privado por diseño',
      privateBody: 'PeerLink se centra en la identidad peer, mensajes cifrados, llamadas y multimedia sin ocultar la implementación.',
      selfHostTitle: 'Listo para self-host',
      selfHostBody: 'Ejecuta tus propios servidores bootstrap, relay y TURN cuando quieras controlar la ruta de infraestructura.',
      resilientTitle: 'Entrega resistente',
      resilientBody: 'Los mensajes y medios asistidos por relay ayudan a los peers a reconectarse y recuperarse ante cambios de red.',
      aboutTitle: 'Acerca de PeerLink',
      aboutBody: 'PeerLink es un mensajero privado de código abierto para chats directos y grupales, llamadas, archivos multimedia y servidores propios.',
      sourceEyebrow: 'Open source',
      sourceTitle: 'Inspecciona el código',
      sourceBody: 'No pedimos confiar en una caja negra. La app móvil y la pila de servidores son públicas.',
      downloadEyebrow: 'Descargar',
      downloadTitle: 'Enlaces de tiendas',
      downloadBody: 'Las páginas de App Store y Google Play llegarán pronto. Por ahora los botones son marcadores.',
    },
    invite: {
      metaTitle: 'Invitación PeerLink',
      metaDescription: 'Abre una invitación de PeerLink o conoce el mensajero privado de código abierto.',
      heroEyebrow: 'Invitación PeerLink',
      title: 'Abrir PeerLink',
      lead: 'Esta página abre una invitación de PeerLink y también explica qué hace el mensajero.',
      detectedTitle: 'Invitación detectada',
      openingMessage: 'Abriendo PeerLink. Si no sucede nada, toca el botón.',
      missingMessage: 'No se encontró payload de invitación en este enlace.',
      missingButton: 'Ir a PeerLink',
      sourceBody: 'Los repositorios de la app y los servidores son públicos para poder revisar la pila de comunicación.',
    },
    fallback: {
      metaTitle: 'PeerLink',
      metaDescription: 'Abre una invitación de PeerLink o vuelve a la página principal.',
      eyebrow: 'PeerLink',
      title: 'Abriendo invitación',
      lead: 'Si era un enlace de invitación, PeerLink se abrirá automáticamente.',
      checkingTitle: 'Revisando enlace',
      checkingMessage: 'Buscando el payload de invitación.',
      homeButton: 'Inicio',
    },
  },
  zh: {
    common: {
      languageAria: '语言',
      download: '下载',
      sourceCode: '源代码',
      openPeerLink: '打开 PeerLink',
      aboutPeerLink: '关于 PeerLink',
      appRepository: 'PeerLink 应用仓库',
      serverRepository: 'PeerLink 服务器仓库',
      appStore: 'App Store',
      googlePlay: 'Google Play',
      comingSoon: '即将推出',
    },
    home: {
      metaTitle: 'PeerLink 通讯应用',
      metaDescription: 'PeerLink 是一款开源通讯应用，支持私密聊天、通话、媒体分享和自托管通信基础设施。',
      heroEyebrow: '开源安全通讯应用',
      lead: '私聊、群聊、通话、媒体分享，以及可自托管的通信服务器。',
      trustTitle: '没有隐藏',
      trustBody: 'PeerLink 公开应用和服务器代码，让任何人都能检查通信方式。',
      privateTitle: '以隐私为核心',
      privateBody: 'PeerLink 专注于 peer 身份、加密消息、通话和媒体，并公开实现细节。',
      selfHostTitle: '适合自托管',
      selfHostBody: '当你需要控制基础设施路径时，可以运行自己的 bootstrap、relay 和 TURN 服务器。',
      resilientTitle: '可靠投递',
      resilientBody: 'relay 辅助的消息和媒体可帮助 peer 在网络变化后重新连接和恢复。',
      aboutTitle: '关于 PeerLink',
      aboutBody: 'PeerLink 是一款开源隐私通讯应用，支持私聊、群聊、通话、媒体分享以及自托管网络服务器。',
      sourceEyebrow: '开源',
      sourceTitle: '自己查看代码',
      sourceBody: '我们不要求用户信任黑盒。移动应用和服务器栈都是公开的。',
      downloadEyebrow: '下载',
      downloadTitle: '应用商店链接',
      downloadBody: 'App Store 和 Google Play 页面即将推出。当前按钮暂为占位。',
    },
    invite: {
      metaTitle: 'PeerLink 邀请',
      metaDescription: '打开 PeerLink 邀请，或了解这款开源隐私通讯应用。',
      heroEyebrow: 'PeerLink 邀请',
      title: '打开 PeerLink',
      lead: '此页面会打开 PeerLink 邀请，并说明这款通讯应用的用途。',
      detectedTitle: '检测到邀请',
      openingMessage: '正在打开 PeerLink。如果没有反应，请点击按钮。',
      missingMessage: '此链接中没有找到邀请 payload。',
      missingButton: '前往 PeerLink',
      sourceBody: '应用和服务器仓库都是公开的，因此可以检查整个通信栈。',
    },
    fallback: {
      metaTitle: 'PeerLink',
      metaDescription: '打开 PeerLink 邀请或返回 PeerLink 主页。',
      eyebrow: 'PeerLink',
      title: '正在打开邀请',
      lead: '如果这是邀请链接，PeerLink 会自动打开。',
      checkingTitle: '正在检查链接',
      checkingMessage: '正在查找邀请 payload。',
      homeButton: '主页',
    },
  },
  fr: {
    common: {
      languageAria: 'Langue',
      download: 'Télécharger',
      sourceCode: 'Code source',
      openPeerLink: 'Ouvrir PeerLink',
      aboutPeerLink: 'À propos de PeerLink',
      appRepository: 'Dépôt de l’app PeerLink',
      serverRepository: 'Dépôt des serveurs PeerLink',
      appStore: 'App Store',
      googlePlay: 'Google Play',
      comingSoon: 'bientôt',
    },
    home: {
      metaTitle: 'Messagerie PeerLink',
      metaDescription: 'PeerLink est une messagerie open source pour les discussions privées, les appels, les médias et l’infrastructure auto-hébergée.',
      heroEyebrow: 'Messagerie sécurisée open source',
      lead: 'Messages directs et de groupe, appels, partage de médias et serveurs de communication auto-hébergés.',
      trustTitle: 'Rien de caché',
      trustBody: 'PeerLink garde le code de l’app et des serveurs public afin que chacun puisse inspecter le fonctionnement des communications.',
      privateTitle: 'Privé par conception',
      privateBody: 'PeerLink met l’accent sur l’identité peer, les messages chiffrés, les appels et les médias sans cacher l’implémentation.',
      selfHostTitle: 'Pensé pour le self-host',
      selfHostBody: 'Lance tes propres serveurs bootstrap, relay et TURN lorsque tu veux contrôler le chemin d’infrastructure.',
      resilientTitle: 'Livraison robuste',
      resilientBody: 'Les messages et médias assistés par relay aident les peers à se reconnecter et récupérer lors des changements réseau.',
      aboutTitle: 'À propos de PeerLink',
      aboutBody: 'PeerLink est une messagerie privée open source pour les discussions directes et de groupe, les appels, les médias et les serveurs auto-hébergés.',
      sourceEyebrow: 'Open source',
      sourceTitle: 'Inspecter le code',
      sourceBody: 'Nous ne demandons pas de faire confiance à une boîte noire. L’app mobile et la pile serveur sont publiques.',
      downloadEyebrow: 'Télécharger',
      downloadTitle: 'Liens des stores',
      downloadBody: 'Les pages App Store et Google Play arrivent. Pour l’instant, les boutons sont des placeholders.',
    },
    invite: {
      metaTitle: 'Invitation PeerLink',
      metaDescription: 'Ouvrez une invitation PeerLink ou découvrez la messagerie privée open source.',
      heroEyebrow: 'Invitation PeerLink',
      title: 'Ouvrir PeerLink',
      lead: 'Cette page ouvre une invitation PeerLink et explique aussi ce que fait la messagerie.',
      detectedTitle: 'Invitation détectée',
      openingMessage: 'Ouverture de PeerLink. Si rien ne se passe, touchez le bouton.',
      missingMessage: 'Aucun payload d’invitation n’a été trouvé dans ce lien.',
      missingButton: 'Aller à PeerLink',
      sourceBody: 'Les dépôts de l’app et des serveurs sont publics afin que la pile de communication puisse être inspectée.',
    },
    fallback: {
      metaTitle: 'PeerLink',
      metaDescription: 'Ouvrez une invitation PeerLink ou revenez à la page d’accueil PeerLink.',
      eyebrow: 'PeerLink',
      title: 'Ouverture de l’invitation',
      lead: 'Si c’était un lien d’invitation, PeerLink s’ouvrira automatiquement.',
      checkingTitle: 'Vérification du lien',
      checkingMessage: 'Recherche du payload d’invitation.',
      homeButton: 'Accueil',
    },
  },
};

function readKey(language, key) {
  return key.split('.').reduce((value, part) => value?.[part], strings[language]);
}

function translate(key, language) {
  return readKey(language, key) ?? readKey(fallbackLanguage, key) ?? key;
}

function normalizeLanguage(language) {
  const shortCode = (language || '').slice(0, 2).toLowerCase();
  return supportedLanguages.includes(shortCode) ? shortCode : fallbackLanguage;
}

function preferredLanguage() {
  const queryLanguage = new URLSearchParams(window.location.search).get('lang');
  if (queryLanguage) {
    return normalizeLanguage(queryLanguage);
  }
  const savedLanguage = readSavedLanguage();
  if (savedLanguage) {
    return normalizeLanguage(savedLanguage);
  }
  return normalizeLanguage(window.navigator.language);
}

function readSavedLanguage() {
  try {
    return window.localStorage.getItem('peerlink.site.language');
  } catch (_) {
    return null;
  }
}

function saveLanguage(language) {
  try {
    window.localStorage.setItem('peerlink.site.language', language);
  } catch (_) {
    // Some browsers block storage for static pages; language switching must still work.
  }
}

function setMeta(name, content) {
  const node = document.querySelector(`meta[name="${name}"]`);
  if (node) {
    node.setAttribute('content', content);
  }
}

function setOpenGraph(property, content) {
  const node = document.querySelector(`meta[property="${property}"]`);
  if (node) {
    node.setAttribute('content', content);
  }
}

function applyLanguage(language) {
  const activeLanguage = normalizeLanguage(language);
  document.documentElement.lang = activeLanguage;
  saveLanguage(activeLanguage);

  document.querySelectorAll('[data-i18n]').forEach((node) => {
    node.textContent = translate(node.dataset.i18n, activeLanguage);
  });

  document.querySelectorAll('[data-i18n-attr]').forEach((node) => {
    node.dataset.i18nAttr.split(',').forEach((entry) => {
      const [attribute, key] = entry.split(':').map((value) => value.trim());
      if (attribute && key) {
        node.setAttribute(attribute, translate(key, activeLanguage));
      }
    });
  });

  document.querySelectorAll('[data-current-lang]').forEach((node) => {
    node.textContent = activeLanguage.toUpperCase();
  });

  document.querySelectorAll('[data-lang]').forEach((button) => {
    const isActive = button.dataset.lang === activeLanguage;
    button.classList.toggle('active', isActive);
    button.setAttribute('aria-pressed', String(isActive));
  });

  const titleKey = `${page}.metaTitle`;
  const descriptionKey = `${page}.metaDescription`;
  const title = translate(titleKey, activeLanguage);
  const description = translate(descriptionKey, activeLanguage);
  document.title = title;
  setMeta('description', description);
  setOpenGraph('og:title', title);
  setOpenGraph('og:description', description);
}

function showInviteMissing() {
  if (inviteMessage) {
    inviteMessage.dataset.i18n = 'invite.missingMessage';
  }
  openInviteLinks.forEach((link) => {
    link.href = '/';
    link.dataset.i18n = 'invite.missingButton';
  });
}

function configureInviteLink() {
  if (payload) {
    const appLink = buildAppLinkFromPayload(payload);
    if (inviteCard) {
      inviteCard.hidden = false;
    }
    if (trustCard) {
      trustCard.hidden = true;
    }
    openInviteLinks.forEach((link) => {
      link.href = appLink;
    });
    window.setTimeout(() => {
      window.location.href = appLink;
    }, 350);
    return;
  }

  if (page === 'invite' || page === 'fallback') {
    showInviteMissing();
    return;
  }

  openInviteLinks.forEach((link) => {
    link.hidden = true;
  });
}

function buildAppLinkFromPayload(rawPayload) {
  const encodedPayload = encodeURIComponent(rawPayload);
  try {
    const normalized = rawPayload.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
    const decoded = atob(padded);
    const parsed = JSON.parse(decoded);
    if (!parsed || typeof parsed.type !== 'string') {
      return `peerlink://invite?payload=${encodedPayload}`;
    }
    if (parsed.type === 'peerlink_account_pairing') {
      return `peerlink://pair?payload=${encodedPayload}`;
    }
    if (parsed.type === 'peerlink_invite') {
      return `peerlink://invite?payload=${encodedPayload}`;
    }
    if (parsed.type === 'peerlink_server_config') {
      return `peerlink://config?payload=${encodedPayload}`;
    }
  } catch (_) {
    return `peerlink://invite?payload=${encodedPayload}`;
  }
  return `peerlink://invite?payload=${encodedPayload}`;
}

document.querySelectorAll('[data-lang]').forEach((button) => {
  button.addEventListener('click', () => {
    applyLanguage(button.dataset.lang);
  });
});

configureInviteLink();
applyLanguage(preferredLanguage());
