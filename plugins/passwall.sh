#!/bin/sh
# plugins/passwall.sh - luci-app-passwall 插件模块
#
# 包来源：
#   - Layer 1 (系统层): OpenWrt 官方源 (apk/opkg)
#   - Layer 2 (PassWall 依赖): SourceForge (openwrt-passwall-build)
#   - Layer 3 (LuCI): GitHub Releases (Openwrt-Passwall/openwrt-passwall)
#
# 安装顺序：
#   系统硬依赖 → 透明代理组件 → PassWall 核心包 → LuCI 本体 → 中文包

SF_PROJECT="openwrt-passwall-build"
SF_BASE="https://downloads.sourceforge.net/project/${SF_PROJECT}/files/releases"

# ============================================================
# 环境检测
# ============================================================

_get_openwrt_version() {
    . /etc/openwrt_release 2>/dev/null || return 1
    local ver
    ver=$(echo "$DISTRIB_RELEASE" | cut -d'.' -f1,2)
    echo "$ver"
}

_get_openwrt_arch() {
    . /etc/openwrt_release 2>/dev/null || return 1
    echo "$DISTRIB_ARCH"
}

_is_apk_system() {
    local ver
    ver=$(_get_openwrt_version) || return 1
    case "$ver" in
        25.*|snapshot) return 0 ;;
        *) return 1 ;;
    esac
}

_get_sf_packages_ver() {
    local ver
    ver=$(_get_openwrt_version) || return 1
    case "$ver" in
        25.*)     echo "packages-25.12" ;;
        24.*)     echo "packages-24.10" ;;
        23.*)     echo "packages-23.05" ;;
        22.*)     echo "packages-22.03" ;;
        21.*)     echo "packages-21.02" ;;
        snapshot) echo "packages-25.12" ;;
        *)        echo "packages-25.12" ;;
    esac
}

# ============================================================
# 解析 SourceForge 目录页面的文件名列表
# ============================================================
_list_sf_files() {
    local dir_url="$1"
    local ext="${2:-apk}"

    local page
    page=$(wget -q --timeout=30 -O- "$dir_url" 2>/dev/null) || return 1

    # HTML: <a href=".../xxx.apk/download">xxx.apk</a>
    # 提取文件名后去掉 /download 后缀
    echo "$page" | grep -oE 'href="[^"]*\.'"$ext"'[^"]*"' | \
        sed 's/.*\///;s/\.'"$ext"'.*/.'"$ext"'/;s/"//g'
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

    # ---- 1. 检测环境 ----
    local arch
    arch=$(_get_openwrt_arch) || {
        echo "[错误] 无法获取架构信息"
        return 1
    }
    echo "[架构] $arch"

    local ver
    ver=$(_get_openwrt_version) || {
        echo "[错误] 无法获取 OpenWrt 版本"
        return 1
    }
    echo "[版本] OpenWrt $ver"

    local is_apk=0
    _is_apk_system && is_apk=1
    local ext="ipk"
    $is_apk && ext="apk"
    echo "[包格式] $ext"

    local sf_ver
    sf_ver=$(_get_sf_packages_ver) || return 1
    local sf_base_url="${SF_BASE}/${sf_ver}/${arch}"
    echo "[SourceForge] $sf_ver/${arch}"

    # ---- 2. 获取 GitHub 最新版本 ----
    echo ""
    echo "[查询] 检查 GitHub 最新版本..."
    local owner="Openwrt-Passwall"
    local repo="openwrt-passwall"
    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || {
        echo "[错误] 无法获取 GitHub Releases"
        return 1
    }
    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json")

    # 匹配适合当前系统的 LuCI 包 URL
    local luci_url i18n_url
    if [ "$is_apk" -eq 1 ]; then
        luci_url=$(echo "$all_urls" | grep "25.12+" | grep "luci-app-passwall" | grep "\.apk$" | head -1)
        i18n_url=$(echo "$all_urls" | grep "25.12+" | grep "luci-i18n-passwall-zh-cn" | grep "\.apk$" | head -1)
    else
        luci_url=$(echo "$all_urls" | grep "23.05-24.10" | grep "luci-app-passwall" | grep "\.ipk$" | head -1)
        i18n_url=$(echo "$all_urls" | grep "23.05-24.10" | grep "luci-i18n-passwall-zh-cn" | grep "\.ipk$" | head -1)
        if [ -z "$luci_url" ]; then
            luci_url=$(echo "$all_urls" | grep "22.03" | grep "luci-app-passwall" | grep "\.ipk$" | head -1)
            i18n_url=$(echo "$all_urls" | grep "22.03" | grep "luci-i18n-passwall-zh-cn" | grep "\.ipk$" | head -1)
        fi
    fi

    if [ -z "$luci_url" ]; then
        echo "[错误] 未找到 luci-app-passwall 安装包"
        return 1
    fi
    local luci_name
    luci_name=$(basename "$luci_url")
    local i18n_name=""
    [ -n "$i18n_url" ] && i18n_name=$(basename "$i18n_url")

    # ---- 3. 准备下载目录 ----
    local download_dir="${CACHE_DIR}/passwall"
    rm -rf "$download_dir"
    mkdir -p "$download_dir"

    # ====================================================
    # Layer 1: 从 OpenWrt 官方源安装系统硬依赖
    # ====================================================
    echo ""
    echo "================================"
    echo " Layer 1: 安装系统硬依赖"
    echo "================================"
    echo ""

    local sys_deps="coreutils coreutils-base64 coreutils-nohup curl dnsmasq-full ip-full libuci-lua lua luci-compat luci-lib-jsonc resolveip lyaml"

    printf "[安装] "
    if [ "$is_apk" -eq 1 ]; then
        for pkg in $sys_deps; do
            printf "%s " "$pkg"
            apk add "$pkg" 2>/dev/null
        done
    else
        for pkg in $sys_deps; do
            printf "%s " "$pkg"
            opkg install "$pkg" 2>/dev/null
        done
    fi
    echo ""
    echo "[完成] 系统依赖安装完毕"

    # ====================================================
    # Layer 2: 透明代理组件 (从官方源安装)
    # ====================================================
    echo ""
    echo "================================"
    echo " Layer 2: 透明代理组件"
    echo "================================"
    echo ""

    # 检测 firewall 类型
    local use_nftables=0
    if command -v fw4 >/dev/null 2>&1 || [ -f /etc/config/firewall4 ] 2>/dev/null; then
        use_nftables=1
        echo "[检测] Nftables 模式 (firewall4)"
    else
        echo "[检测] Iptables 模式 (firewall3)"
    fi

    local tproxy_deps
    if [ "$use_nftables" -eq 1 ]; then
        tproxy_deps="nftables kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
    else
        tproxy_deps="ipset iptables iptables-zz-legacy iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy kmod-ipt-nat"
    fi
    # ipt2socks 来自 passwall-packages，在 Layer 3 从 SourceForge 获取

    printf "[安装] "
    if [ "$is_apk" -eq 1 ]; then
        for pkg in $tproxy_deps; do
            printf "%s " "$pkg"
            apk add "$pkg" 2>/dev/null
        done
    else
        for pkg in $tproxy_deps; do
            printf "%s " "$pkg"
            opkg install "$pkg" 2>/dev/null
        done
    fi
    echo ""
    echo "[完成] 透明代理组件安装完毕"

    # ====================================================
    # Layer 3: PassWall 依赖包 (从 SourceForge 下载)
    # ====================================================
    echo ""
    echo "================================"
    echo " Layer 3: PassWall 核心依赖"
    echo "================================"
    echo ""

    # 构建 SourceForge 目录 URL 用于文件列表扫描
    local sf_dir_url="${SF_BASE}/${sf_ver}/${arch}"
    if [ "$is_apk" -eq 1 ]; then
        # 25.12+: passwall_packages/ 子目录
        sf_dir_url="https://sourceforge.net/projects/${SF_PROJECT}/files/releases/${sf_ver}/${arch}/passwall_packages/"
    else
        # 24.10 及更早: 直接在架构目录下
        sf_dir_url="https://sourceforge.net/projects/${SF_PROJECT}/files/releases/${sf_ver}/${arch}/"
    fi
    echo "[扫描] $sf_dir_url"

    local file_list
    file_list=$(_list_sf_files "$sf_dir_url" "$ext") || {
        echo "[错误] SourceForge 包列表获取失败"
        return 1
    }

    if [ -z "$file_list" ]; then
        echo "[错误] SourceForge 源中未找到任何 $ext 包"
        return 1
    fi

    # PassWall 需要从 SourceForge 获取的包
    local pw_pkgs="chinadns-ng dns2socks ipt2socks microsocks tcping xray-core sing-box shadowsocks-rust-sslocal v2ray-geoip v2ray-geosite simple-obfs-client v2ray-plugin shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir geoview haproxy hysteria naiveproxy shadow-tls xray-plugin"

    local dl_count=0
    local mt_count=0
    local dl_fail=0

    for need in $pw_pkgs; do
        # 精确匹配: 包名-版本号.ext
        local matched
        matched=$(echo "$file_list" | grep -i "^${need}-" | head -1)
        # 回退: 包含包名
        [ -z "$matched" ] && matched=$(echo "$file_list" | grep -i "${need}" | head -1)

        if [ -n "$matched" ]; then
            mt_count=$((mt_count + 1))

            # 构造下载 URL
            local dl_url
            if [ "$is_apk" -eq 1 ]; then
                dl_url="${sf_base_url}/passwall_packages/${matched}"
            else
                dl_url="${sf_base_url}/${matched}"
            fi

            local output="${download_dir}/${matched}"
            if [ -f "$output" ] && [ -s "$output" ]; then
                echo "[跳过] $matched"
            else
                if download_file "$dl_url" "$output"; then
                    dl_count=$((dl_count + 1))
                else
                    dl_fail=$((dl_fail + 1))
                    echo "[警告] 下载失败: $matched"
                fi
            fi
        else
            echo "[跳过] $need (未在 SourceForge 中找到)"
        fi
    done

    echo "[汇总] 匹配 $mt_count 个，下载 $dl_count 个，失败 $dl_fail 个"

    # ---- 同时下载 LuCI 包到同一目录 ----
    echo ""
    echo "[下载] LuCI 主程序..."
    download_file "$luci_url" "${download_dir}/${luci_name}" || {
        echo "[错误] LuCI 包下载失败"
        return 1
    }

    if [ -n "$i18n_url" ]; then
        echo "[下载] 中文语言包..."
        download_file "$i18n_url" "${download_dir}/${i18n_name}" || echo "[警告] 中文包下载失败"
    fi

    # ---- 检查是否有可安装的包 ----
    local pkg_total
    pkg_total=$(find "$download_dir" -maxdepth 1 \( -name "*.apk" -o -name "*.ipk" \) 2>/dev/null | wc -l)
    if [ "$pkg_total" -eq 0 ]; then
        echo "[错误] 没有任何包可安装"
        return 1
    fi
    echo "[准备] 共 $pkg_total 个包"

    # ====================================================
    # Layer 4: 安装
    # ====================================================
    echo ""
    echo "================================"
    echo " 开始安装 (共 $pkg_total 个包)"
    echo "================================"
    echo ""

    cd "$download_dir" || return 1

    # Step A: 先安装依赖包（排除 LuCI 本体和 i18n）
    echo "[安装] 依赖包..."
    local dep_files=""
    local f
    for f in "$download_dir"/*."${ext}" "$download_dir"/*.apk "$download_dir"/*.ipk; do
        [ -f "$f" ] || continue
        local base
        base=$(basename "$f")
        case "$base" in
            luci-app-passwall*|luci-i18n-passwall*) continue ;;
            *) dep_files="$dep_files $f" ;;
        esac
    done

    if [ -n "$dep_files" ]; then
        if [ "$is_apk" -eq 1 ]; then
            apk add --allow-untrusted --force-overwrite $dep_files 2>/dev/null || {
                echo "[警告] 部分依赖包安装异常，继续..."
            }
        else
            opkg install --force-reinstall --force-overwrite $dep_files 2>/dev/null || {
                echo "[警告] 部分依赖包安装异常，继续..."
            }
        fi
    fi

    # Step B: 安装 LuCI 主程序
    echo ""
    echo "[安装] LuCI 主程序..."
    if [ "$is_apk" -eq 1 ]; then
        apk add --allow-untrusted "${download_dir}/${luci_name}" 2>/dev/null || {
            echo "[错误] LuCI 安装失败"
            return 1
        }
    else
        opkg install --force-overwrite "${download_dir}/${luci_name}" 2>/dev/null || {
            echo "[错误] LuCI 安装失败"
            return 1
        }
    fi

    # Step C: 安装中文包
    if [ -n "$i18n_name" ] && [ -f "${download_dir}/${i18n_name}" ]; then
        echo ""
        echo "[安装] 中文语言包..."
        if [ "$is_apk" -eq 1 ]; then
            apk add --allow-untrusted "${download_dir}/${i18n_name}" 2>/dev/null || echo "[警告] 中文包安装失败"
        else
            opkg install --force-overwrite "${download_dir}/${i18n_name}" 2>/dev/null || echo "[警告] 中文包安装失败"
        fi
    fi

    # ---- 完成 ----
    echo ""
    echo "[成功] PassWall 安装完成"

    # 重启 LuCI
    echo "[重启] 重启 LuCI..."
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

    local cmd="opkg remove"
    _is_apk_system && cmd="apk del"

    $cmd luci-app-passwall 2>/dev/null
    $cmd luci-i18n-passwall-zh-cn 2>/dev/null

    echo ""
    echo "[提示] PassWall 已卸载"
    echo "[提示] 依赖包（xray-core, sing-box, chinadns-ng 等）未被清理"
    echo "  如需清理请手动执行: $cmd xray-core sing-box chinadns-ng dns2socks ..."
    echo "  如需清理系统依赖请手动执行: $cmd coreutils curl dnsmasq-full ip-full lua ..."

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
