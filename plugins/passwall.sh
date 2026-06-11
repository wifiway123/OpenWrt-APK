#!/bin/sh
# plugins/passwall.sh - luci-app-passwall 安装模块 (APK only, OpenWrt 25.12+)
#
# 包来源：
#   - 系统依赖: OpenWrt 官方源 (apk)
#   - PassWall 依赖: SourceForge (openwrt-passwall-build)
#   - LuCI: GitHub Releases (Openwrt-Passwall/openwrt-passwall)

SF_PROJECT="openwrt-passwall-build"
SF_BASE="https://downloads.sourceforge.net/project/${SF_PROJECT}/files/releases"

# ============================================================
# 获取架构名
# ============================================================
_get_openwrt_arch() {
    . /etc/openwrt_release 2>/dev/null || return 1
    echo "$DISTRIB_ARCH"
}

# ============================================================
# 解析 SourceForge 目录页，提取 APK 文件名列表
# ============================================================
_list_sf_apks() {
    local dir_url="$1"
    local page
    page=$(wget -q --timeout=30 -O- "$dir_url" 2>/dev/null) || return 1
    # <a href=".../xxx.apk/download">xxx.apk</a>
    echo "$page" | grep -oE 'href="[^"]*\.apk[^"]*"' | \
        sed 's/.*\///;s/\.apk.*/.apk/;s/"//g' | sort -u
}

# ============================================================
# 安装 PassWall
# ============================================================
install_passwall() {
    echo ""
    echo "================================"
    echo " 安装 PassWall"
    echo "================================"
    echo ""

    # ---- 检测环境 ----
    local arch
    arch=$(_get_openwrt_arch) || {
        echo "[错误] 无法获取架构信息"
        return 1
    }
    echo "[架构] $arch"

    local download_dir="${CACHE_DIR}/passwall"
    rm -rf "$download_dir"
    mkdir -p "$download_dir"

    # ============================================================
    # 1. 从 GitHub Releases 下载 LuCI 包
    # ============================================================
    echo ""
    echo "--- [1/5] 获取 LuCI 主程序 ---"

    local release_json
    release_json=$(get_latest_release "Openwrt-Passwall" "openwrt-passwall") || {
        echo "[错误] GitHub Releases 请求失败"
        return 1
    }

    local tag
    tag=$(get_release_tag "$release_json")
    echo "  版本: $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json")

    # GitHub URL: 25.12%2B_luci-app-passwall-26.6.2-r1.apk
    local luci_url
    luci_url=$(echo "$all_urls" | grep -i "luci-app-passwall" | grep "\.apk$" | head -1)

    local i18n_url
    i18n_url=$(echo "$all_urls" | grep -i "luci-i18n-passwall-zh-cn" | grep "\.apk$" | head -1)

    if [ -z "$luci_url" ]; then
        echo "[错误] 未找到 luci-app-passwall APK 包"
        return 1
    fi

    local luci_name; luci_name=$(basename "$luci_url")
    local i18n_name=""; [ -n "$i18n_url" ] && i18n_name=$(basename "$i18n_url")

    echo "  LuCI: $luci_name"
    [ -n "$i18n_name" ] && echo "  语言: $i18n_name"

    download_file "$luci_url" "${download_dir}/${luci_name}" || {
        echo "[错误] LuCI 包下载失败"
        return 1
    }
    [ -n "$i18n_url" ] && download_file "$i18n_url" "${download_dir}/${i18n_name}" || true

    # ============================================================
    # 2. 从 SourceForge 获取依赖包列表
    # ============================================================
    echo ""
    echo "--- [2/5] 扫描 SourceForge 依赖源 ---"

    local sf_dir_url="https://sourceforge.net/projects/${SF_PROJECT}/files/releases/packages-25.12/${arch}/passwall_packages/"
    echo "  扫描: $sf_dir_url"

    local file_list
    file_list=$(_list_sf_apks "$sf_dir_url") || {
        echo "[错误] SourceForge 包列表获取失败"
        return 1
    }

    local pkg_count
    pkg_count=$(echo "$file_list" | wc -l)
    echo "  可用: $pkg_count 个包"

    # ============================================================
    # 3. 下载 passwall_packages 中的所有 APK
    # ============================================================
    echo ""
    echo "--- [3/5] 下载依赖包 ---"

    local dl_ok=0 dl_fail=0
    local sf_base_url="${SF_BASE}/packages-25.12/${arch}"

    for fname in $file_list; do
        local dl_url="${sf_base_url}/passwall_packages/${fname}"
        local output="${download_dir}/${fname}"

        if [ -f "$output" ] && [ -s "$output" ]; then
            echo "  [跳过] $fname"
            dl_ok=$((dl_ok + 1))
        elif download_file "$dl_url" "$output"; then
            echo "  [下载] $fname"
            dl_ok=$((dl_ok + 1))
        else
            echo "  [失败] $fname"
            dl_fail=$((dl_fail + 1))
        fi
    done

    echo "  结果: 成功 $dl_ok, 失败 $dl_fail"

    # ============================================================
    # 4. 安装系统硬依赖 (OpenWrt 官方源)
    # ============================================================
    echo ""
    echo "--- [4/5] 安装系统硬依赖 ---"

    local sys_pkgs="coreutils coreutils-base64 coreutils-nohup curl dnsmasq-full ip-full libuci-lua lua luci-compat luci-lib-jsonc resolveip lyaml"

    # 检测 firewall 类型，安装透明代理组件
    if command -v fw4 >/dev/null 2>&1 || [ -f /etc/config/firewall4 ] 2>/dev/null; then
        echo "  防火墙: Nftables (fw4)"
        sys_pkgs="$sys_pkgs nftables kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
    else
        echo "  防火墙: Iptables (fw3)"
        sys_pkgs="$sys_pkgs ipset iptables iptables-zz-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat"
    fi

    local install_ok=0 install_fail=0
    for pkg in $sys_pkgs; do
        if apk add "$pkg" 2>/dev/null; then
            install_ok=$((install_ok + 1))
        else
            install_fail=$((install_fail + 1))
        fi
    done
    printf "  结果: 成功 %d, 失败 %d\n" "$install_ok" "$install_fail"

    # ============================================================
    # 5. 安装所有 APK (依赖 + LuCI)
    # ============================================================
    echo ""
    echo "--- [5/5] 安装 APK 包 ---"

    cd "$download_dir" || return 1

    local total_apk
    total_apk=$(find "$download_dir" -maxdepth 1 -name "*.apk" 2>/dev/null | wc -l)
    echo "  共 $total_apk 个 APK"

    # 先装依赖，再装 LuCI
    echo "  安装依赖包..."
    for f in "$download_dir"/*.apk; do
        [ -f "$f" ] || continue
        local base; base=$(basename "$f")
        case "$base" in
            luci-app-passwall*|luci-i18n-passwall*) continue ;;
        esac
        apk add --allow-untrusted --force-overwrite "$f" 2>/dev/null || true
    done

    echo "  安装 LuCI 主程序..."
    apk add --allow-untrusted --force-overwrite "${download_dir}/${luci_name}" 2>/dev/null || {
        echo "[错误] LuCI 安装失败"
        return 1
    }

    if [ -n "$i18n_name" ] && [ -f "${download_dir}/${i18n_name}" ]; then
        echo "  安装中文语言包..."
        apk add --allow-untrusted --force-overwrite "${download_dir}/${i18n_name}" 2>/dev/null || \
            echo "  [警告] 中文包安装失败"
    fi

    echo ""
    echo "[成功] PassWall 安装完成"
    restart_luci
    show_success
}

# ============================================================
# 卸载 PassWall
# ============================================================
uninstall_passwall() {
    echo ""
    echo "================================"
    echo " 卸载 PassWall"
    echo "================================"
    echo ""

    apk del luci-app-passwall luci-i18n-passwall-zh-cn 2>/dev/null

    echo ""
    echo "[完成] PassWall 已卸载"
    echo "[提示] 依赖包保留未删除，如需清理:"
    echo "  apk del xray-core sing-box chinadns-ng dns2socks ..."
    show_success
}

# ============================================================
# 更新 PassWall
# ============================================================
update_passwall() {
    echo ""
    echo "================================"
    echo " 更新 PassWall"
    echo "================================"
    echo ""
    cleanup_old_cache
    install_passwall
}
