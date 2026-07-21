#!/bin/sh
# plugins/arcane.sh - Arcane (Docker面板) 插件模块

install_arcane() {
    echo ""
    echo "================================"
    echo " 安装 Arcane (Docker面板)"
    echo "================================"
    echo ""

    echo "[安装] 正在运行 Arcane 一键安装脚本..."
    if wget -qO /usr/bin/openwrt-easy https://raw.githubusercontent.com/slobys/openwrt-official-one-click/main/bootstrap.sh && chmod +x /usr/bin/openwrt-easy; then
        echo "[提示] 下载成功，正在启动 openwrt-easy 安装向导..."
        openwrt-easy
        echo "[成功] 执行完毕"
        show_success
    else
        echo "[错误] 下载或设置 openwrt-easy 失败"
        return 1
    fi
}

uninstall_arcane() {
    echo ""
    echo "================================"
    echo " 卸载 Arcane (Docker面板)"
    echo "================================"
    echo ""

    if command -v openwrt-easy >/dev/null 2>&1; then
        echo "[卸载] 正在调用 openwrt-easy 进行卸载..."
        openwrt-easy --arcane-uninstall
    else
        echo "[错误] 未找到 openwrt-easy，可能未安装或已移除。"
        echo "[提示] 如果有残留容器，请手动执行: docker rm -f arcane && docker rmi arcane"
    fi

    echo "[清理] 清理 openwrt-easy 相关文件..."
    rm -f /usr/bin/openwrt-easy 2>/dev/null
    rm -rf /usr/lib/openwrt-official-one-click 2>/dev/null

    echo "[重启] 重启 LuCI..."
    restart_luci

    echo "[成功] 卸载清理完成"
}

update_arcane() {
    echo ""
    echo "================================"
    echo " 更新 Arcane (Docker面板)"
    echo "================================"
    echo ""

    echo "[更新] 正在重新运行 Arcane 一键脚本进行更新..."
    if wget -qO /usr/bin/openwrt-easy https://raw.githubusercontent.com/slobys/openwrt-official-one-click/main/bootstrap.sh && chmod +x /usr/bin/openwrt-easy; then
        openwrt-easy
        echo "[成功] 执行完毕"
        show_success
    else
        echo "[错误] 更新失败"
        return 1
    fi
}