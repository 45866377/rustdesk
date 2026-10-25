// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:provider/provider.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter/services.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

final homeMainView = 0.obs;

const kTdBlue = Color(0xFF2E7CF6);
const kTdOrange = Color(0xFFF57C2E);
const kTdGreen = Color(0xFF2EAD5B);

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  void onUsePublicServerGuide() {
    const url = "https://rustdesk.com/pricing";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginOnly(left: em),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
            // ready && public
            // No need to show the guide if is custom client.
            if (!isIncomingOnly) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: Alignment.centerLeft)
                    .marginOnly(top: 2.0, left: 22.0),
              ],
            )
          : basicWidget()),
    ).paddingOnly(right: isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;

  final _pwdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    _pwdController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Obx(() => homeMainView.value == 1
              ? PeerTabPage()
              : _buildToDeskMain(context)),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: kTdBlue));

  Widget _buildToDeskMain(BuildContext context) {
    final model = gFFI.serverModel;
    return ChangeNotifierProvider.value(
      value: model,
      child: Consumer<ServerModel>(builder: (context, sm, child) {
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('同意被控制'),
                  SizedBox(height: 12),
                  _idRow(context, sm),
                  SizedBox(height: 10),
                  _passwordRow(context, sm),
                  SizedBox(height: 28),
                  _sectionTitle('远程控制设备'),
                  SizedBox(height: 12),
                  _connectRow(context),
                  SizedBox(height: 10),
                  _statusRow(),
                  SizedBox(height: 28),
                  _RecentSection(
                    onPick: (peer) {
                      _idController.id = peer.id;
                      onConnect();
                    },
                  ),
                  SizedBox(height: 40),
                  _footer(context),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _idRow(BuildContext context, ServerModel model) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('控制码', style: TextStyle(fontSize: 15, color: Colors.grey)),
        SizedBox(width: 20),
        Expanded(
          child: Text(model.serverId.text,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        ),
        PopupMenuButton<String>(
          tooltip: '复制选项',
          offset: const Offset(0, 42),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          onSelected: (v) {
            final idText = model.serverId.text;
            if (v == 'id') {
              Clipboard.setData(ClipboardData(text: idText));
              showToast(translate("Copied"));
            } else if (v == 'idpwd') {
              final pwd = model.serverPasswd.text;
              Clipboard.setData(ClipboardData(
                  text: '我的识别码: $idText\n'
                      '我的验证码: $pwd\n'
                      '使用极简云远程即可对我发起远程协助\n'
                      '极简云远程下载地址: https://xn--9kqx5fsxuf5v.top/'));
              showToast('已复制识别码和密码');
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'id', height: 40, child: Text('复制识别码')),
            PopupMenuItem(
                value: 'idpwd', height: 40, child: Text('复制识别码+密码')),
          ],
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: kTdOrange,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text('复制',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _passwordRow(BuildContext context, ServerModel model) {
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Row(
      children: [
        Text(showOneTime ? '临时密码' : '永久密码',
            style: TextStyle(fontSize: 15, color: Colors.grey)),
        SizedBox(width: 20),
        Expanded(
          child: Text(model.serverPasswd.text,
              style: TextStyle(fontSize: 20, letterSpacing: 2)),
        ),
        if (showOneTime)
          InkWell(
            onTap: () => bind.mainUpdateTemporaryPassword(),
            child: Tooltip(
                message: translate('Refresh Password'),
                child:
                    Icon(Icons.refresh, size: 22, color: Colors.grey)),
          ).marginOnly(right: 12),
        ElevatedButton.icon(
          onPressed: () =>
              DesktopSettingPage.switch2page(SettingsTabKey.safety),
          icon: Icon(Icons.edit, size: 16),
          label: Text('编辑密码'),
          style: ElevatedButton.styleFrom(
            backgroundColor: kTdGreen,
            foregroundColor: Colors.white,
            minimumSize: Size(96, 36),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _connectRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: _buildRemoteIDTextField(context),
        ),
        SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _pwdController,
            obscureText: true,
            style: TextStyle(fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.background,
              counterText: '',
              hintText: '对方的连接密码（可留空）',
              prefixIcon:
                  Icon(Icons.lock_outline, size: 20, color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      BorderSide(color: Theme.of(context).dividerColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: kTdBlue, width: 1.2)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            ),
            onSubmitted: (_) => onConnect(),
          ),
        ),
        SizedBox(width: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => onConnect(),
            child: Text('连接  >>',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kTdBlue,
              foregroundColor: Colors.white,
              minimumSize: Size(110, 48),
              elevation: 0,
            ),
          ),
        ),
        SizedBox(width: 8),
        _moreMenuButton(context),
      ],
    );
  }

  Widget _statusRow() {
    return Obx(() {
      final st = stateGlobal.svcStatus.value;
      final ready = st == SvcStatus.ready;
      final color = ready
          ? kTdGreen
          : (st == SvcStatus.connecting ? kTdOrange : Colors.redAccent);
      final text = ready
          ? '已准备好连接（端到端连接加密已启用）'
          : st == SvcStatus.connecting
              ? translate("connecting_status")
              : translate("not_ready_status");
      return Row(children: [
        Icon(
            ready
                ? Icons.check_circle
                : (st == SvcStatus.connecting
                    ? Icons.timelapse
                    : Icons.error_outline),
            color: color,
            size: 18),
        SizedBox(width: 6),
        Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: Colors.grey))),
        Spacer(),
        InkWell(
          onTap: _parseClipboardAndConnect,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: kTdBlue),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.content_paste_search, size: 16, color: kTdBlue),
              SizedBox(width: 5),
              Text('识别剪贴板并连接',
                  style: TextStyle(fontSize: 13, color: kTdBlue)),
            ]),
          ),
        ),
      ]);
    });
  }

  /// 定制：识别剪贴板中的「识别码/验证码」文本并一键连接
  Future<void> _parseClipboardAndConnect() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      showToast('剪贴板为空');
      return;
    }
    final idMatch =
        RegExp(r'识别码[:：\s]*(\d[\d\s]{7,}\d)').firstMatch(text);
    final pwdMatch = RegExp(r'验证码[:：]\s*([^\s]+)').firstMatch(text);
    if (idMatch == null) {
      showToast('未识别到控制码（需要形如“我的识别码: 123 456 789”）');
      return;
    }
    final id = idMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
    _idController.id = id;
    if (pwdMatch != null) {
      _pwdController.text = pwdMatch.group(1)!;
    }
    showToast('已识别控制码 $id，正在连接...');
    onConnect();
  }

  Widget _footer(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(Icons.desktop_windows, color: kTdBlue, size: 26),
          SizedBox(width: 8),
          Text('极简云远程',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: kTdBlue)),
        ]),
        Text('简单好用的远程控制',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _moreMenuButton(BuildContext context) {
    return Container(
      height: 48.0,
      width: 48.0,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: StatefulBuilder(
          builder: (context, setState) {
            var offset = Offset(0, 0);
            return Obx(() => InkWell(
                  child: _menuOpen.value
                      ? Transform.rotate(
                          angle: pi,
                          child: Icon(IconFont.more, size: 14),
                        )
                      : Icon(IconFont.more, size: 14),
                  onTapDown: (e) {
                    offset = e.globalPosition;
                  },
                  onTap: () async {
                    _menuOpen.value = true;
                    final x = offset.dx;
                    final y = offset.dy;
                    await mod_menu
                        .showMenu(
                      context: context,
                      position: RelativeRect.fromLTRB(x, y, x, y),
                      items: [
                        (
                          'Transfer file',
                          () => onConnect(isFileTransfer: true)
                        ),
                        (
                          'View camera',
                          () => onConnect(isViewCamera: true)
                        ),
                        (
                          '${translate('Terminal')} (beta)',
                          () => onConnect(isTerminal: true)
                        ),
                        if (isDesktop)
                          (
                            'TCP tunneling',
                            () => onConnect(isTcpTunneling: true)
                          ),
                      ]
                          .map((e) => MenuEntryButton<String>(
                                childBuilder: (TextStyle? style) => Text(
                                  translate(e.$1),
                                  style: style,
                                ),
                                proc: () => e.$2(),
                                padding: EdgeInsets.symmetric(
                                    horizontal:
                                        kDesktopMenuPadding.left),
                                dismissOnClicked: true,
                              ))
                          .map((e) => e.build(
                              context,
                              const MenuConfig(
                                  commonColor:
                                      CustomPopupMenuTheme.commonColor,
                                  height: CustomPopupMenuTheme.height,
                                  dividerHeight:
                                      CustomPopupMenuTheme
                                          .dividerHeight)))
                          .expand((i) => i)
                          .toList(),
                      elevation: 8,
                    )
                        .then((_) {
                      _menuOpen.value = false;
                    });
                  },
                ));
          },
        ),
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false,
      bool isTcpTunneling = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling,
        password: _pwdController.text.isEmpty ? null : _pwdController.text);
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    return RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                      _allPeersLoader.queryOnlines(_autocompleteOpts);
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    return Obx(() => TextField(
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          focusNode: fieldFocusNode,
                          style: const TextStyle(
                            fontFamily: 'WorkSans',
                            fontSize: 20,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          cursorColor:
                              Theme.of(context).textTheme.titleLarge?.color,
                          decoration: InputDecoration(
                              filled: true,
                              fillColor:
                                  Theme.of(context).colorScheme.background,
                              counterText: '',
                              hintText: _idInputFocused.value
                                  ? null
                                  : '请输入对方设备代码',
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color:
                                          Theme.of(context).dividerColor)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                      color: kTdBlue, width: 1.2)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 14)),
                          controller: fieldTextEditingController,
                          inputFormatters: [IDTextInputFormatter()],
                          onChanged: (v) {
                            _idController.id = v;
                          },
                          onSubmitted: (_) {
                            onConnect();
                          },
                        ).workaroundFreezeLinuxMint());
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: 319,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
                );
  }

}

/// Recent connections list (max 6) shown below the connect area.
class _RecentSection extends StatefulWidget {
  final ValueChanged<Peer> onPick;

  _RecentSection({required this.onPick});

  @override
  State<_RecentSection> createState() => _RecentSectionState();
}

class _RecentSectionState extends State<_RecentSection> {
  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
    gFFI.recentPeersModel.addListener(_refresh);
  }

  @override
  void dispose() {
    gFFI.recentPeersModel.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  IconData _platformIcon(String p) {
    final s = p.toLowerCase();
    if (s.contains('android')) return Icons.phone_android;
    if (s.contains('ios')) return Icons.phone_iphone;
    if (s.contains('mac')) return Icons.desktop_mac;
    if (s.contains('linux')) return Icons.computer;
    return Icons.desktop_windows;
  }

  @override
  Widget build(BuildContext context) {
    final peers = gFFI.recentPeersModel.peers.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('连接记录',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w600, color: kTdBlue)),
        SizedBox(height: 12),
        if (peers.isEmpty)
          Text('暂无连接记录',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ...peers.map((peer) {
          final name = peer.alias.isNotEmpty
              ? peer.alias
              : (peer.hostname.isNotEmpty ? peer.hostname : peer.id);
          return InkWell(
            onTap: () => widget.onPick(peer),
            child: Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.background,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(_platformIcon(peer.platform),
                      size: 22, color: peer.online ? kTdGreen : Colors.grey),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500)),
                        SizedBox(height: 2),
                        Text('${peer.id} · ${peer.online ? '在线' : '离线'}',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
