#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 注意：这个脚本以前会用 SDK 自带的 p12 自签，然后覆盖 hvigor 产出的包。
# 现在工程已经在 build-profile.json5 里配好了 DevEco 自动签名
# （~/.ohos/config/default_workbench_*.p12/.cer/.p7b），
# hvigor  assembleHap  产出的 entry-default-signed.hap 就是**设备能装的**那个包。
#
# 踩过的坑：自签包 verify 能过（sign-app success），但真机安装会报
#   error: fail to verify pkcs7 file. code:9568257
# 原因：设备只信任 DevEco 自动签名的那套证书链。
#
# 所以：正常流程直接用 hvigor 的产物，不要跑这个脚本。
#       如果 build-profile.json5 里没有 signingConfigs（自己删过），
#       才需要本脚本兜底自签。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROFILE="$ROOT/build-profile.json5"
HAP="$ROOT/entry/build/default/outputs/default/entry-default-signed.hap"

# 1. 已经配了 DevEco 自动签名 → 直接提示用 hvigor 的产物
if grep -q '"signingConfigs"' "$PROFILE" && \
   grep -q '"material"' "$PROFILE" && \
   ! grep -q '"signingConfigs"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' "$PROFILE"; then
  echo "检测到 build-profile.json5 里已配置 DevEco 自动签名。"
  echo "请直接用 hvigor 构建产出的包（它才是设备能装的）："
  echo "  $HAP"
  echo
  echo "如果你刚才跑过本脚本，hvigor 的包已经被覆盖了，请重新构建："
  echo "  cd \"$ROOT\""
  echo "  export NODE_HOME=\"/Applications/DevEco-Studio.app/Contents/tools/node\""
  echo "  export JAVA_HOME=\"/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home\""
  echo "  export DEVECO_SDK_HOME=\"/Applications/DevEco-Studio.app/Contents/sdk\""
  echo "  export PATH=\"\$JAVA_HOME/bin:\$NODE_HOME/bin:\$PATH\""
  echo "  node \"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js\" assembleHap --mode module -p product=default -p buildMode=debug --no-daemon"
  exit 0
fi

# 2. 没配签名 → 走 SDK 自带 p12 自签兜底
SDK="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains"
LIB="$SDK/lib"
JBR="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin"
JAVA="$JBR/java"
KEYTOOL="$JBR/keytool"
JAR="$LIB/hap-sign-tool.jar"
P12="$LIB/OpenHarmony.p12"
STORE_PWD="123456"

SRC="$ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"
OUT="$HAP"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -f "$SRC" ]; then
  echo "找不到未签名包：$SRC"
  echo "先跑 assembleHap。"
  exit 1
fi

BUNDLE="$(python3 - "$ROOT/AppScope/app.json5" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'"bundleName"\s*:\s*"([^"]+)"', text)
print(m.group(1) if m else "com.lbuding.workbench")
PY
)"
echo "bundleName = $BUNDLE（自签兜底模式，装到真机可能被拒）"

python3 - "$LIB/UnsgnedReleasedProfileTemplate.json" "$WORK/profile.json" "$BUNDLE" "$WORK/leaf.cer" <<'PY'
import json, sys, datetime
src, prof, bundle, leaf = sys.argv[1:]
d = json.load(open(src))
d["validity"] = {
    "not-before": int(datetime.datetime(2026, 1, 1).timestamp()),
    "not-after": int(datetime.datetime(2035, 1, 1).timestamp()),
}
d["uuid"] = "a1b2c3d4-1111-2222-3333-444455556666"
bi = d["bundle-info"]
bi["bundle-name"] = bundle
open(prof, "w").write(json.dumps(d, indent=2, ensure_ascii=False))
open(leaf, "w").write(bi["distribution-certificate"].strip() + "\n")
PY

"$JAVA" -jar "$JAR" sign-profile -mode localSign \
  -keyAlias "openharmony application profile release" -keyPwd "$STORE_PWD" \
  -profileCertFile "$LIB/OpenHarmonyProfileRelease.pem" \
  -inFile "$WORK/profile.json" -signAlg SHA256withECDSA \
  -keystoreFile "$P12" -keystorePwd "$STORE_PWD" \
  -outFile "$WORK/signed-profile.p7b"

# 叶子必须是模板里的 distribution-certificate（Issuer=Application CA），
# 拿 p12 里自签的 "openharmony application release" 当叶子会报 11013002。
"$KEYTOOL" -exportcert -rfc -keystore "$P12" -storetype PKCS12 -storepass "$STORE_PWD" \
  -alias cacert -file "$WORK/ca.cer" >/dev/null 2>&1
"$KEYTOOL" -exportcert -rfc -keystore "$P12" -storetype PKCS12 -storepass "$STORE_PWD" \
  -alias rootcacert -file "$WORK/rootca.cer" >/dev/null 2>&1
cat "$WORK/leaf.cer" "$WORK/ca.cer" "$WORK/rootca.cer" > "$WORK/app-chain.cer"

"$JAVA" -jar "$JAR" sign-app -mode localSign \
  -keyAlias "openharmony application release" -keyPwd "$STORE_PWD" \
  -appCertFile "$WORK/app-chain.cer" \
  -profileFile "$WORK/signed-profile.p7b" -profileSigned 1 \
  -inFile "$SRC" -signAlg SHA256withECDSA \
  -keystoreFile "$P12" -keystorePwd "$STORE_PWD" \
  -outFile "$OUT" -compatibleVersion 24 -signCode 1

"$JAVA" -jar "$JAR" verify-app -inFile "$OUT" \
  -outCertChain "$WORK/verify-chain.cer" -outProfile "$WORK/verify-profile.p7b" >/dev/null
echo "signed & verified: $OUT"
echo "提醒：自签包真机可能装不上（fail to verify pkcs7 file），优先用 DevEco 自动签名的构建产物。"
ls -la "$OUT"
