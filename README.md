# OpenWrt APK Store

OpenWrt APK 应用商店 - 一键插件安装系统

适配 OpenWrt / ImmortalWrt / iStoreOS

## 功能特性

- 一键安装插件
- 自动识别系统架构（x86_64/aarch64/arm/mipsel/mips/riscv64）
- 自动获取 GitHub Releases 最新版本
- 自动安装依赖
- 自动安装中文包
- 自动修复依赖
- 自动重启 LuCI
- 插件卸载
- 插件更新（支持一键更新全部）
- 一键配置启动快捷键
- 自动更新脚本
- 支持管道安装（wget -O- | sh）

## 一键安装

```sh
wget -O- https://raw.githubusercontent.com/chengege666/OpenWrt-APK/main/install.sh | sh
```

## 短链接

```sh
bash <(curl -sL https://lj.1231818.xyz/apk)
```

## 手动安装

```sh
git clone https://github.com/chengege666/OpenWrt-APK.git
cd OpenWrt-APK
chmod +x store.sh
./store.sh
```

## 目录结构

```
OpenWrt-APK/
├── store.sh              # 主安装器（交互式菜单）
├── install.sh            # 一键安装脚本
├── apk-opts.sh           # APK 安装参数配置（--allow-untrusted 开关）
├── core/
│   ├── network.sh        # 网络工具模块（下载/缓存/网络检测）
│   ├── github.sh         # GitHub Releases API 模块
│   ├── install.sh        # 安装/卸载/重启模块
│   └── ui.sh             # 用户界面模块
└── plugins/
    ├── openclash.sh          # OpenClash
    ├── passwall.sh           # PassWall
    ├── passwall2.sh          # PassWall2
    ├── mosdns.sh             # MosDNS
    ├── docker.sh             # Docker
    ├── smartdns.sh           # SmartDNS
    ├── lucky.sh              # Lucky
    ├── daed.sh               # Daed
    ├── nikki.sh              # Nikki
    ├── taskplan.sh           # TaskPlan
    ├── istore.sh             # iStore
    ├── luci-app-diskman.sh   # DiskMan
    ├── luci-app-wechatpush.sh# WeChatPush
    ├── luci-theme-argon.sh   # Argon 主题
    └── luci-theme-aurora.sh  # Aurora 主题
```

## APK luci安装参数配置

通过独立脚本 `apk-opts.sh` 管理 `--allow-untrusted` 开关，持久化配置保存在 `/etc/apk-store.conf`。

### 一键安装

```sh
bash <(curl -sL https://lj.1231818.xyz/kg)
```

或

```sh
wget -qO- https://raw.githubusercontent.com/chengege666/OpenWrt-APK/main/apk-opts.sh | sh
```

> 注：OpenWrt 默认无 bash，需先安装 `opkg install bash`，或使用下方 wget 方式

### 命令行使用

```sh
# 交互式菜单
sh apk-opts.sh

# 快速开关
sh apk-opts.sh on       # 开启（跳过签名验证，默认）
sh apk-opts.sh off      # 关闭（需要有效签名）

# 查看当前状态
sh apk-opts.sh status
```

### 脚本内调用

```sh
. /root/apk-store/apk-opts.sh
apk_opts_init
apk add $(apk_get_opts) /path/to/package.apk
```

## 支持的插件

| 插件 | 说明 |
|------|------|
| OpenClash | 透明代理工具 |
| PassWall | 科学上网 |
| PassWall2 | 科学上网 |
| Nikki | 科学上网 |
| Daed | 科学上网 |
| MosDNS | DNS 分流解析 |
| AdGuardHome | 广告过滤 |
| Docker | 容器管理 |
| SmartDNS | DNS 本地加速 |
| Lucky | 综合网络工具（DDNS/Stun/Webhook） |
| TaskPlan | 定时任务管理 |
| iStore | 软件商店 |
| DiskMan | 磁盘管理 |
| WeChatPush | 微信消息推送 |
| Argon 主题 | 后台主题美化 |
| Aurora 主题 | 后台主题美化 |

## 使用方式

运行 `store.sh` 后显示主菜单：

```
================================
 OpenWrt APK Store
================================

1.   安装插件
2.   卸载插件
3.   更新插件
4.   一键配置启动快捷键
00.  卸载脚本
000. 更新脚本
0.   退出
```

选择 **安装插件** 后进入子菜单：

```
================================
 安装插件
================================

  1.  OpenClash (科学上网)       6.  Argon 主题 (后台主题)
  2.  MosDNS (DNS解析)           7.  TaskPlan (定时任务)
  3.  Docker (容器管理)          8.  PassWall2 (科学上网)
  4.  Aurora 主题 (后台主题)     9.  SmartDNS (DNS加速)
  5.  Lucky (端口转发)           10. Daed (科学上网)
  11. iStore (软件商店)          12. DiskMan (磁盘管理)
  13. WeChatPush (消息推送)      14. PassWall (科学上网)
  15. Nikki (科学上网)
  0.  返回上级
```

## 添加新插件

在 `plugins/` 目录下创建新的插件脚本，参考现有插件模板：

```sh
#!/bin/sh
# plugins/your_plugin.sh

install_your_plugin() {
    local owner="owner"
    local repo="repo"
    local plugin_name="plugin"

    # 获取最新 Release
    local release_json
    release_json=$(get_latest_release "$owner" "$repo") || return 1

    local tag
    tag=$(get_release_tag "$release_json")
    echo "[版本] $tag"

    # 获取下载链接
    local all_urls
    all_urls=$(get_download_urls "$release_json" "$owner" "$repo" "$tag")

    # 过滤并下载
    local url
    url=$(echo "$all_urls" | grep "xxx.apk" | head -1)
    # ... 下载、安装逻辑
}

uninstall_your_plugin() {
    uninstall_plugin "luci-app-xxx"
}

update_your_plugin() {
    cleanup_old_cache
    install_your_plugin
}
```

然后在 `store.sh` 中引入并添加到菜单。

### 插件模板说明

- `get_latest_release owner/repo` - 获取最新 Release JSON
- `get_release_tag json` - 提取版本号
- `get_download_urls json owner repo tag` - 获取所有下载链接（含 HTML 回退机制）
- `download_file url output_path` - 下载文件（含镜像加速、重试）
- `fix_dependencies` - 修复依赖
- `restart_luci` - 重启 LuCI 界面

## 技术栈

- Shell (兼容 BusyBox ash)
- wget
- GitHub API / SourceForge
- APK / OPKG 包管理

## 许可证

MIT
