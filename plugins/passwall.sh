#!/bin/sh
# plugins/passwall.sh - PassWall 科学上网插件模块

# 从 SourceForge 下载指定包
_download_sf_pkg() {
    local sf_dir="$1"
    local pkg_pattern="$2"
    local output_dir="$3"

    local page
    page=$(wget -q --timeout=15 --user-agent="OpenWrt-APK-Store/1.0" -O- "${sf_dir}" 2>/dev/null)
    [ -z "$page" ] && return 1

    # 从 HTML 解析 .apk 文件的下载链接
    local dl_path
    dl_path=$(echo "$page" | grep -o '/projects/openwrt-passwall-build/files/[^"'"'"']*'"${pkg_pattern}"'[^"'"'"']*\.apk[^"'"'"']*' | head -1)
    [ -z "$dl_path" ] && return 1

    # 去掉尾部查询参数（?xxx）
    dl_path=$(echo "$dl_path" | sed 's/\?.*//')
    # 去掉尾部 /stats/timeline
    dl_path=$(echo "$dl_path" | sed 's|/stats/timeline$||')

    local filename
    # 从路径中提取文件名（最后一个 / 和 .apk 之间的部分）
    filename=$(echo "$dl_path" | sed 's|.*/\([^/]*\.apk\).*|\1|')
    [ -z "$filename" ] && return 1

    local dl_url="https://sourceforge.net${dl_path}"
    if ! download_file "$dl_url" "${output_dir}/${filename}"; then
        return 1
    fi
    echo "${output_dir}/${filename}"
    return 0
}

# 从 SourceForge passwall_packages 下载所有依赖包
_download_passwall_deps() {
    local sf_base="$1"
    local output_dir="$2"
    local deps="dns2socks ipt2socks pdnsd-alt microsocks tcping chinadns-ng haveged"
    local downloaded=""
    local count=0

    for dep in $deps; do
        local file
        file=$(_download_sf_pkg "${sf_base}" "${dep}" "${output_dir}")
        if [ -n "$file" ] && [ -f "$file" ]; then
            downloaded="$downloaded $file"
            count=$((count + 1))
        fi
    done

    echo "$downloaded"
    [ "$count" -gt 0 ]
}

install_passwall() {
    echo ""
    echo "================================"
    echo " 安装 PassWall"
    echo "================================"
    echo ""

    local owner="Openwrt-Passwall"
    local repo="openwrt-passwall"
    local plugin_name="passwall"

    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || return 1

    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    local all_urls
    all_urls=$(get_download_urls "$release_json" "$owner" "$repo" "$tag")

    local download_dir="${CACHE_DIR}/${plugin_name}"
    rm -rf "$download_dir"
    mkdir -p "$download_dir"

    . /etc/openwrt_release 2>/dev/null

    local release_major
    release_major=$(echo "$DISTRIB_RELEASE" | cut -d'.' -f1)
    local release_ver
    release_ver=$(echo "$DISTRIB_RELEASE" | cut -d'.' -f1,2)
    [ -z "$release_ver" ] && release_ver="25.12"
    local is_apk=0
    case "$release_ver" in
        25.*|snapshot) is_apk=1 ;;
    esac
    [ "$is_apk" -eq 1 ] && pkg_ext="apk" || pkg_ext="ipk"

    local arch="${DISTRIB_ARCH:-$(uname -m)}"

    # SourceForge 路径用主版本号，如 packages-25.12
    local sf_ver="packages-${release_major}.12"
    [ "$release_ver" = "snapshot" ] && sf_ver="snapshots"

    echo "[步骤 1/2] 下载 PassWall 主程序..."
    local main_url
    main_url=$(echo "$all_urls" | grep "luci-app-passwall" | grep "\.${pkg_ext}$" | head -1)

    if [ -z "$main_url" ]; then
        echo "[重试] 未找到 ${pkg_ext} 格式，尝试另一种格式..."
        case "$pkg_ext" in
            apk) main_url=$(echo "$all_urls" | grep "luci-app-passwall" | grep "\.ipk$" | head -1) ;;
            ipk) main_url=$(echo "$all_urls" | grep "luci-app-passwall" | grep "\.apk$" | head -1) ;;
        esac
    fi

    if [ -z "$main_url" ]; then
        echo "[错误] 未找到 PassWall 主程序包"
        return 1
    fi

    local main_file
    main_file=$(basename "$main_url")
    main_file=$(echo "$main_file" | sed 's/%2B/+/g')

    if ! download_file "$main_url" "${download_dir}/${main_file}"; then
        echo "[错误] 主程序下载失败"
        return 1
    fi

    if [ ! -s "${download_dir}/${main_file}" ]; then
        echo "[错误] 下载文件为空"
        rm -f "${download_dir}/${main_file}"
        return 1
    fi
    echo "[成功] 主程序下载完成"

    echo "[步骤 2/2] 下载中文语言包..."
    local i18n_url
    i18n_url=$(echo "$all_urls" | grep "luci-i18n-passwall-zh-cn" | grep "\.${pkg_ext}$" | head -1)

    if [ -z "$i18n_url" ]; then
        echo "[重试] 未找到 ${pkg_ext} 格式语言包，尝试另一种格式..."
        case "$pkg_ext" in
            apk) i18n_url=$(echo "$all_urls" | grep "luci-i18n-passwall-zh-cn" | grep "\.ipk$" | head -1) ;;
            ipk) i18n_url=$(echo "$all_urls" | grep "luci-i18n-passwall-zh-cn" | grep "\.apk$" | head -1) ;;
        esac
    fi

    if [ -n "$i18n_url" ]; then
        local i18n_file
        i18n_file=$(basename "$i18n_url")
        i18n_file=$(echo "$i18n_file" | sed 's/%2B/+/g')
        if ! download_file "$i18n_url" "${download_dir}/${i18n_file}"; then
            echo "[警告] 语言包下载失败，继续安装主程序..."
            i18n_url=""
        fi
    else
        echo "[警告] 未找到中文语言包"
    fi

    # 如果当前是 apk 系统，从 SourceForge 下载依赖包
    if [ "$is_apk" -eq 1 ]; then
        echo "[依赖] 从 SourceForge 下载 PassWall 依赖包..."
        local sf_base="https://sourceforge.net/projects/openwrt-passwall-build/files/releases/${sf_ver}/${arch}/passwall_packages/"
        _download_passwall_deps "$sf_base" "$download_dir"
    fi

    echo "[安装] 正在安装..."
    local apk_files=""
    local ipk_files=""
    for f in "${download_dir}"/*.apk "${download_dir}"/*.ipk; do
        [ -f "$f" ] || continue
        case "$f" in
            *.apk) apk_files="$apk_files $f" ;;
            *.ipk) ipk_files="$ipk_files $f" ;;
        esac
    done

    if [ -n "$apk_files" ] && apk add --allow-untrusted --force-overwrite $apk_files; then
        echo "[成功] PassWall 安装完成"
    elif [ -n "$ipk_files" ] && opkg install --force-overwrite $ipk_files; then
        echo "[成功] PassWall 安装完成"
    else
        echo ""
        echo "[错误] PassWall 安装失败。"
        echo ""
        echo "原因：依赖包不在标准 OpenWrt 软件源中。"
        echo ""
        echo "解决方法（任选其一）："
        echo ""
        echo "1. 添加 PassWall 构建源后重试："
        echo "   https://github.com/moetayuko/openwrt-passwall-build"
        echo ""
        echo "2. 手动从 SourceForge 下载依赖后重试："
        echo "   https://sourceforge.net/projects/openwrt-passwall-build/files/releases/${sf_ver}/${arch}/passwall_packages/"
        echo ""

        # 显示已下载但安装失败的文件
        local file_list
        file_list=$(ls "${download_dir}"/*."${pkg_ext}" 2>/dev/null | head -5)
        if [ -n "$file_list" ]; then
            echo "已下载的文件："
            for f in $file_list; do
                echo "  $(basename "$f") ($(du -h "$f" | cut -f1))"
            done
            echo ""
            echo "手动安装命令："
            echo "  cd ${download_dir} && apk add --allow-untrusted $(ls *.apk 2>/dev/null | tr '\n' ' ')"
            echo ""
        fi

        return 1
    fi

    echo "[修复] 修复依赖..."
    fix_dependencies

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
