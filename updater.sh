#!/usr/bin/bash

set -e

# Server酱推送函数
sc_send() {
    if [ $# -lt 2 ]; then
        echo "错误: 参数不足"
        echo "用法: sc_send <sendkey> <title> [desp] [options...]"
        return 1
    fi

    local sendkey="$1"
    local title="$2"
    local desp=""
    local tags=""
    local short=""
    local noip=""
    local channel=""
    local openid=""

    shift 2

    if [ $# -gt 0 ]; then
        if [[ ! "$1" =~ ^-- ]]; then
            desp="$1"
            shift
        fi
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            --tags)
                tags="$2"
                shift 2
                ;;
            --short)
                short="$2"
                shift 2
                ;;
            --noip)
                noip="$2"
                shift 2
                ;;
            --channel)
                channel="$2"
                shift 2
                ;;
            --openid)
                openid="$2"
                shift 2
                ;;
            *)
                echo "警告: 未知选项 $1"
                shift
                ;;
        esac
    done

    local url
    if [[ "$sendkey" =~ ^sctp ]]; then
        url="https://${sendkey}.push.ft07.com/send"
    else
        url="https://sctapi.ftqq.com/${sendkey}.send"
    fi

    local json_data="{\"title\":\"$title\""

    if [ -n "$desp" ]; then
        json_data="$json_data,\"desp\":\"$desp\""
    fi

    if [ -n "$tags" ]; then
        json_data="$json_data,\"tags\":\"$tags\""
    fi

    if [ -n "$short" ]; then
        json_data="$json_data,\"short\":\"$short\""
    fi

    if [ -n "$noip" ]; then
        json_data="$json_data,\"noip\":$noip"
    fi

    if [ -n "$channel" ]; then
        json_data="$json_data,\"channel\":\"$channel\""
    fi

    if [ -n "$openid" ]; then
        json_data="$json_data,\"openid\":\"$openid\""
    fi

    json_data="$json_data}"

    echo "发送JSON数据: $json_data" >&2

    local response
    response=$(curl -s -X POST \
            -H "Content-Type: application/json;charset=utf-8" \
            -d "$json_data" \
        "$url")

    echo "$response"

    local code=$(echo "$response" | grep -o '"code":[0-9]*' | cut -d: -f2 2>/dev/null || echo "1")
    if [[ "$code" == "0" ]]; then
        return 0
    else
        return 1
    fi
}

# 修改：使用文件来传递结果，而不是全局数组
RECORD_FILE=$(mktemp)
SUCCESS_FILE=$(mktemp)
FAILED_FILE=$(mktemp)

cleanup() {
    rm -f "$RECORD_FILE" "$SUCCESS_FILE" "$FAILED_FILE"
}

trap cleanup EXIT

_update() {
    local name=$1
    local record_file="$2"
    local success_file="$3"
    local failed_file="$4"

    echo "正在更新包: $name"

    # 克隆仓库
    if ! git clone "ssh://aur@aur.archlinux.org/$name.git" 2>/dev/null; then
        echo "错误：无法克隆仓库 $name" >&2
        echo "$name - 无法克隆仓库" >> "$failed_file"
        return 1
    fi

    cd "$name" || {
        echo "错误：无法进入目录 $name" >&2
        echo "$name - 无法进入目录" >> "$failed_file"
        return 1
    }

    # 获取当前版本
    if ! grep -q '^pkgver=' PKGBUILD; then
        echo "错误：PKGBUILD 中没有 pkgver 字段" >&2
        echo "$name - PKGBUILD格式错误" >> "$failed_file"
        cd ..
        rm -rf "$name"
        return 1
    fi

    local old_version=$(grep -oP '(?<=^pkgver=).*' PKGBUILD)
    echo "当前版本: $old_version"

    # 尝试获取新版本
    local new_version=""
    source PKGBUILD
    new_version=$(version)

    if [[ -z "$new_version" ]]; then
        echo "错误：无法获取 $name 的新版本" >&2
        echo "$name - 无法获取新版本 (当前: $old_version)" >> "$failed_file"
        cd ..
        rm -rf "$name"
        return 1
    fi

    echo "最新版本: $new_version"

    if [[ "$new_version" == "$old_version" ]]; then
        echo "包 $name 无需更新"
        echo "$name - 无需更新 (保持 $old_version)" >> "$success_file"
        cd ..
        rm -rf "$name"
        return 0
    else
        echo "正在更新 $name 到版本 $new_version"

        # 更新版本号
        sed -i "s/^pkgver=.*/pkgver=$new_version/" PKGBUILD

        # 重置pkgrel
        if grep -q '^pkgrel=' PKGBUILD; then
            sed -i "s/^pkgrel=.*/pkgrel=1/" PKGBUILD
        fi

        # 更新校验和
        if ! updpkgsums 2>/dev/null; then
            echo "警告：更新校验和失败，继续执行..."
        fi

        # 生成.SRCINFO
        if ! makepkg --printsrcinfo 2>/dev/null > .SRCINFO; then
            echo "错误：生成.SRCINFO失败" >&2
            echo "$name - 生成.SRCINFO失败 ($old_version → $new_version)" >> "$failed_file"
            cd ..
            rm -rf "$name"
            return 1
        fi

        # 提交更改
        if ! git add PKGBUILD .SRCINFO 2>/dev/null; then
            echo "错误：添加文件到git失败" >&2
            echo "$name - git添加文件失败 ($old_version → $new_version)" >> "$failed_file"
            cd ..
            rm -rf "$name"
            return 1
        fi

        if ! git commit -m "Upgrade to $new_version" 2>/dev/null; then
            echo "错误：提交更改失败" >&2
            echo "$name - git提交失败 ($old_version → $new_version)" >> "$failed_file"
            cd ..
            rm -rf "$name"
            return 1
        fi

        # 推送更改
        if git push 2>/dev/null; then
            echo "成功更新 $name 到版本 $new_version"
            echo "$name - $old_version → $new_version" >> "$success_file"
            cd ..
            rm -rf "$name"
            return 0
        else
            echo "错误：推送 $name 更新失败" >&2
            echo "$name - 推送失败 ($old_version → $new_version)" >> "$failed_file"
            cd ..
            rm -rf "$name"
            return 1
        fi
    fi
}

update() {
    local temp_dir
    temp_dir=$(mktemp -d /tmp/aur_update_XXXXXX)

    local cwd
    cwd=$(pwd)

    echo "工作目录: $temp_dir"
    cd "$temp_dir"

    local packages=("buck2-bin")

    for package in "${packages[@]}"; do
        echo "========================================"
        echo "尝试更新: $package"
        if _update "$package" "$RECORD_FILE" "$SUCCESS_FILE" "$FAILED_FILE"; then
            echo "✅ 更新完成: $package"
        else
            echo "❌ 更新失败: $package" >&2
        fi
        echo ""
    done

    cd "$cwd"
    rm -rf "$temp_dir"

    echo "所有更新任务完成"
}

read_array_from_file() {
    local file="$1"
    if [[ -f "$file" ]] && [[ -s "$file" ]]; then
        cat "$file"
    else
        echo ""
    fi
}

format_message() {
    local success_content=$(read_array_from_file "$SUCCESS_FILE")
    local failed_content=$(read_array_from_file "$FAILED_FILE")

    # 统计成功和失败的数量
    local success_count=0
    local fail_count=0

    if [[ -n "$success_content" ]]; then
        success_count=$(echo "$success_content" | wc -l)
    fi

    if [[ -n "$failed_content" ]]; then
        fail_count=$(echo "$failed_content" | wc -l)
    fi

    local total_count=$((success_count + fail_count))

    local msg="## AUR包更新结果\\n\\n"

    msg+="### 📊 统计信息\\n"
    msg+="- **总计包数**: $total_count\\n"
    msg+="- **✅ 成功**: $success_count\\n"
    msg+="- **❌ 失败**: $fail_count\\n\\n"

    # 成功更新的包
    if [ $success_count -gt 0 ]; then
        msg+="### ✅ 成功更新的包\\n"
        local i=1
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                msg+="$i. $line\\n"
                ((i++))
            fi
        done <<< "$success_content"
        msg+="\\n"
    else
        msg+="### ℹ️ 没有成功更新的包\\n\\n"
    fi

    # 失败的包
    if [ $fail_count -gt 0 ]; then
        msg+="### ❌ 更新失败的包\\n"
        local i=1
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                msg+="$i. $line\\n"
                ((i++))
            fi
        done <<< "$failed_content"
        msg+="\\n"
    else
        msg+="### ✅ 没有失败的包\\n\\n"
    fi

    # 时间戳
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    msg+="---\\n*更新完成时间: $timestamp*"

    echo "$msg"
}

escape_json() {
    local str="$1"
    # 转义反斜杠、双引号和换行符
    str=$(echo "$str" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
    echo "$str"
}

main() {
    # 清空临时文件
    > "$SUCCESS_FILE"
    > "$FAILED_FILE"
    > "$RECORD_FILE"

    # 执行更新并捕获输出
    echo "开始更新AUR包..."
    update 2>&1 | tee /tmp/aur_update_full.log

    # 构建消息
    local msg
    msg=$(format_message)

    echo "=== 原始消息内容 ==="
    echo -e "$msg" | sed 's/\\n/\n/g'
    echo "=================="

    # 转义消息内容（双重转义：一次用于JSON，一次用于sed）
    local escaped_msg=$(echo "$msg" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

    echo "=== 转义后的JSON消息 ==="
    echo "{\"title\":\"AUR包更新结果\",\"desp\":\"$escaped_msg\"}"
    echo "=================="

    # 发送通知
    echo "发送推送通知..."
    if sc_send "$PUSH_KEY" "AUR包更新结果" "$msg"; then
        echo "✅ 推送发送成功"
    else
        echo "❌ 推送发送失败"
        return 1
    fi
}

# 确保 PUSH_KEY 环境变量已设置
if [ -z "$PUSH_KEY" ]; then
    echo "错误: PUSH_KEY 环境变量未设置"
    exit 1
fi
