# Send-Utf8Request.ps1
# Windows PowerShell 下的 UTF-8 安全 HTTP 封装。
#
# 设计动机：PowerShell 5.1（Windows 默认）的 Invoke-RestMethod 在把字符串
# 序列化为 HTTP body 字节流时，使用系统默认编码（Windows-1252 / GBK）而非 UTF-8。
# 中文等非-ASCII 字符会被不可逆替换成 0x3F（'?'），数据在网络传输前已丢失。
#
# 本函数统一处理两条路径：
#   * PowerShell 7+（pwsh）：原生已用 UTF-8，直接发字符串即可。
#   * PowerShell 5.1：必须把 body 显式转为 UTF-8 字节数组，并以字节方式提交。
#
# 用法（点源后调用）：
#   . .\Send-Utf8Request.ps1
#   $r = Send-Utf8RestMethod -Uri "http://127.0.0.1:8420/capture" -Body @{
#       session_key = "s1"; user_content = "我叫张明"; assistant_content = "你好！"
#   }
#
# 自检：
#   . .\Send-Utf8Request.ps1
#   Test-UriUtf8RoundTrip -Uri "http://127.0.0.1:8420/__echo"   # 需先启动网关

<#
.SYNOPSIS
  发送一个 UTF-8 安全的 JSON POST 请求，兼容 PowerShell 5.1 与 7+。

.DESCRIPTION
  在 PowerShell 5.1 下强制将 body 转为 UTF-8 字节数组后提交，
  从源头消除 Invoke-RestMethod 的中文乱码（0x3F 替换）问题。
  PowerShell 7+ 原生 UTF-8，直接提交字符串。
#>
function Send-Utf8RestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [object] $Body,
        [string] $Method = "POST",
        [int]    $TimeoutSec = 30
    )

    # 1) 序列化为 JSON。5.1 下 ConvertTo-Json 默认会转义非-ASCII 为 \uXXXX，
    #    这里用 -Compress 并交给下方编码步骤；真正的关键是字节编码而非转义。
    if ($Body -is [string]) {
        $json = $Body
    } else {
        $json = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    $headers = @{
        "Content-Type" = "application/json; charset=utf-8"
        "Accept"       = "application/json; charset=utf-8"
    }

    # 2) 按版本分流：5.1 走字节数组，7+ 走原生
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return Invoke-RestMethod -Uri $Uri -Method $Method `
            -Headers $headers -Body $json -TimeoutSec $TimeoutSec
    }

    # --- PowerShell 5.1：关键修复 ---
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Uri $Uri -Method $Method `
        -Headers $headers -Body $bytes -TimeoutSec $TimeoutSec
}

<#
.SYNOPSIS
  端到端 UTF-8 往返自检。向一个「原样回显 body 文本」的端点发非-ASCII 样例，
  校验回显是否与原文逐字符一致。对应技能的验证门槛（V(x,a) 预言机）。

.PARAMETER Uri
  回显端点（如 validation/mock-gateway.mjs 暴露的 /__echo）。
#>
function Test-UriUtf8RoundTrip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [string] $Sample = "我叫张明，技术栈：TypeScript + React + Node.js ✓ 🚀"
    )

    $resp = Send-Utf8RestMethod -Uri $Uri -Body @{ text = $Sample }
    $received = $resp.text
    if ($null -eq $received) { $received = ($resp | ConvertTo-Json -Compress) }

    Write-Host "sent:     $Sample"
    Write-Host "received: $received"
    if ($received -eq $Sample) {
        Write-Host "result:   PASS (UTF-8 preserved)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "result:   FAIL (encoding broken — likely Invoke-RestMethod 非 UTF-8)" -ForegroundColor Red
        return $false
    }
}

# 文件被 dot-source 时，不自动执行；直接运行脚本则做一次自检
if ($MyInvocation.InvocationName -ne ".") {
    $target = if ($args.Count -ge 1) { $args[0] } else { "http://127.0.0.1:8420/__echo" }
    Test-UriUtf8RoundTrip -Uri $target
}
