#!/bin/sh
# core/doctor.sh - 查看系统信息
# 调用方式: show_system_info

show_system_info() {
    echo ""
    echo "======== 系统信息 ========"

    # 版本
    local ver=""
    [ -f /etc/openwrt_release ] && ver=$(grep "DISTRIB_DESCRIPTION" /etc/openwrt_release | cut -d"'" -f2)
    echo "  固件: ${ver:-未知}"

    # 架构 + 内核
    echo "  架构: $(uname -m) | 内核: $(uname -r)"

    # 包管理器
    local pkg="未知" pkg_count="?" pkg_arch=""
    if command -v apk >/dev/null 2>&1; then
        pkg="apk"; pkg_count=$(apk list --installed 2>/dev/null | wc -l)
        pkg_arch=$(apk --print-arch 2>/dev/null)
        echo "  包管理: $pkg ($pkg_count 包) | APK 架构: $pkg_arch"
    elif command -v opkg >/dev/null 2>&1; then
        pkg="opkg"; pkg_count=$(opkg list-installed 2>/dev/null | wc -l)
        echo "  包管理: $pkg ($pkg_count 包)"
    else
        echo "  包管理: 未知"
    fi

    # 磁盘
    df -h 2>/dev/null | awk '
        NR==1{printf "  磁盘: %s\n", $0}
        /overlay$/||/\/root/||/\/overlay/||/\/$/{
            if(NR>1) printf "        %s\n", $0
        }'

    # 内存
    local mem_total mem_free
    if command -v free >/dev/null 2>&1; then
        free -h 2>/dev/null | awk '/Mem:/{printf "  内存: 总 %s  已用 %s  可用 %s\n", $2, $3, $4}'
    else
        mem_total=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
        mem_free=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
        [ -n "$mem_total" ] && echo "  内存: 总 ${mem_total}MiB  可用 ${mem_free}MiB"
    fi

    # overlay 使用率（单行）
    if mount | grep -q "overlayfs:/overlay on /"; then
        df /overlay 2>/dev/null | awk 'NR==2{printf "  overlay: 总 %s  已用 %s  可用 %s  使用率 %s\n", $2, $3, $4, $5}'
    else
        df / 2>/dev/null | awk 'NR==2{printf "  /: 总 %s  已用 %s  可用 %s  使用率 %s\n", $2, $3, $4, $5}'
    fi

    echo "=========================="
    echo ""
}
