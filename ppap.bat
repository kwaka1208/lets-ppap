@echo off
chcp 65001 > nul
setlocal

:: ==========================================
:: 設定項目
:: ==========================================
:: 7-Zipの実行ファイルパス（標準インストール先）
set "SEVEN_ZIP=C:\Program Files\7-Zip\7z.exe"

:: 自動生成するパスワードの文字数
set "PASS_LENGTH=12"
:: ==========================================

:: 7-Zipの存在確認
if not exist "%SEVEN_ZIP%" (
    echo [エラー] 7-Zipが見つかりません: "%SEVEN_ZIP%"
    echo 7-Zipをインストールするか、バッチファイル内の SEVEN_ZIP のパスを修正してください。
    pause
    exit /b 1
)

:: 対象フォルダ（このバッチファイルが置かれているフォルダ）
set "TARGET_DIR=%~dp0"

echo.
echo 処理を開始します...
echo 対象フォルダ: %TARGET_DIR%
echo.

:: PowerShellを呼び出してパスワード生成・ZIP圧縮・CSV出力を一括実行
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$targetDir = $env:TARGET_DIR;" ^
  "$sevenZip = $env:SEVEN_ZIP;" ^
  "$passLen = [int]$env:PASS_LENGTH;" ^
  "$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss';" ^
  "$csvPath = Join-Path $targetDir ('password_list_' + $timestamp + '.csv');" ^
  "$chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';" ^
  "$results = @();" ^
  "$folders = Get-ChildItem -LiteralPath $targetDir -Directory;" ^
  "if ($folders.Count -eq 0) { Write-Host '処理対象のサブフォルダが見つかりませんでした。'; exit };" ^
  "foreach ($f in $folders) {" ^
  "  if ((Get-ChildItem -LiteralPath $f.FullName -Force).Count -eq 0) {" ^
  "    Write-Host ('[スキップ] 中身が空のため除外: ' + $f.Name);" ^
  "    continue;" ^
  "  }" ^
  "  $pass = -join (1..$passLen | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] });" ^
  "  $zipName = $f.Name + '.zip';" ^
  "  $zipPath = Join-Path $targetDir $zipName;" ^
  "  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force };" ^
  "  $srcPath = Join-Path $f.FullName '*';" ^
  "  & $sevenZip a -tzip -p$pass -mem=ZipCrypto $zipPath $srcPath | Out-Null;" ^
  "  if ($LASTEXITCODE -eq 0) {" ^
  "    Write-Host ('[完了] ' + $zipName);" ^
  "    $results += [PSCustomObject]@{ 'ファイル名' = $zipName; 'パスワード' = $pass };" ^
  "  } else {" ^
  "    Write-Host ('[失敗] ' + $zipName);" ^
  "  }" ^
  "};" ^
  "if ($results.Count -gt 0) {" ^
  "  $results | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8;" ^
  "  Write-Host '';" ^
  "  Write-Host ('CSVファイルを出力しました: ' + $csvPath);" ^
  "}"

echo.
echo すべての処理が終了しました。
pause
