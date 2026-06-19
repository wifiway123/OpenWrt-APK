#!/bin/sh
# plugins/luci-app-advanced-uninstall.sh - 高级卸载插件模块

install_advanced_uninstall() {
    echo ""
    echo "================================"
    echo " 安装 高级卸载"
    echo "================================"
    echo ""

    local owner="Linsen-Gao"
    local repo="luci-app-advanced-uninstall"
    local plugin_name="luci-app-advanced-uninstall"

    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || return 1

    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json" "$owner" "$repo" "$tag")

    local run_url
    run_url=$(echo "$all_urls" | grep "\.run$" | head -1)

    if [ -z "$run_url" ]; then
        echo "[错误] 未找到安装文件"
        return 1
    fi

    local filename
    filename=$(basename "$run_url")

    if ! download_file "$run_url" "${CACHE_DIR}/${plugin_name}/${filename}"; then
        echo "[错误] 下载失败"
        return 1
    fi

    local download_dir="${CACHE_DIR}/${plugin_name}"
    local extracted_dir="${download_dir}/extracted"
    rm -rf "$extracted_dir"
    mkdir -p "$extracted_dir"

    echo "[解压] 正在解压安装包..."
    chmod +x "${download_dir}/${filename}"

    if ! sh "${download_dir}/${filename}" --target "$extracted_dir" --noexec 2>/dev/null; then
        echo "[错误] 解压失败"
        rm -rf "$download_dir"
        return 1
    fi

    rm -f "${download_dir}/${filename}"

    # 查找 ipk 安装文件
    local ipk_file
    ipk_file=$(find "$extracted_dir" -name "*.ipk" 2>/dev/null | head -1)

    if [ -z "$ipk_file" ]; then
        echo "[错误] 未找到安装包文件"
        rm -rf "$download_dir"
        return 1
    fi

    echo "[安装] 正在安装 ${ipk_file##*/}..."

    # ipk 是 tar.gz 格式，手动解压 data.tar.gz 到根目录
    local ipk_extract_dir="${download_dir}/ipk_extract"
    rm -rf "$ipk_extract_dir"
    mkdir -p "$ipk_extract_dir"

    if ! tar -xzf "$ipk_file" -C "$ipk_extract_dir" 2>/dev/null; then
        echo "[错误] 解压 ipk 失败"
        rm -rf "$download_dir"
        return 1
    fi

    if [ -f "${ipk_extract_dir}/data.tar.gz" ]; then
        echo "[安装] 释放文件到系统..."
        tar -xzf "${ipk_extract_dir}/data.tar.gz" -C / 2>/dev/null
    fi

    # 执行安装后脚本
    if [ -f "${ipk_extract_dir}/control.tar.gz" ]; then
        local control_dir="${download_dir}/control"
        rm -rf "$control_dir"
        mkdir -p "$control_dir"
        tar -xzf "${ipk_extract_dir}/control.tar.gz" -C "$control_dir" 2>/dev/null

        if [ -x "${control_dir}/postinst" ]; then
            echo "[脚本] 执行安装后脚本..."
            "${control_dir}/postinst" configure 2>/dev/null
        fi
        if [ -x "${control_dir}/postinst-pkg" ]; then
            "${control_dir}/postinst-pkg" configure 2>/dev/null
        fi
        rm -rf "$control_dir"
    fi

    rm -rf "$download_dir"
    echo "[成功] 安装完成"

    echo "[重启] 重启 LuCI..."
    restart_luci

    show_success
}

uninstall_advanced_uninstall() {
    echo ""
    echo "================================"
    echo " 卸载 高级卸载"
    echo "================================"
    echo ""

    uninstall_plugin "luci-app-advanced-uninstall"

    show_success
}

update_advanced_uninstall() {
    echo ""
    echo "================================"
    echo " 更新 高级卸载"
    echo "================================"
    echo ""

    cleanup_old_cache
    install_advanced_uninstall
}