$ErrorActionPreference = 'Stop'
$serviceRoot = $PSScriptRoot
$projectRoot = 'D:\NewProof\NewsProof-main\NewsProof-main'
$pgBin = Join-Path $serviceRoot 'postgresql\pgsql\bin'
$pgData = Join-Path $serviceRoot 'postgres-data'
$redisFolder = Join-Path $serviceRoot 'redis\Redis-8.10.2-Windows-x64-msys2-with-Service'
$redisData = Join-Path $serviceRoot 'redis-data'
$redisConfig = Join-Path $serviceRoot 'redis-local.conf'

Start-Transcript -Path (Join-Path $serviceRoot 'install-services.log') -Append | Out-Null

if (!(Test-Path (Join-Path $pgData 'PG_VERSION'))) { throw 'PostgreSQL data directory is not initialized.' }
New-Item -ItemType Directory -Force -Path $redisData | Out-Null
@(
    'bind 127.0.0.1'
    'protected-mode yes'
    'port 6379'
    "dir $($redisData.Replace('\','/'))"
    "logfile $($redisData.Replace('\','/'))/redis.log"
    'appendonly yes'
) | Set-Content -LiteralPath $redisConfig -Encoding ascii

$pgService = Get-Service -Name 'NewsProofPostgreSQL' -ErrorAction SilentlyContinue
if (!$pgService) {
    & (Join-Path $pgBin 'pg_ctl.exe') register -N 'NewsProofPostgreSQL' -D $pgData -S demand -o '-h 127.0.0.1 -p 5432'
    if ($LASTEXITCODE -ne 0) { throw 'Could not register PostgreSQL as a Windows service.' }
}
$redisService = Get-Service -Name 'NewsProofRedis' -ErrorAction SilentlyContinue
if (!$redisService) {
    & (Join-Path $redisFolder 'RedisService.exe') install --service-name NewsProofRedis --display-name 'NewsProof Redis' --description 'Local Redis service for NewsProof' --start-mode manual -c $redisConfig --dir $redisData --port 6379
    if ($LASTEXITCODE -ne 0) { throw 'Could not register Redis as a Windows service.' }
}

Start-Service -Name 'NewsProofPostgreSQL'
Start-Service -Name 'NewsProofRedis'

$config = @{}
$projectEnv = Join-Path $projectRoot '.env'
if (Test-Path $projectEnv) {
    Get-Content $projectEnv | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $config[$matches[1]] = $matches[2].Trim() }
    }
}
$dbUser = if ($config['POSTGRES_USER']) { $config['POSTGRES_USER'] } else { 'postgres' }
$dbName = if ($config['POSTGRES_DB']) { $config['POSTGRES_DB'] } else { 'newsproof' }
$dbPassword = if ($config['POSTGRES_PASSWORD']) { $config['POSTGRES_PASSWORD'] } else { 'postgres' }
if ($dbName -notmatch '^[A-Za-z0-9_]+$') { throw 'POSTGRES_DB must contain only letters, digits, and underscores.' }

$env:PGPASSWORD = $dbPassword
try {
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        $result = & (Join-Path $pgBin 'psql.exe') -h 127.0.0.1 -p 5432 -U $dbUser -d postgres -tAc 'SELECT 1' 2>$null
        if ($LASTEXITCODE -eq 0 -and $result.Trim() -eq '1') { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (!$ready) { throw 'PostgreSQL service did not become ready.' }
    $exists = & (Join-Path $pgBin 'psql.exe') -h 127.0.0.1 -p 5432 -U $dbUser -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$dbName'"
    if (($exists | Out-String).Trim() -ne '1') {
        & (Join-Path $pgBin 'createdb.exe') -h 127.0.0.1 -p 5432 -U $dbUser $dbName
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the NewsProof database.' }
    }
} finally {
    Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
}

$redisPing = & (Join-Path $redisFolder 'redis-cli.exe') -h 127.0.0.1 -p 6379 ping
if ($redisPing -ne 'PONG') { throw 'Redis service did not respond to PING.' }

Write-Output "PostgreSQL ready at 127.0.0.1:5432 ($dbName)."
Write-Output 'Redis ready at 127.0.0.1:6379.'
Stop-Transcript | Out-Null
