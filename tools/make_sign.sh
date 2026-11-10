#!/bin/bash
# 为 com.lbuding.workbench 生成一套本地调试签名（OpenHarmony 官方根 CA 签发）
# 产物：~/.ohos/config/local_workbench_com.lbuding.workbench.{cer,p12,p7b}
# 注意：脚本里别用 PWD 做变量名（bash 内建=当前目录）
set -e
JBR=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
LIB=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib
WORK=/tmp/ohsign-work
DEST="$HOME/.ohos/config/local_workbench_com.lbuding.workbench"
SIGNPWD=WBopenharmony2026LocalDevSign2026X   # 必须 >= 32 位
BUNDLE=com.lbuding.workbench
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
SIGN="$JBR/bin/java -jar $LIB/hap-sign-tool.jar"

# 1) 导出 SDK 里的根 CA / 子 CA（DER）
$JBR/bin/keytool -exportcert -keystore $LIB/OpenHarmony.p12 -storepass 123456 \
  -alias "openharmony application root ca" -file "$WORK/root-ca.cer"
$JBR/bin/keytool -exportcert -keystore $LIB/OpenHarmony.p12 -storepass 123456 \
  -alias "openharmony application ca" -file "$WORK/sub-ca.cer"

# 2) 应用密钥 + 应用证书（由 OpenHarmony Application Root CA 签发）
$SIGN generate-keypair -keyAlias wbAppKey -keyPwd $SIGNPWD -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile "$WORK/app.p12" -keystorePwd $SIGNPWD
$SIGN generate-csr -keyAlias wbAppKey -keyPwd $SIGNPWD \
  -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Personal Workbench Debug" \
  -signAlg SHA256withECDSA -keystoreFile "$WORK/app.p12" -keystorePwd $SIGNPWD -outFile "$WORK/app.csr"
$SIGN generate-app-cert -keyAlias wbAppKey -keyPwd $SIGNPWD \
  -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
  -issuerKeyAlias "openharmony application ca" -issuerKeyPwd 123456 \
  -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Personal Workbench Debug" \
  -signAlg SHA256withECDSA -keystoreFile "$WORK/app.p12" -keystorePwd $SIGNPWD \
  -outFile "$WORK/app-chain.cer" -outForm certChain \
  -rootCaCertFile "$WORK/root-ca.cer" -subCaCertFile "$WORK/sub-ca.cer" \
  -issuerKeystoreFile $LIB/OpenHarmony.p12 -issuerKeystorePwd 123456

# 3) profile 密钥 + profile 证书链（由 OpenHarmony Application CA 签发）
$SIGN generate-keypair -keyAlias wbProfileKey -keyPwd $SIGNPWD -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile "$WORK/profile.p12" -keystorePwd $SIGNPWD
$SIGN generate-csr -keyAlias wbProfileKey -keyPwd $SIGNPWD \
  -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Personal Workbench Profile Debug" \
  -signAlg SHA256withECDSA -keystoreFile "$WORK/profile.p12" -keystorePwd $SIGNPWD -outFile "$WORK/profile.csr"
$SIGN generate-profile-cert -keyAlias wbProfileKey -keyPwd $SIGNPWD \
  -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
  -issuerKeyAlias "openharmony application ca" -issuerKeyPwd 123456 \
  -subject "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=Personal Workbench Profile Debug" \
  -signAlg SHA256withECDSA -keystoreFile "$WORK/profile.p12" -keystorePwd $SIGNPWD \
  -outForm certChain -rootCaCertFile "$WORK/root-ca.cer" -subCaCertFile "$WORK/sub-ca.cer" \
  -outFile "$WORK/profile-cert-chain.pem" \
  -issuerKeystoreFile $LIB/OpenHarmony.p12 -issuerKeystorePwd 123456

# 4) profile JSON（结构照 AGC 下发的 profile，只是换了 bundle-name 与证书）
python3 - "$WORK" "$BUNDLE" <<'PY'
import json, time, uuid, random, sys
work, bundle = sys.argv[1], sys.argv[2]
import re
chain = open(work + '/app-chain.cer', encoding='utf-8').read()
app_pem = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', chain, re.S)[0] + '\n'  # 结尾必须带换行，否则 sign-app 解析 base64 失败
now = int(time.time())
prof = {
  "version-name": "2.0.0", "version-code": 2, "uuid": str(uuid.uuid4()),
  "validity": {"not-before": now - 86400, "not-after": now + 3 * 365 * 86400},
  "type": "debug",
  "bundle-info": {"developer-id": "OpenHarmony", "development-certificate": app_pem,
                  "bundle-name": bundle, "apl": "normal", "app-feature": "hos_normal_app"},
  "permissions": {"restricted-permissions": [""]},
  "debug-info": {"device-ids": ["6AE938E4A29AA5C9717A801DBF839623201B12BF670182343E59D0256ED9B5D3", "454D5504D4143041524D0BA00F50A234B4E41B767CF2099FCABD000000000000"],
                 "device-id-type": "udid"},
  "acls": {"allowed-acls": [""]}, "issuer": "pki_internal"}
open(work + '/profile.json', 'w', encoding='utf-8').write(json.dumps(prof, separators=(',', ':')))
print('profile.json written for', bundle)
PY

$SIGN sign-profile -mode localSign -keyAlias wbProfileKey -keyPwd $SIGNPWD \
  -profileCertFile "$WORK/profile-cert-chain.pem" -inFile "$WORK/profile.json" \
  -signAlg SHA256withECDSA -keystoreFile "$WORK/profile.p12" -keystorePwd $SIGNPWD \
  -outFile "$WORK/profile.p7b"

# 5) 安装到 ~/.ohos/config
cp "$WORK/app-chain.cer" "$DEST.cer"
cp "$WORK/app.p12" "$DEST.p12"
cp "$WORK/profile.p7b" "$DEST.p7b"
echo "PASSWORD=$SIGNPWD"
echo "OK -> $DEST.{cer,p12,p7b}"
