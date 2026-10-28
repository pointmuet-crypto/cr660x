#!/usr/bin/env bash
set -Eeuo pipefail

# Build ImmortalWrt for Xiaomi CR6606/CR6608/CR6609 with Netkeeper + UA3F.
# Usage: JOBS=2 bash ./build-cr660x.sh [source-directory]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${1:-$HOME/immortalwrt-cr660x-netkeeper-ua3f}"
BRANCH="${IMMORTALWRT_BRANCH:-openwrt-24.10}"
JOBS="${JOBS:-$(nproc)}"

info() { printf '\n[INFO] %s\n' "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

if [[ ! -f /etc/os-release ]] || ! grep -qiE 'ubuntu|debian' /etc/os-release; then
  info "建议在 Ubuntu 22.04/24.04 或 Debian x86-64 编译环境运行。"
fi

if [[ "${SKIP_APT:-0}" != "1" ]] && command -v apt-get >/dev/null 2>&1; then
  info "安装编译依赖"
  if [[ "${EUID}" -eq 0 ]]; then
    APT=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    APT=(sudo apt-get)
  else
    die "需要 root 或 sudo 安装主机编译依赖；手动安装后可设置 SKIP_APT=1。"
  fi
  "${APT[@]}" update
  "${APT[@]}" install -y --no-install-recommends \
    build-essential clang flex bison g++ gawk gcc-multilib gettext git \
    libncurses-dev libssl-dev python3 python3-setuptools python3-dev \
    rsync swig unzip zlib1g-dev file wget curl perl tar xz-utils \
    patch diffutils time cpio libelf-dev device-tree-compiler
fi

if [[ -e "$WORKDIR" ]]; then
  [[ -d "$WORKDIR/.git" ]] || die "$WORKDIR 已存在但不是 Git 仓库，请换一个目录。"
  info "复用源码目录：$WORKDIR"
else
  info "克隆 ImmortalWrt 分支：$BRANCH"
  git clone --branch "$BRANCH" --single-branch https://github.com/immortalwrt/immortalwrt.git "$WORKDIR"
fi
cd "$WORKDIR"

# Register the Netkeeper feed once.
if ! grep -qE '^[[:space:]]*src-git[[:space:]]+netkeeper[[:space:]]' feeds.conf.default; then
  printf '\n# Netkeeper and Netkeeper interception packages\nsrc-git netkeeper https://github.com/YYuan996/netkeeper-interception.git\n' >> feeds.conf.default
fi

info "更新并安装 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

# Repair upstream Netkeeper Makefiles for repeatable builds and PPP 2.5.1.
# The upstream recipes use "mkdir ./builds", which fails when the directory
# already exists, and look for the obsolete PKG_RELEASE_VERSION variable.
info "修复闪讯上游 Makefile 的 builds 目录创建和 pppd 版本号检测"
python3 - <<'PY'
from pathlib import Path

root = Path("feeds/netkeeper")
source_makefiles = [
    root / "netkeeper/src/Makefile",
    root / "netkeeper-interception/src/Makefile",
]
package_makefiles = [
    root / "netkeeper/Makefile",
    root / "netkeeper-interception/Makefile",
]

for path in source_makefiles:
    if not path.is_file():
        raise SystemExit(f"[ERROR] 找不到闪讯源码 Makefile：{path}")
    text = path.read_text()
    text = text.replace("@mkdir ./builds", "@mkdir -p ./builds")
    if "@mkdir -p ./builds" not in text:
        raise SystemExit(f"[ERROR] 未能修复 builds 目录创建命令：{path}")
    path.write_text(text)

for path in package_makefiles:
    if not path.is_file():
        raise SystemExit(f"[ERROR] 找不到闪讯打包 Makefile：{path}")
    text = path.read_text()
    text = text.replace("grep 'PKG_RELEASE_VERSION:='", "grep '^PKG_VERSION:='")
    if "grep 'PKG_RELEASE_VERSION:='" in text:
        raise SystemExit(f"[ERROR] 未能更新 PPP 版本检测：{path}")
    path.write_text(text)

print("[INFO] Netkeeper Makefile fixes applied.")
PY


# PPP 2.5.1 no longer exposes the legacy Netkeeper variables/hooks through
# pppd/pppd.h alone. Include the public PAP/CHAP hook declarations and declare
# the pppd-private username/password globals used by the legacy plugin.
info "修复 Netkeeper 与 PPP 2.5.1 的头文件/API 兼容性"
python3 - <<'PY'
from pathlib import Path

root = Path("feeds/netkeeper")
sources = [
    root / "netkeeper/src/sxplugin.c",
    root / "netkeeper/src/sxplugin4.c",
]
for path in sources:
    if not path.is_file():
        raise SystemExit(f"[ERROR] 找不到 Netkeeper 源文件：{path}")
    text = path.read_text()
    anchor = '#include "pppd/pppd.h"'
    if anchor not in text:
        raise SystemExit(f"[ERROR] 找不到 pppd.h include：{path}")
    additions = (
        '#include "pppd/upap.h"\n'
        '#include "pppd/chap.h"'
    )
    if '#include "pppd/upap.h"' not in text:
        text = text.replace(anchor, anchor + "\n" + additions, 1)
    decls = (
        '\n/* PPP 2.5.1 keeps these option globals in pppd-private.h; '
        'the Netkeeper plugin needs the exported symbols. */\n'
        'extern char user[MAXNAMELEN];\n'
        'extern char passwd[MAXSECRETLEN];\n'
    )
    if 'extern char user[MAXNAMELEN];' not in text:
        pos = text.find('#include "pppd/chap.h"')
        if pos < 0:
            raise SystemExit(f"[ERROR] 找不到 CHAP include：{path}")
        end = pos + len('#include "pppd/chap.h"')
        text = text[:end] + decls + text[end:]
    path.write_text(text)
    print(f"[INFO] patched {path}")
PY

# UA3F stores its OpenWrt package recipe in package/UA3F/openwrt/Makefile.
if [[ ! -d package/UA3F/.git ]]; then
  [[ ! -e package/UA3F ]] || die "package/UA3F 已存在但不是 UA3F Git 仓库，请检查目录。"
  info "克隆 UA3F"
  git clone --depth 1 --branch master https://github.com/SunBK201/UA3F.git package/UA3F
fi
[[ -f package/UA3F/openwrt/Makefile ]] || die "未找到 UA3F 的 OpenWrt 打包配方 package/UA3F/openwrt/Makefile。"

info "应用 CR660x 固件配置"
cp "$SCRIPT_DIR/cr660x.config" .config
make defconfig

required=(
  CONFIG_TARGET_ramips=y
  CONFIG_TARGET_ramips_mt7621=y
  CONFIG_TARGET_MULTI_PROFILE=y
  CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6606=y
  CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6608=y
  CONFIG_TARGET_DEVICE_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6609=y
  CONFIG_PACKAGE_netkeeper=y
  CONFIG_PACKAGE_luci-proto-netkeeper=y
  CONFIG_PACKAGE_netkeeper-interception=y
  CONFIG_PACKAGE_luci-app-netkeeper-interception=y
  CONFIG_PACKAGE_ua3f=y
  CONFIG_PACKAGE_kmod-nft-queue=y
  CONFIG_PACKAGE_kmod-nft-tproxy=y
  CONFIG_PACKAGE_kmod-sched-bpf=y
  CONFIG_PACKAGE_libubox-lua=y
)
missing=()
for item in "${required[@]}"; do
  grep -qxF "$item" .config || missing+=("$item")
done
if (("${#missing[@]}")); then
  printf '\n[ERROR] make defconfig 后以下配置未保留：\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  printf '\n常见原因是目标符号/软件包在当前分支不可用，或其依赖不满足。\n' >&2
  exit 2
fi

info "下载构建所需源码包"
make download -j"$JOBS" V=s

info "开始编译，JOBS=$JOBS"
if ! make -j"$JOBS"; then
  info "并行编译失败，改为单线程详细输出"
  make -j1 V=s
fi

OUT="$WORKDIR/bin/targets/ramips/mt7621"
[[ -d "$OUT" ]] || die "未找到预期的固件输出目录：$OUT"
printf '\n构建结束，镜像目录：%s\n' "$OUT"
find "$OUT" -maxdepth 1 -type f -printf '%f  %s bytes\n' | sort
printf '\n请核对实际机型、文件用途与刷机流程，不要仅凭文件名相似直接刷写。\n'
