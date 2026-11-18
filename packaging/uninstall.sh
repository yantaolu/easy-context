#!/bin/bash
# Easy Context 卸载脚本。随 App 安装在：
#   /Applications/EasyContext.app/Contents/Resources/uninstall.sh
#
# 用法（以普通用户运行，需要管理员权限的步骤会自动调用 sudo）：
#   uninstall.sh                 交互式卸载，询问是否删除配置
#   uninstall.sh --keep-config   保留 ~/.easy-context（配置、自定义命令）
#   uninstall.sh --purge         连同 ~/.easy-context 一并删除
#   uninstall.sh --yes           不再确认（未指定 --purge 时保留配置）
#   uninstall.sh --dry-run       只列出将执行的操作，不做任何改动
#
# 会清理：App 本体、Finder 扩展登记、LaunchServices 登记、隐私授权（TCC）记录、
# 偏好设置、安装包回执，以及（可选）共享配置目录。
set -uo pipefail

APP_ID="com.luyantao.easycontext"
APPEX_ID="$APP_ID.finder"
APP_PATH="/Applications/EasyContext.app"
APPEX_PATH="$APP_PATH/Contents/PlugIns/EasyContextFinder.appex"
CONFIG_DIR="$HOME/.easy-context"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

CONFIG_MODE="ask" # ask | keep | purge
ASSUME_YES=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --keep-config) CONFIG_MODE="keep" ;;
    --purge) CONFIG_MODE="purge" ;;
    --yes|-y) ASSUME_YES=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：${arg}（--help 查看用法）" >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -eq 0 ]; then
  echo "请以普通用户运行（不要加 sudo）：偏好设置与隐私授权属于当前用户，需要时脚本会自行调用 sudo。" >&2
  exit 1
fi

FAILURES=0
run() {
  if [ "$DRY_RUN" = true ]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  if ! "$@"; then
    printf '  ⚠️  失败（已跳过）：%s\n' "$*" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

confirm() {
  local answer
  [ "$ASSUME_YES" = true ] && return 0
  printf '%s [y/N] ' "$1"
  read -r answer || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# 删除前核对目标确实是 Easy Context，避免误删同路径的其它东西。
APP_PRESENT=false
if [ -d "$APP_PATH" ]; then
  installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  if [ "$installed_id" = "$APP_ID" ]; then
    APP_PRESENT=true
  else
    echo "⚠️  $APP_PATH 的 bundle id 是「${installed_id:-未知}」而不是 ${APP_ID}，不会删除它。" >&2
  fi
fi

if [ "$CONFIG_MODE" = "ask" ]; then
  if [ ! -d "$CONFIG_DIR" ]; then
    CONFIG_MODE="keep"
  elif [ "$ASSUME_YES" = true ]; then
    CONFIG_MODE="keep"
  elif confirm "是否同时删除配置目录 ${CONFIG_DIR}（显示的 App、自定义命令、终端模板）？"; then
    CONFIG_MODE="purge"
  else
    CONFIG_MODE="keep"
  fi
fi

echo "将卸载 Easy Context："
[ "$APP_PRESENT" = true ] && echo "  · 删除 ${APP_PATH}（需要管理员密码）"
echo "  · 注销 Finder 扩展与 LaunchServices 登记"
echo "  · 重置隐私授权：${APP_ID}（含 Finder 扩展）"
echo "  · 删除偏好设置与安装包回执"
if [ "$CONFIG_MODE" = "purge" ]; then
  echo "  · 删除配置目录 $CONFIG_DIR"
else
  echo "  · 保留配置目录 $CONFIG_DIR"
fi
echo "  · 重启访达以移除右键菜单"
if [ "$DRY_RUN" != true ] && ! confirm "继续？"; then
  echo "已取消。"
  exit 1
fi

echo "==> 退出 Easy Context"
if /usr/bin/pgrep -x EasyContext >/dev/null; then
  run /usr/bin/osascript -e "tell application id \"$APP_ID\" to quit"
  [ "$DRY_RUN" = true ] || /bin/sleep 1
fi
for process_name in EasyContext EasyContextFinder; do
  if /usr/bin/pgrep -x "$process_name" >/dev/null; then
    run /usr/bin/pkill -x "$process_name"
  fi
done

echo "==> 注销登记"
[ -d "$APPEX_PATH" ] && run /usr/bin/pluginkit -r "$APPEX_PATH"
[ "$APP_PRESENT" = true ] && run "$LSREGISTER" -u "$APP_PATH"

echo "==> 重置隐私授权"
# tccutil 只能按应用程序 id 重置（对 Finder 扩展 id 恒报 -10814），扩展的授权归属于宿主。
# 须在删除 App 之前执行：App 不在了，tccutil 同样找不到该 id。
run /usr/bin/tccutil reset All "$APP_ID"             # 用户库：可移除宗卷、自动化等
run /usr/bin/sudo /usr/bin/tccutil reset All "$APP_ID" # 系统库：完全磁盘访问

echo "==> 删除 App 与安装记录"
[ "$APP_PRESENT" = true ] && run /usr/bin/sudo /bin/rm -rf "$APP_PATH"
if /usr/sbin/pkgutil --pkg-info "$APP_ID" >/dev/null 2>&1; then
  run /usr/bin/sudo /usr/sbin/pkgutil --forget "$APP_ID"
fi

echo "==> 删除偏好设置"
if /usr/bin/defaults read "$APP_ID" >/dev/null 2>&1; then
  run /usr/bin/defaults delete "$APP_ID"
fi

if [ "$CONFIG_MODE" = "purge" ] && [ -d "$CONFIG_DIR" ]; then
  echo "==> 删除配置目录"
  run /bin/rm -rf "$CONFIG_DIR"
fi

# 扩展的沙盒容器受 macOS 保护，通常删不掉；失败不计入错误，系统会在之后清理。
for leftover in "$HOME/Library/Containers/$APPEX_ID" "$HOME/Library/Application Scripts/$APPEX_ID"; do
  if [ -e "$leftover" ]; then
    if [ "$DRY_RUN" = true ]; then
      printf '  [dry-run] /bin/rm -rf %s（受系统保护时跳过）\n' "$leftover"
    else
      /bin/rm -rf "$leftover" 2>/dev/null || true
    fi
  fi
done

echo "==> 重启访达"
run /usr/bin/killall Finder

if [ "$DRY_RUN" = true ]; then
  echo "dry-run 结束，未做任何改动。"
elif [ "$FAILURES" -gt 0 ]; then
  echo "卸载完成，但有 $FAILURES 个步骤失败（见上方提示）。"
  exit 1
else
  echo "卸载完成。"
fi
