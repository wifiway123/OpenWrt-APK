#!/bin/sh
# plugins/luci-app-cloudflared.sh - Cloudflared Cloudflare 隧道插件模块

install_cloudflared() {
    echo ""
    echo "================================"
    echo " 安装 Cloudflared"
    echo "================================"
    echo ""

    # 清理 cloudflared 专属缓存，确保获取最新版本
    local cache_dir="${CACHE_DIR}/cloudflared"
    if [ -d "$cache_dir" ]; then
        echo "[清理] 清理 cloudflared 旧缓存..."
        rm -rf "$cache_dir"
    fi

    local arch
    arch=$(detect_arch) || return 1
    echo "[架构] $arch"

    . /etc/openwrt_release 2>/dev/null
    local release_ver
    release_ver=$(echo "$DISTRIB_RELEASE" | cut -d'.' -f1,2)
    local is_apk=0
    case "$release_ver" in
        25.*|snapshot) is_apk=1 ;;
    esac
    echo "[系统] OpenWrt $DISTRIB_RELEASE ($([ "$is_apk" -eq 1 ] && echo 'APK' || echo 'OPKG'))"

    # ---------- 方式一: 通过包管理器安装 ----------
    echo "[步骤 1/2] 尝试通过包管理器安装..."

    local pkg_ok=0
    local luci_ok=0

    if [ "$is_apk" -eq 1 ]; then
        if apk add cloudflared 2>/dev/null; then
            echo "[成功] cloudflared 核心安装完成"
            pkg_ok=1
        else
            echo "[提示] 软件源中未找到 cloudflared 包，改用手动安装"
        fi
        # 可选安装 LuCI 界面及中文包
        apk add luci-app-cloudflared 2>/dev/null && echo "[成功] luci-app-cloudflared 安装完成" && luci_ok=1 || \
            echo "[提示] 软件源中未提供 luci-app-cloudflared"
        apk add luci-i18n-cloudflared-zh-cn 2>/dev/null && echo "[成功] luci-i18n-cloudflared-zh-cn 安装完成" || \
            echo "[提示] 软件源中未提供 luci-i18n-cloudflared-zh-cn"
    else
        opkg update 2>/dev/null
        if opkg install cloudflared 2>/dev/null; then
            echo "[成功] cloudflared 核心安装完成"
            pkg_ok=1
        else
            echo "[提示] 软件源中未找到 cloudflared 包，改用手动安装"
        fi
        opkg install luci-app-cloudflared 2>/dev/null && echo "[成功] luci-app-cloudflared 安装完成" && luci_ok=1 || \
            echo "[提示] 软件源中未提供 luci-app-cloudflared"
        opkg install luci-i18n-cloudflared-zh-cn 2>/dev/null && echo "[成功] luci-i18n-cloudflared-zh-cn 安装完成" || \
            echo "[提示] 软件源中未提供 luci-i18n-cloudflared-zh-cn"
    fi

    # 核心未装上 -> 手动安装二进制
    if [ "$pkg_ok" -eq 0 ]; then
        install_cloudflared_manual "$arch" || return 1
    fi

    echo "[修复] 修复依赖..."
    fix_dependencies

    echo "[重启] 重启 LuCI..."
    restart_luci

    show_success

    if [ "$luci_ok" -eq 0 ]; then
        echo "[提示] 未安装 LuCI 前端，可使用命令行配置 /etc/cloudflared/config.yml"
        echo "       或手动从第三方仓库获取 luci-app-cloudflared 前端"
    fi
    return 0
}

# 手动安装 cloudflared 二进制（当包管理器不可用时）
install_cloudflared_manual() {
    local arch="$1"

    echo ""
    echo "[手动] 从 cloudflare/cloudflared 官方 GitHub 下载..."

    local owner="cloudflare"
    local repo="cloudflared"
    local plugin_name="cloudflared"

    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || return 1

    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json" "$owner" "$repo" "$tag")

    # 架构映射（cloudflared release 文件命名规则）
    local cf_arch
    case "$arch" in
        x86_64)
            cf_arch="amd64"
            ;;
        aarch64)
            cf_arch="arm64"
            ;;
        arm)
            cf_arch="arm"
            ;;
        *)
            echo "[错误] cloudflared 不支持架构: $arch (仅支持 x86_64/aarch64/arm)"
            return 1
            ;;
    esac

    # 精确匹配二进制（排除 .deb/.rpm/.pkg 等同名扩展）
    local bin_url
    bin_url=$(echo "$all_urls" | grep "cloudflared-linux-${cf_arch}$" | head -1)

    if [ -z "$bin_url" ]; then
        echo "[错误] 未找到匹配架构 ${arch} (cloudflared-linux-${cf_arch}) 的二进制"
        echo "[提示] 可用文件列表:"
        echo "$all_urls" | grep "cloudflared-linux-" | grep -v '\.deb$' | grep -v '\.rpm$' | grep -v '\.pkg$' | head -10
        return 1
    fi

    local download_dir="${CACHE_DIR}/${plugin_name}"
    rm -rf "$download_dir"
    mkdir -p "$download_dir"

    local bin_name="cloudflared-linux-${cf_arch}"
    echo "[下载] $bin_name ..."
    if ! download_file "$bin_url" "${download_dir}/${bin_name}"; then
        echo "[错误] 下载失败"
        rm -rf "$download_dir"
        return 1
    fi

    if [ ! -s "${download_dir}/${bin_name}" ]; then
        echo "[错误] 下载文件为空"
        rm -rf "$download_dir"
        return 1
    fi

    echo "[安装] 安装 cloudflared 到 /usr/bin/cloudflared ..."
    mkdir -p /usr/bin
    # 停止旧服务避免占用二进制
    [ -x /etc/init.d/cloudflared ] && /etc/init.d/cloudflared stop 2>/dev/null
    cp -f "${download_dir}/${bin_name}" /usr/bin/cloudflared
    chmod +x /usr/bin/cloudflared

    if [ ! -x /usr/bin/cloudflared ]; then
        echo "[错误] 复制或赋权失败"
        rm -rf "$download_dir"
        return 1
    fi

    # 配置目录
    mkdir -p /etc/cloudflared

    # 注册 init 服务（若不存在，避免覆盖官方包提供的脚本）
    if [ ! -f /etc/init.d/cloudflared ]; then
        echo "[服务] 注册系统服务..."
        cat > /etc/init.d/cloudflared << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1

PROG=/usr/bin/cloudflared
CONFIG_FILE=/etc/cloudflared/config.yml

start_service() {
    [ -x "$PROG" ] || return 1
    procd_open_instance
    procd_set_param command "$PROG" tunnel --no-autoupdate --config "$CONFIG_FILE" run
    procd_set_param respawn 60 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

reload() {
    restart
}

service_triggers() {
    procd_add_reload_trigger "cloudflared"
}
INITEOF
        chmod +x /etc/init.d/cloudflared
        /etc/init.d/cloudflared enable 2>/dev/null
    fi

    echo "[成功] cloudflared 二进制安装完成"
    echo ""
    echo "========================================"
    echo "  配置说明:"
    echo "  1. 在 /etc/cloudflared/config.yml 写入隧道配置"
    echo "  2. 执行: /etc/init.d/cloudflared start"
    echo "  3. 如已安装 luci-app-cloudflared，可在 LuCI 界面配置"
    echo "========================================"
    echo ""

    rm -rf "$download_dir"
    return 0
}

uninstall_cloudflared() {
    echo ""
    echo "================================"
    echo " 卸载 Cloudflared"
    echo "================================"
    echo ""

    # 判断是包管理安装还是手动安装
    local pkg_installed=0
    if command -v apk >/dev/null 2>&1 && apk info --installed cloudflared >/dev/null 2>&1; then
        pkg_installed=1
    elif command -v opkg >/dev/null 2>&1 && opkg list-installed 2>/dev/null | grep -q "^cloudflared "; then
        pkg_installed=1
    fi

    # 停止服务
    echo "[停止] 停止服务..."
    [ -x /etc/init.d/cloudflared ] && /etc/init.d/cloudflared stop 2>/dev/null
    [ -x /etc/init.d/cloudflared ] && /etc/init.d/cloudflared disable 2>/dev/null

    if [ "$pkg_installed" -eq 1 ]; then
        echo "[卸载] 通过包管理器卸载核心..."
        if command -v apk >/dev/null 2>&1; then
            apk del cloudflared 2>/dev/null
        else
            opkg remove cloudflared 2>/dev/null
        fi
    else
        echo "[卸载] 卸载手动安装版本..."
        rm -f /usr/bin/cloudflared
        rm -f /etc/init.d/cloudflared
    fi

    # LuCI 前端卸载
    echo "[卸载] 卸载 LuCI 前端..."
    if command -v apk >/dev/null 2>&1; then
        apk del luci-app-cloudflared 2>/dev/null
        apk del luci-i18n-cloudflared-zh-cn 2>/dev/null
    else
        opkg remove luci-app-cloudflared 2>/dev/null
        opkg remove luci-i18n-cloudflared-zh-cn 2>/dev/null
    fi

    # 残留清理（保留 /etc/cloudflared 用户配置数据）
    rm -rf /usr/share/luci/menu.d/*cloudflared* 2>/dev/null
    rm -rf /usr/share/rpcd/acl.d/*cloudflared* 2>/dev/null
    rm -rf /www/luci-static/resources/*cloudflared* 2>/dev/null
    rm -rf /usr/lib/lua/luci/*cloudflared* 2>/dev/null

    echo "[提示] 已保留 /etc/cloudflared 配置目录（如需彻底清理请手动删除）"

    echo "[重启] 重启 LuCI..."
    restart_luci

    show_success
}

update_cloudflared() {
    echo ""
    echo "================================"
    echo " 更新 Cloudflared"
    echo "================================"
    echo ""

    cleanup_old_cache
    install_cloudflared
}
