$ErrorActionPreference = 'Stop'
$serviceRoot = $PSScriptRoot
$projectRoot = 'D:\NewProof\NewsProof-main\NewsProof-main'
$backendRoot = Join-Path $projectRoot 'backend'
$python = Join-Path $backendRoot '.venv\Scripts\python.exe'
$projectEnv = Join-Path $projectRoot '.env'
$envValues = @{}

if (Test-Path $projectEnv) {
    Get-Content $projectEnv | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $envValues[$matches[1]] = $matches[2].Trim() }
    }
}
foreach ($name in $envValues.Keys) { Set-Item -Path "Env:$name" -Value $envValues[$name] }

$env:DATABASE_URL = $env:DATABASE_URL -replace '@postgres:', '@127.0.0.1:'
$env:REDIS_URL = 'redis://127.0.0.1:6379/0'
$env:UPLOAD_DIR = Join-Path $serviceRoot 'uploads'
$env:BACKEND_CORS_ORIGINS_RAW = 'http://localhost:3000,http://127.0.0.1:3000,http://localhost:3001,http://127.0.0.1:3001'
$env:PATH = @(
    (Join-Path $serviceRoot 'tesseract')
    (Join-Path $serviceRoot 'ffmpeg\ffmpeg-9.0.2-essentials_build\bin')
    (Join-Path $serviceRoot 'postgresql\pgsql\bin')
    (Join-Path $serviceRoot 'redis\Redis-8.10.2-Windows-x64-msys2-with-Service')
    $env:PATH
) -join ';'

New-Item -ItemType Directory -Force -Path $env:UPLOAD_DIR | Out-Null
if (!(Test-Path $python)) { throw 'NewsProof backend Python environment was not found.' }
Push-Location $backendRoot
try {
    & $python -m alembic upgrade head
    if ($LASTEXITCODE -ne 0) { throw 'Database migrations failed.' }
    & $python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
    if ($LASTEXITCODE -ne 0) { throw 'FastAPI exited with an error.' }
} finally {
    Pop-Location
}

