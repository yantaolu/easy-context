#!/bin/bash
# 把 base64 编码的签名 .p12 导入一个临时钥匙串，供 build-pkg.sh 非交互签名。
# 仅供发布工作流调用；本地可用测试证书验证同一流程。
#
# 输入（环境变量）：EC_SIGNING_P12_BASE64、EC_SIGNING_P12_PASSWORD
# 参数：$1 = 要创建的临时钥匙串路径（不得已存在）
# 输出（stdout，可直接追加到 ${GITHUB_ENV}）：
#   EC_SIGN_IDENTITY=<证书 SHA-1>
#   EC_SIGN_KEYCHAIN=<钥匙串路径>
# 调用方负责在结束后执行 `security delete-keychain <路径>`。
set -euo pipefail

KEYCHAIN="${1:?usage: import-signing-cert.sh <keychain-path>}"
: "${EC_SIGNING_P12_BASE64:?EC_SIGNING_P12_BASE64 未设置（请在仓库 Secrets 中配置）}"
: "${EC_SIGNING_P12_PASSWORD:?EC_SIGNING_P12_PASSWORD 未设置（请在仓库 Secrets 中配置）}"

if [[ -e "$KEYCHAIN" ]]; then
  echo "钥匙串已存在，拒绝复用：$KEYCHAIN" >&2
  exit 1
fi

umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
P12="$WORK/signing.p12"
printf '%s' "$EC_SIGNING_P12_BASE64" | base64 --decode > "$P12"

KEYCHAIN_PASSWORD="$(uuidgen)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
# 6 小时内不自动上锁，覆盖整个构建过程。
security set-keychain-settings -lut 21600 "$KEYCHAIN" >&2
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security import "$P12" -k "$KEYCHAIN" -P "$EC_SIGNING_P12_PASSWORD" -T /usr/bin/codesign >&2
# macOS 10.12+：允许 Apple 工具在无 UI 的情况下使用该私钥。
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

# 自签名证书不受信任，find-identity 不能加 -v（-v 只列「有效」身份）。
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" \
  | awk '/^[[:space:]]*[0-9]+\)/ { print tolower($2); exit }')"
if [[ ! "$IDENTITY" =~ ^[0-9a-f]{40}$ ]]; then
  echo "导入的 .p12 中没有可用于代码签名的身份" >&2
  security find-identity -p codesigning "$KEYCHAIN" >&2 || true
  exit 1
fi

printf 'EC_SIGN_IDENTITY=%s\n' "$IDENTITY"
printf 'EC_SIGN_KEYCHAIN=%s\n' "$KEYCHAIN"
