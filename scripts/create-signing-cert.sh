#!/bin/bash
# 一次性生成 Easy Context 的自签名代码签名证书（.p12），供本地与 GitHub Actions 发布使用。
#
# 为什么需要：ad-hoc 签名的「指定要求」(designated requirement) 是 cdhash，每次构建都会变，
# macOS 的隐私授权（可移除宗卷、完全磁盘访问、自动化）因此在每次升级后失效。用一张固定的
# 自签名证书签名后，指定要求变为「bundle id + 证书叶子指纹」，跨版本保持不变。
#
# 用法：
#   ./scripts/create-signing-cert.sh [输出目录]          # 默认 ~/EasyContext-signing
#   ./scripts/create-signing-cert.sh [输出目录] --import # 同时导入登录钥匙串，供本地 build-pkg 使用
#
# 产物（目录权限 0700）：
#   easycontext-signing.p12           私钥 + 证书，务必离线备份，绝不提交到仓库
#   easycontext-signing.p12.password  .p12 的随机密码
#   easycontext-signing.cer.pem       证书公开部分
# 并把证书 SHA-1 指纹写入仓库 packaging/signing-certificate.sha1（公开信息，应提交）。
#
# ⚠️ 私钥丢失 = 所有用户需重新授权一次；私钥泄露 = 他人可签出继承用户授权的程序。
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd -P)"
PIN_FILE="$REPO_ROOT/packaging/signing-certificate.sha1"

OUT_DIR="$HOME/EasyContext-signing"
DO_IMPORT=false
for arg in "$@"; do
  case "$arg" in
    --import) DO_IMPORT=true ;;
    -*) echo "未知参数：$arg" >&2; exit 2 ;;
    *) OUT_DIR="$arg" ;;
  esac
done

COMMON_NAME="Easy Context Self-Signed Code Signing"
VALID_DAYS=7300 # 20 年：避免证书过期带来的额外问题
P12="$OUT_DIR/easycontext-signing.p12"
P12_PASSWORD_FILE="$P12.password"
CERT_PEM="$OUT_DIR/easycontext-signing.cer.pem"

if [[ -e "$P12" ]]; then
  echo "已存在 ${P12}，拒绝覆盖（重新生成会让所有用户的授权失效一次）。" >&2
  echo "确需更换证书，请先手动移走旧文件。" >&2
  exit 1
fi

umask 077
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $COMMON_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 固定用系统 LibreSSL：其 PKCS#12 默认算法可被 macOS `security import` 读取
# （Homebrew OpenSSL 3 默认的 AES 加密 .p12 在部分系统上导入失败）。
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:3072 -sha256 -nodes -days "$VALID_DAYS" \
  -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$CERT_PEM" 2>/dev/null

PASSWORD="$("$OPENSSL" rand -hex 24)"
printf '%s' "$PASSWORD" > "$P12_PASSWORD_FILE"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$CERT_PEM" \
  -name "$COMMON_NAME" -out "$P12" -passout "file:$P12_PASSWORD_FILE"

SHA1="$("$OPENSSL" x509 -in "$CERT_PEM" -noout -fingerprint -sha1 \
  | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')"
printf '%s\n' "$SHA1" > "$PIN_FILE"

if [[ "$DO_IMPORT" == true ]]; then
  # -T /usr/bin/codesign：允许 codesign 使用私钥而不弹窗确认。
  security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASSWORD" -T /usr/bin/codesign
  echo "==> 已导入登录钥匙串。"
fi

cat <<EOF

==> 证书已生成：$OUT_DIR
    SHA-1 指纹：${SHA1}（已写入 packaging/signing-certificate.sha1，请提交该文件）

下一步：
  1. 离线备份 $P12 与其密码文件（例如加密 U 盘 / 密码管理器）。
  2. 在 GitHub 仓库 Settings → Secrets and variables → Actions 添加两个 secret：
       EC_SIGNING_P12_BASE64    ← base64 -i "$P12" | pbcopy
       EC_SIGNING_P12_PASSWORD  ← pbcopy < "$P12_PASSWORD_FILE"
  3. 本地正式打包（需先用 --import 导入，或手动导入登录钥匙串）：
       EC_SIGN_IDENTITY=$SHA1 ./scripts/release.sh preview
EOF
