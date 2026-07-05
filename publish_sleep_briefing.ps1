# publish_sleep_briefing.ps1 v1.3
# v1.3: 加 Step 5 自动更新 briefings/index.html 和根 index.html
#      根因修复: 之前每天 push 新 HTML 但忘了更新 index.html，主页一直是旧的
# 关键修复: 所有路径用单引号(避免 PowerShell 把 \ 解释为转义字符)
# 调用: powershell -ExecutionPolicy Bypass -File "F:\hermes-home\sleep-briefing\publish_sleep_briefing.ps1" -Date 2026-07-02
# 用途: render HTML -> copy to briefings/ -> git commit + push -> 自动重写 index.html -> 再 commit+push
# 创建: 2026-07-01 19:24 (Bot3 fix v8.4 第六步 publish 脚本缺失)
# 更新: 2026-07-05 11:50 (Bot1 补 Step 5)
param([Parameter(Mandatory=$true)][string]$Date)

# 所有路径用单引号(关键!)
$BriefingDir = 'F:\hermes-home\sleep-briefing'
$RenderScript = 'F:\小豆包AI专用\重要\bots\bot3\tools\render_sleep_briefing.py'
$OutHtml = Join-Path $BriefingDir "$Date.html"
$BriefingsDir = Join-Path $BriefingDir 'briefings'
$OutHtmlBriefings = Join-Path $BriefingsDir "$Date.html"

Write-Host "publish: Date: $Date"
Write-Host "publish: Step 1/5: render HTML"
Write-Host "publish: script: $RenderScript"
Write-Host "publish: out: $OutHtml"

# Step 1: render HTML
$env:PYTHONIOENCODING = 'utf-8'
$renderOutput = python "$RenderScript" --date $Date --out "$OutHtml" 2>&1
if (Test-Path "$OutHtml") {
    $size = (Get-Item "$OutHtml").Length
    Write-Host "publish: render OK: $OutHtml ($size bytes)"
} else {
    Write-Host "publish: FAIL: HTML not generated at $OutHtml"
    Write-Host "publish: render output: $renderOutput"
    Write-Host "publish: step2-5 skip, feishu still sent"
    exit 0
}

# Step 2: copy to briefings/ (GitHub Pages 入口)
Write-Host "publish: Step 2/5: copy to briefings/"
Write-Host "publish: source: $OutHtml"
Write-Host "publish: dest: $OutHtmlBriefings"
if (-not (Test-Path $BriefingsDir)) {
    Write-Host "publish: creating dir $BriefingsDir"
    New-Item -ItemType Directory -Path $BriefingsDir -Force | Out-Null
}
Copy-Item "$OutHtml" "$OutHtmlBriefings" -Force
Write-Host "publish: copy exit code: $LASTEXITCODE"
if (Test-Path "$OutHtmlBriefings") {
    Write-Host "publish: copy OK: $OutHtmlBriefings"
} else {
    Write-Host "publish: FAIL: copy failed (file not found after copy)"
    Write-Host "publish: step3-5 skip, feishu still sent"
    exit 0
}

# Step 3: git commit (HTML file only)
Write-Host "publish: Step 3/5: git commit (HTML)"
Set-Location $BriefingDir
git add "$Date.html" 2>&1 | Out-Null
git add "briefings/$Date.html" 2>&1 | Out-Null
$status = git status --porcelain 2>&1
if ([string]::IsNullOrWhiteSpace($status)) {
    Write-Host "publish: no changes to commit (already published)"
} else {
    git -c user.email='bot3@openclaw.local' -c user.name='bot3' commit -m "briefing: $Date" 2>&1 | Out-Null
    Write-Host "publish: commit OK"
}

# Step 4: git push (with 3x retry to handle transient GitHub outages)
Write-Host "publish: Step 4/5: git push (max 3 retries)"
$pushOk = $false
for ($i = 1; $i -le 3; $i++) {
    git push origin main 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $pushOk = $true
        break
    } else {
        Write-Host "publish: push attempt $i failed, retrying in 30s..."
        Start-Sleep -Seconds 30
    }
}
if ($pushOk) {
    Write-Host "publish: push OK: $Date.html -> GitHub Pages"
    Write-Host "publish: public URL: https://dcrlovejs-spec.github.io/sleep-briefing/$Date.html"
} else {
    Write-Host "publish: FAIL: push failed 3x (GitHub outage or limit)"
    Write-Host "publish: step5 skip, feishu still sent (need manual recovery)"
    Write-Host "publish: TOMORROW MANUAL: powershell -ExecutionPolicy Bypass -File 'F:\hermes-home\sleep-briefing\publish_sleep_briefing.ps1' -Date $Date"
}

# Step 5: 自动重写 briefings/index.html 和根 index.html（按时间倒序列出全部入口）
# v1.3 新增: 修复主页看不到新简报的 bug
Write-Host "publish: Step 5/5: 自动重写 index.html 入口"

# 5a: 扫 briefings/ 下所有 YYYY-MM-DD.html，倒序
$briefingFiles = Get-ChildItem -Path $BriefingsDir -Filter '????-??-??.html' -File -ErrorAction SilentlyContinue
if ($briefingFiles) {
    $briefingFiles = $briefingFiles | Sort-Object Name -Descending
}

$briefingEntries = ''
foreach ($bf in $briefingFiles) {
    $bdate = $bf.BaseName
    $bsize = $bf.Length
    $briefingEntries += "  <div class=`"entry`"><a href=`"$bdate.html`">📅 $bdate</a><div class=`"meta`">$bsize bytes</div></div>" + [Environment]::NewLine
}

$briefingsIndexContent = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>探索者每日睡后简报</title>
<style>
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    max-width: 720px; margin: 32px auto; padding: 0 16px;
    background: #fafafa; color: #2c3e3c; line-height: 1.7; }
  h1 { color: #1890ff; }
  .entry { padding: 12px 16px; margin: 8px 0;
    background: #fff; border: 1px solid #e8e8e8; border-radius: 8px; }
  .entry a { color: #1890ff; text-decoration: none; font-weight: 500; }
  .entry a:hover { text-decoration: underline; }
  .entry .meta { color: #888; font-size: 13px; margin-top: 4px; }
  footer { color: #888; font-size: 12px; text-align: center; margin-top: 32px; }
</style>
</head>
<body>
<h1>🌙 探索者每日睡后简报</h1>
<p>由 Bot3 自动生成并归档于 GitHub Pages，永久免服务器费。</p>
$briefingEntries<footer>by 探索(Bot3) · GitHub Pages · 永久免费</footer>
</body>
</html>
"@

$BriefingsIndexHtml = Join-Path $BriefingsDir 'index.html'
[System.IO.File]::WriteAllText($BriefingsIndexHtml, $briefingsIndexContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "publish: briefings/index.html updated"

# 5b: 扫根目录下所有家报 jiabao-*.html
$jiabaoFiles = Get-ChildItem -Path $BriefingDir -Filter 'jiabao-*.html' -File -ErrorAction SilentlyContinue
if ($jiabaoFiles) {
    $jiabaoFiles = $jiabaoFiles | Sort-Object Name -Descending
}

$jiabaoEntries = ''
foreach ($jf in $jiabaoFiles) {
    $jname = $jf.Name
    $jbase = $jf.BaseName
    $jdate = $jbase -replace '^jiabao-', ''
    $jsize = $jf.Length
    $jiabaoEntries += "  <div class=`"entry`"><a href=`"$jname`">🏠 家报 $jdate</a><div class=`"meta`">$jsize bytes · 兰州分刊</div></div>" + [Environment]::NewLine
}

$rootIndexContent = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>探索者每日睡后简报</title>
<style>
  body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
    max-width: 720px; margin: 32px auto; padding: 0 16px;
    background: #fafafa; color: #2c3e3c; line-height: 1.7; }
  h1 { color: #1890ff; }
  h2 { color: #1890ff; margin-top: 32px; font-size: 18px; }
  .entry { padding: 12px 16px; margin: 8px 0;
    background: #fff; border: 1px solid #e8e8e8; border-radius: 8px; }
  .entry a { color: #1890ff; text-decoration: none; font-weight: 500; }
  .entry a:hover { text-decoration: underline; }
  .entry .meta { color: #888; font-size: 13px; margin-top: 4px; }
  footer { color: #888; font-size: 12px; text-align: center; margin-top: 32px; }
</style>
</head>
<body>
<h1>🌙 探索者每日睡后简报</h1>
<p>由 Bot3 自动生成并归档于 GitHub Pages，永久免服务器费。</p>
<h2>📰 每日简报</h2>
$briefingEntries
<h2>🏠 戴先生 & 戴太太 兰州分刊</h2>
$jiabaoEntries
<footer>by 探索(Bot3) · GitHub Pages · 永久免费</footer>
</body>
</html>
"@

$RootIndexHtml = Join-Path $BriefingDir 'index.html'
[System.IO.File]::WriteAllText($RootIndexHtml, $rootIndexContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "publish: index.html updated"

# 5c: 提交 + push index.html（Step 4 已经 push 过 HTML 了，index 是新增的变更）
git add "index.html" "briefings/index.html" 2>&1 | Out-Null
$status2 = git status --porcelain 2>&1
if (-not [string]::IsNullOrWhiteSpace($status2)) {
    git -c user.email='bot3@openclaw.local' -c user.name='bot3' commit -m "index: auto-update $Date" 2>&1 | Out-Null
    $pushOk2 = $false
    for ($i = 1; $i -le 3; $i++) {
        git push origin main 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $pushOk2 = $true
            break
        } else {
            Write-Host "publish: index push attempt $i failed, retrying in 30s..."
            Start-Sleep -Seconds 30
        }
    }
    if ($pushOk2) {
        Write-Host "publish: index.html auto-push OK"
    } else {
        Write-Host "publish: FAIL: index.html push failed 3x (manual recovery needed)"
    }
} else {
    Write-Host "publish: index.html no changes"
}

Write-Host "publish: === ALL DONE ==="
exit 0