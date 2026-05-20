#!/bin/sh
# plugins/passwall.sh - luci-app-passwall 插件模块

install_passwall() {
    echo ""
    echo "================================"
    echo " 安装 PassWall"
    echo "================================"
    echo ""

    local arch
    arch=$(detect_arch) || return 1
    echo "[架构] $arch"

    local owner="xiaorouji"
    local repo="openwrt-passwall"
    local plugin_name="passwall"

    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || return 1

    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json")

    local luci_url
    luci_url=$(echo "$all_urls" | grep "luci-app-passwall" | grep "\.ipk$" | head -1)

    local i18n_url
    i18n_url=$(echo "$all_urls" | grep "luci-i18n-passwall-zh-cn" | grep "\.ipk$" | head -1)

    if [ -z "$luci_url" ]; then
        echo "[错误] 未找到 luci-app-passwall 安装包"
        return 1
    fi

    local download_dir="${CACHE_DIR}/${plugin_name}"
    rm -rf "$download_dir"
    mkdir -p "$download_dir"

    local pkg_zip_url
    pkg_zip_url=$(echo "$all_urls" | grep "passwall_packages_ipk_${arch}\.zip$" | head -1)

    if [ -z "$pkg_zip_url" ]; then
        echo "[重试] 未找到精确匹配 ${arch} 的依赖包..."
        pkg_zip_url=$(echo "$all_urls" | grep "passwall_packages_ipk_" | grep "${arch}" | grep "\.zip$" | head -1)
    fi

    if [ -z "$pkg_zip_url" ]; then
        echo "[重试] 尝试模糊匹配..."
        pkg_zip_url=$(echo "$all_urls" | grep "passwall_packages_ipk_" | grep "\.zip$" | head -1)
    fi

    if [ -z "$pkg_zip_url" ]; then
        echo "[错误] 未找到匹配架构 ${arch} 的依赖包"
        return 1
    fi

    local luci_name
    luci_name=$(basename "$luci_url")
    echo "[下载] $luci_name"
    if ! wget -q --timeout=120 -O "${download_dir}/${luci_name}" "$luci_url" 2>/dev/null; then
        echo "[错误] 下载失败: $luci_name"
        rm -f "${download_dir}/${luci_name}"
        return 1
    fi

    if [ -n "$i18n_url" ]; then
        local i18n_name
        i18n_name=$(basename "$i18n_url")
        echo "[下载] $i18n_name"
        wget -q --timeout=60 -O "${download_dir}/${i18n_name}" "$i18n_url" 2>/dev/null || echo "[警告] 中文包下载失败"
    fi

    local zip_name
    zip_name=$(basename "$pkg_zip_url")
    echo "[下载] $zip_name (依赖包)"
    if ! wget -q --timeout=180 -O "${download_dir}/${zip_name}" "$pkg_zip_url" 2>/dev/null; then
        echo "[错误] 下载失败: $zip_name"
        rm -f "${download_dir}/${zip_name}"
        return 1
    fi

    echo "[解压] 正在解压依赖包..."
    if ! unzip -o -q "${download_dir}/${zip_name}" -d "${download_dir}/packages" 2>/dev/null; then
        echo "[错误] 解压失败: $zip_name"
        rm -f "${download_dir}/${zip_name}"
        return 1
    fi

    rm -f "${download_dir}/${zip_name}"

    local ipk_files
    ipk_files=$(find "${download_dir}/packages" -name "*.ipk" 2>/dev/null)

    if [ -z "$ipk_files" ]; then
        echo "[错误] 解压后未找到安装包文件"
        return 1
    fi

    local pkg_count
    pkg_count=$(echo "$ipk_files" | wc -l)
    echo "[安装] 正在安装 $pkg_count 个依赖包..."

    if ! opkg install --force-reinstall --force-overwrite $ipk_files 2>/dev/null; then
        echo "[警告] 部分依赖包安装失败，尝试继续安装主程序..."
    fi

    echo "[安装] 安装 LuCI 主程序..."
    opkg install --force-overwrite "${download_dir}/${luci_name}" 2>/dev/null

    if [ -f "${download_dir}/${i18n_name:-__empty__}" ] && [ -n "$i18n_name" ]; then
        echo "[安装] 安装中文包..."
        opkg install --force-overwrite "${download_dir}/${i18n_name}" 2>/dev/null
    fi

    echo "[成功] 安装完成"

    echo "[重启] 重启 LuCI..."
    restart_luci

    show_success
}

uninstall_passwall() {
    echo ""
    echo "================================"
    echo " 卸载 PassWall"
    echo "================================"
    echo ""

    uninstall_plugin "luci-app-passwall"
    uninstall_plugin "luci-i18n-passwall-zh-cn"

    show_success
}

update_passwall() {
    echo ""
    echo "================================"
    echo " 更新 PassWall"
    echo "================================"
    echo ""

    cleanup_old_cache
    install_passwall
}
