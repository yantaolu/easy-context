#!/bin/bash
# preinstall / postinstall 共用的判定函数。只定义函数、不执行任何动作，
# 以便 scripts/test-version.sh 直接 source 后用固定输入测试。
#
# 安装器以 root 运行，这里一律使用系统工具的绝对路径。

EC_APP_ID="com.luyantao.easycontext"
EC_APPEX_ID="com.luyantao.easycontext.finder"
EC_LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 打印 bundle 的 designated requirement（单行，不含 "designated => " 前缀）。
# ad-hoc 形如 `cdhash H"…"`；证书签名形如 `identifier "…" and certificate leaf = H"…"`。
# 无法读取（不存在 / 未签名）时打印空串。
ec_designated_requirement() {
  [ -e "$1" ] || return 0
  /usr/bin/codesign -d -r- "$1" 2>&1 \
    | /usr/bin/sed -n 's/^#* *designated => //p' \
    | /usr/bin/head -n 1
}

# macOS 隐私授权（TCC）按 designated requirement 识别 App。旧要求存在且与新要求
# 不同，说明旧授权已不匹配新程序：开关仍显示开启，访问却被静默拒绝。此时返回 0。
# 首次安装（无旧要求）或身份未变（同一证书签名的升级）返回 1，保留现有授权。
ec_requirement_changed() {
  [ -n "$1" ] && [ "$1" != "$2" ]
}

# stdin：`pluginkit -mAvvv -i <id>` 的输出；$1：应保留的 appex 路径。
# 打印其它所有已登记的同 id 扩展路径（路径可含空格）。
ec_other_plugin_paths() {
  /usr/bin/awk -v keep="$1" '
    $1 == "Path" && $2 == "=" {
      path = $0
      sub(/^[^=]*= /, "", path)
      if (path != keep) print path
    }'
}

# stdin：`lsregister -dump` 的输出；$1：bundle id；$2：应保留的 App 路径。
# 打印其它所有登记为该 bundle id 的 App 路径（含文件已删除但登记仍在的条目）。
ec_other_registered_app_paths() {
  /usr/bin/awk -v id="$1" -v keep="$2" '
    /^-+$/ { path = ""; next }
    /^path:/ {
      path = $0
      sub(/^path:[ \t]+/, "", path)
      sub(/ \(0x[0-9a-fA-F]+\)$/, "", path)
      next
    }
    /^identifier:/ {
      value = $0
      sub(/^identifier:[ \t]+/, "", value)
      sub(/ \(0x[0-9a-fA-F]+\)$/, "", value)
      if (value == id && path != "" && path != keep && !(path in seen)) {
        seen[path] = 1
        print path
      }
    }'
}
