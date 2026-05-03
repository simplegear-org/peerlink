import 'package:flutter/widgets.dart';

import 'app_language.dart';
import 'dictionaries/app_strings_en.dart';
import 'dictionaries/app_strings_es.dart';
import 'dictionaries/app_strings_fr.dart';
import 'dictionaries/app_strings_ru.dart';
import 'dictionaries/app_strings_zh.dart';

class AppStrings {
  final AppLanguage currentLanguage;

  const AppStrings(this.currentLanguage);

  static const supportedLanguages = AppLanguage.values;
  static final supportedLocales = AppLanguage.values
      .map((language) => language.locale)
      .toList(growable: false);

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const _dictionaries = <AppLanguage, Map<String, String>>{
    AppLanguage.en: appStringsEn,
    AppLanguage.ru: appStringsRu,
    AppLanguage.es: appStringsEs,
    AppLanguage.zh: appStringsZh,
    AppLanguage.fr: appStringsFr,
  };

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(AppLanguage.ru);
  }

  Map<String, String> get _dictionary =>
      _dictionaries[currentLanguage] ?? appStringsRu;

  String _text(String key) => _dictionary[key] ?? appStringsEn[key] ?? key;

  String _format(String key, Map<String, Object?> values) {
    var result = _text(key);
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return result;
  }

  String get contacts => _text('contacts');
  String get chats => _text('chats');
  String get calls => _text('calls');
  String get settings => _text('settings');
  String get invite => _text('invite');
  String get cancel => _text('cancel');
  String get add => _text('add');
  String get create => _text('create');
  String get delete => _text('delete');
  String get save => _text('save');
  String get close => _text('close');
  String get retry => _text('retry');
  String get name => _text('name');
  String get peerId => _text('peerId');
  String get language => _text('language');
  String get languageDescription => _text('languageDescription');
  String get launchPreparing => _text('launchPreparing');
  String get launchStorage => _text('launchStorage');
  String get launchFirebase => _text('launchFirebase');
  String get launchFcm => _text('launchFcm');
  String get launchNotifications => _text('launchNotifications');
  String get launchNetwork => _text('launchNetwork');
  String get launchUi => _text('launchUi');
  String get launchDone => _text('launchDone');
  String get launchingPeerLink => _text('launchingPeerLink');
  String launchError(Object error) => _format('launchError', {'error': error});
  String get newContact => _text('newContact');
  String get invitePlaceholder => _text('invitePlaceholder');
  String get inviteTitle => _text('inviteTitle');
  String get inviteDescription => _text('inviteDescription');
  String inviteShareText(String peerId, String inviteLink) =>
      _format('inviteShareText', {'peerId': peerId, 'inviteLink': inviteLink});
  String get deleteContactTitle => _text('deleteContactTitle');
  String deleteContactContent(String contactName) =>
      _format('deleteContactContent', {'contactName': contactName});
  String get renameContact => _text('renameContact');
  String contactRenamed(String name) =>
      _format('contactRenamed', {'name': name});
  String get contactsEmptyTitle => _text('contactsEmptyTitle');
  String get contactsEmptySubtitle => _text('contactsEmptySubtitle');
  String get noMessages => _text('noMessages');
  String get newChat => _text('newChat');
  String get directChat => _text('directChat');
  String get groupChat => _text('groupChat');
  String get addContactsFirst => _text('addContactsFirst');
  String get createGroupChat => _text('createGroupChat');
  String get creatingGroupChat => _text('creatingGroupChat');
  String get chatName => _text('chatName');
  String get members => _text('members');
  String get deleteChatTitle => _text('deleteChatTitle');
  String deleteChatContent(String chatName) =>
      _format('deleteChatContent', {'chatName': chatName});
  String deleteGroupChatContent(String chatName) =>
      _format('deleteGroupChatContent', {'chatName': chatName});
  String deleteGroupChatLocalContent(String chatName) =>
      _format('deleteGroupChatLocalContent', {'chatName': chatName});
  String deleteChatError(Object error) =>
      _format('deleteChatError', {'error': error});
  String get chatsEmptyTitle => _text('chatsEmptyTitle');
  String get chatsEmptySubtitle => _text('chatsEmptySubtitle');
  String get callHistoryEmptyTitle => _text('callHistoryEmptyTitle');
  String get callHistoryEmptySubtitle => _text('callHistoryEmptySubtitle');
  String get callBack => _text('callBack');
  String get openChat => _text('openChat');
  String get deleteFromHistory => _text('deleteFromHistory');
  String get deleteEntryTitle => _text('deleteEntryTitle');
  String get deleteMissedGroupMessage => _text('deleteMissedGroupMessage');
  String get deleteCallMessage => _text('deleteCallMessage');
  String get missedGroupDeleted => _text('missedGroupDeleted');
  String get callDeleted => _text('callDeleted');
  String missedCalls(int count) => _format('missedCalls', {'count': count});
  String missedInARow(int count) => _format('missedInARow', {'count': count});
  String callStartError(Object error) =>
      _format('callStartError', {'error': error});
  String get incoming => _text('incoming');
  String get outgoing => _text('outgoing');
  String get missed => _text('missed');
  String get rejected => _text('rejected');
  String get ended => _text('ended');
  String get canceled => _text('canceled');
  String get busy => _text('busy');
  String get callError => _text('callError');
  String get noDuration => _text('noDuration');
  String get connecting => _text('connecting');
  String get connectionError => _text('connectionError');
  String get offline => _text('offline');
  String get online => _text('online');
  String get lastSeenJustNow => _text('lastSeenJustNow');
  String lastSeenMinutes(int minutes) =>
      _format('lastSeenMinutes', {'minutes': minutes});
  String lastSeenHours(int hours) => _format('lastSeenHours', {'hours': hours});
  String lastSeenAt(String day, String month, String hour, String minute) =>
      _format('lastSeenAt', {
        'day': day,
        'month': month,
        'hour': hour,
        'minute': minute,
      });
  String get appAppearance => _text('appAppearance');
  String get appAppearanceDescription => _text('appAppearanceDescription');
  String get appLog => _text('appLog');
  String get appLogDescription => _text('appLogDescription');
  String get showLog => _text('showLog');
  String get shareLog => _text('shareLog');
  String get clearLog => _text('clearLog');
  String get logEmpty => _text('logEmpty');
  String get logCleared => _text('logCleared');
  String version(String version) => _format('version', {'version': version});
  String get serverQrTitle => _text('serverQrTitle');
  String get serverQrDescription => _text('serverQrDescription');
  String get scanServerQr => _text('scanServerQr');
  String get shareConfig => _text('shareConfig');
  String get importConfig => _text('importConfig');
  String importConfigFound({
    required int bootstrap,
    required int relay,
    required int turn,
  }) => _format('importConfigFound', {
    'bootstrap': bootstrap,
    'relay': relay,
    'turn': turn,
  });
  String importConfigMergeAdds({
    required int bootstrap,
    required int relay,
    required int turn,
  }) => _format('importConfigMergeAdds', {
    'bootstrap': bootstrap,
    'relay': relay,
    'turn': turn,
  });
  String get importConfigReplaceWarning => _text('importConfigReplaceWarning');
  String get merge => _text('merge');
  String get replace => _text('replace');
  String get serverSettingsReplaced => _text('serverSettingsReplaced');
  String get serverSettingsMerged => _text('serverSettingsMerged');
  String get storage => _text('storage');
  String storageUsed(String value) => _format('storageUsed', {'value': value});
  String get storageDescription => _text('storageDescription');
  String get installOwnServerStack => _text('installOwnServerStack');
  String get installOwnServerStackDescription =>
      _text('installOwnServerStackDescription');
  String get installOwnService => _text('installOwnService');
  String addServerTitle(String server) =>
      _format('addServerTitle', {'server': server});
  String deleteServerTitle(String server) =>
      _format('deleteServerTitle', {'server': server});
  String deleteServerContent(String server, String endpoint) =>
      _format('deleteServerContent', {'server': server, 'endpoint': endpoint});
  String qrReadError(Object error) => _format('qrReadError', {'error': error});
  String get avatarUpdated => _text('avatarUpdated');
  String avatarSaveError(Object error) =>
      _format('avatarSaveError', {'error': error});
  String get deleteAvatarTitle => _text('deleteAvatarTitle');
  String get deleteAvatarDescription => _text('deleteAvatarDescription');
  String get avatarDeleted => _text('avatarDeleted');
  String get takePhoto => _text('takePhoto');
  String get chooseFromGallery => _text('chooseFromGallery');
  String get deleteAvatar => _text('deleteAvatar');
  String get avatarHint => _text('avatarHint');
  String get bootstrapSummary => _text('bootstrapSummary');
  String get relaySummary => _text('relaySummary');
  String get turnSummary => _text('turnSummary');
  String get serverConfigFormat => _text('serverConfigFormat');
  String get bootstrapServersTitle => _text('bootstrapServersTitle');
  String get bootstrapServersDescription =>
      _text('bootstrapServersDescription');
  String get relayServersTitle => _text('relayServersTitle');
  String get relayServersDescription => _text('relayServersDescription');
  String get turnServersTitle => _text('turnServersTitle');
  String get turnServersDescription => _text('turnServersDescription');
  String get allServers => _text('allServers');
  String get swipeToDeleteHint => _text('swipeToDeleteHint');
  String serverListEmpty(String server) =>
      _format('serverListEmpty', {'server': server});
  String statusPrefix(String value) =>
      _format('statusPrefix', {'value': value});
  String get noPassword => _text('noPassword');
  String maskedPassword(String mask) =>
      _format('maskedPassword', {'mask': mask});
  String serverAvailable({required bool active}) =>
      _text(active ? 'serverAvailableActive' : 'serverAvailable');
  String serverUnavailable({required bool active}) =>
      _text(active ? 'serverUnavailableActive' : 'serverUnavailable');
  String get serverCheckPending => _text('serverCheckPending');
  String serverConnected(String base) =>
      _format('serverConnected', {'base': base});
  String serverConnecting(String base) =>
      _format('serverConnecting', {'base': base});
  String serverDisconnected(String base) =>
      _format('serverDisconnected', {'base': base});
  String serverError(String base, String? error) {
    if (error == null || error.trim().isEmpty) {
      return _format('serverError', {'base': base});
    }
    return _format('serverErrorDetails', {'base': base, 'error': error});
  }

  String serverRuntimeUsed(String base) =>
      _format('serverRuntimeUsed', {'base': base});
  String serverRuntimeError(String base, String error) =>
      _format('serverRuntimeError', {'base': base, 'error': error});
  String get invalidAddress => _text('invalidAddress');
  String get dataCategories => _text('dataCategories');
  String get storageDetailsDescription => _text('storageDetailsDescription');
  String deleteStorageCategoryTitle(String title) =>
      _format('deleteStorageCategoryTitle', {'title': title});
  String deletedStorageCategory(String title) =>
      _format('deletedStorageCategory', {'title': title});
  String get storageMediaFiles => _text('storageMediaFiles');
  String get storageMessagesDatabase => _text('storageMessagesDatabase');
  String get storageLogs => _text('storageLogs');
  String get storageSettingsAndServiceData =>
      _text('storageSettingsAndServiceData');
  String get storageMediaSubtitle => _text('storageMediaSubtitle');
  String get storageMessagesSubtitle => _text('storageMessagesSubtitle');
  String get storageLogsSubtitle => _text('storageLogsSubtitle');
  String get storageSettingsSubtitle => _text('storageSettingsSubtitle');
  String get storageMediaWarning => _text('storageMediaWarning');
  String get storageMessagesWarning => _text('storageMessagesWarning');
  String get storageLogsWarning => _text('storageLogsWarning');
  String get storageSettingsWarning => _text('storageSettingsWarning');
  String get storageMediaInlineWarning => _text('storageMediaInlineWarning');
  String get storageMessagesInlineWarning =>
      _text('storageMessagesInlineWarning');
  String get storageLogsInlineWarning => _text('storageLogsInlineWarning');
  String get storageSettingsInlineWarning =>
      _text('storageSettingsInlineWarning');
  String get scanQr => _text('scanQr');
  String get scanQrHintTitle => _text('scanQrHintTitle');
  String get scanQrHintSubtitle => _text('scanQrHintSubtitle');
  String get sharePeer => _text('sharePeer');
  String get nodeQrCode => _text('nodeQrCode');
  String imageOpenError(Object error) =>
      _format('imageOpenError', {'error': error});
  String get crop => _text('crop');
  String get cropAvatar => _text('cropAvatar');
  String get imageLoadError => _text('imageLoadError');
  String get avatarCropInstruction => _text('avatarCropInstruction');
  String get apply => _text('apply');
  String frontCameraOpenError(Object error) =>
      _format('frontCameraOpenError', {'error': error});
  String captureError(Object error) =>
      _format('captureError', {'error': error});
  String get avatarSnapshot => _text('avatarSnapshot');
  String get saving => _text('saving');
  String get takeSnapshot => _text('takeSnapshot');
  String get previewUnavailable => _text('previewUnavailable');
  String get imageUnavailable => _text('imageUnavailable');
  String get videoNotLoaded => _text('videoNotLoaded');
  String get videoUnavailable => _text('videoUnavailable');
  String get videoSourceUnavailable => _text('videoSourceUnavailable');
  String videoOpenError(Object error) =>
      _format('videoOpenError', {'error': error});
  String get serverHostLabel => _text('serverHostLabel');
  String get login => _text('login');
  String get password => _text('password');
  String get install => _text('install');
  String get fillServerLoginPassword => _text('fillServerLoginPassword');
  String get preparingInstall => _text('preparingInstall');
  String get servicesAddedToConfig => _text('servicesAddedToConfig');
  String deployErrorLog(Object error) =>
      _format('deployErrorLog', {'error': error});
  String deployingService(String elapsed) =>
      _format('deployingService', {'elapsed': elapsed});
  String get running => _text('running');
  String get ownServersDeployed => _text('ownServersDeployed');
  String deployFailed(Object error) =>
      _format('deployFailed', {'error': error});
  String get sending => _text('sending');
  String get sent => _text('sent');
  String get sendError => _text('sendError');
  String get relayFetching => _text('relayFetching');
  String get retryDownload => _text('retryDownload');
  String get downloadError => _text('downloadError');
  String get you => _text('you');
  String get voiceMessage => _text('voiceMessage');
  String get photo => _text('photo');
  String get video => _text('video');
  String get file => _text('file');
  String get message => _text('message');
  String groupMembers(int count) => _format('groupMembers', {'count': count});
  String get addParticipants => _text('addParticipants');
  String get removeParticipants => _text('removeParticipants');
  String get renameChat => _text('renameChat');
  String get addAvatar => _text('addAvatar');
  String get deleteDialog => _text('deleteDialog');
  String get groupCallsUnsupported => _text('groupCallsUnsupported');
  String startCallError(Object error) =>
      _format('startCallError', {'error': error});
  String get chatAvatarUpdated => _text('chatAvatarUpdated');
  String chatAvatarUpdateError(Object error) =>
      _format('chatAvatarUpdateError', {'error': error});
  String get notGroupMember => _text('notGroupMember');
  String get noMicAccess => _text('noMicAccess');
  String startRecordError(Object error) =>
      _format('startRecordError', {'error': error});
  String stopRecordError(Object error) =>
      _format('stopRecordError', {'error': error});
  String sendVoiceError(Object error) =>
      _format('sendVoiceError', {'error': error});
  String get sourceMessageNotFoundLocal => _text('sourceMessageNotFoundLocal');
  String get sourceMessageNotFoundCurrent =>
      _text('sourceMessageNotFoundCurrent');
  String get sourceMessageJumpFailed => _text('sourceMessageJumpFailed');
  String get cancelSending => _text('cancelSending');
  String get cancelSendingDescription => _text('cancelSendingDescription');
  String get deleteMessage => _text('deleteMessage');
  String get deleteMessageDescription => _text('deleteMessageDescription');
  String get addContact => _text('addContact');
  String get resend => _text('resend');
  String get deleteForMe => _text('deleteForMe');
  String get deleteForEveryone => _text('deleteForEveryone');
  String get onlyAuthorCanDeleteForPeer => _text('onlyAuthorCanDeleteForPeer');
  String get contactName => _text('contactName');
  String contactAdded(String name) => _format('contactAdded', {'name': name});
  String get noContactsToAdd => _text('noContactsToAdd');
  String get participantsAdded => _text('participantsAdded');
  String get chatNameLabel => _text('chatNameLabel');
  String get noParticipantsToRemove => _text('noParticipantsToRemove');
  String get noParticipantsToSend => _text('noParticipantsToSend');
  String get participantsRemoved => _text('participantsRemoved');
  String get deleteDialogDescription => _text('deleteDialogDescription');
  String get gallery => _text('gallery');
  String get location => _text('location');
  String get fileSendingPlaceholder => _text('fileSendingPlaceholder');
  String get locationPlaceholder => _text('locationPlaceholder');
  String get scrollUpToLoadOlder => _text('scrollUpToLoadOlder');
  String loadedOlderMessages(int count) =>
      _format('loadedOlderMessages', {'count': count});
  String get firstMessages => _text('firstMessages');
  String get mediaStillLoading => _text('mediaStillLoading');
  String get mediaUnavailable => _text('mediaUnavailable');
  String get fileUnavailableOpen => _text('fileUnavailableOpen');
  String get fileTooLarge => _text('fileTooLarge');
  String addFilesFailed(int failed, int total, String? error) => _format(
    error == null ? 'addFilesFailed' : 'addFilesFailedWithError',
    {'failed': failed, 'total': total, 'error': error ?? ''},
  );
  String replyTo(String sender) => _format('replyTo', {'sender': sender});
  String get replyToMessage => _text('replyToMessage');
  String get cancelReply => _text('cancelReply');
  String recording(String duration) =>
      _format('recording', {'duration': duration});
  String get voiceReady => _text('voiceReady');
  String get messageHint => _text('messageHint');
  String get unread => _text('unread');
  String get status => _text('status');
  String get channel => _text('channel');
  String get answer => _text('answer');
  String get decline => _text('decline');
  String get calling => _text('calling');
  String get incomingCall => _text('incomingCall');
  String get establishingConnection => _text('establishingConnection');
  String get waitingForAnswer => _text('waitingForAnswer');
  String get peerCallingYou => _text('peerCallingYou');
  String get preparingCallTransport => _text('preparingCallTransport');
  String get dialling => _text('dialling');
  String get connected => _text('connected');
  String get waiting => _text('waiting');

  String translateTransferStatus(String? status) {
    switch (status) {
      case 'В очереди':
      case 'Подготовка':
      case 'Загрузка в relay':
      case 'Ожидает отправки':
        return sending;
      case 'Отправлено':
      case 'Загрузка завершена':
        return sent;
      case 'Ошибка отправки':
        return sendError;
      case 'Получение из relay':
      case 'Загрузка':
      case 'Расшифровка':
      case 'Сохранение':
        return relayFetching;
      case 'Повторная загрузка':
        return retryDownload;
      case 'Ошибка загрузки':
        return downloadError;
      case 'Файл недоступен':
      case 'Не удалось прочитать файл':
        return mediaUnavailable;
      case 'Вы больше не участник чата':
        return notGroupMember;
      case 'Нет участников для отправки':
        return noParticipantsToSend;
      case 'Отменено':
        return canceled;
      case null:
        return sending;
      default:
        if (status.startsWith('Ожидает отправки')) {
          return sending;
        }
        return status;
    }
  }
}

extension AppStringsBuildContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLanguage.values.any(
      (language) => language.code == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(AppLanguage.fromCode(locale.languageCode));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}
