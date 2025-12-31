param(
  [int]$N = 100,
  [int]$Warmup = 5,
  [int]$Value = 123,
  [int]$DelayMs = 0,

  [string]$RestUrl = "http://localhost:8000/process",
  [string]$GrpcUrl = "http://localhost:8002/process",

  # optional: Ergebnisse als Markdown speichern
  [string]$OutFile = "docs/latency-results.md"
)

function Invoke-PostOnce([string]$Url, [string]$BodyJson) {
  $sw = New-Object System.Diagnostics.Stopwatch
  $sw.Start()

  $ok = $false
  $status = $null

  try {
    $resp = Invoke-WebRequest $Url -Method Post -ContentType "application/json" -Body $BodyJson -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    $ok = $true
    $status = [int]$resp.StatusCode
  }
  catch {
    # Bei Windows PowerShell kommen Statuscodes teils nur über Exception.Response
    try {
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $status = [int]$_.Exception.Response.StatusCode
      }
    } catch {}
  }
  finally {
    $sw.Stop()
  }

  return [PSCustomObject]@{
    ms     = $sw.Elapsed.TotalMilliseconds
    ok     = $ok
    status = $status
  }
}

function Get-Median([double[]]$sorted) {
  $count = $sorted.Count
  if ($count -eq 0) { return [double]::NaN }
  if (($count % 2) -eq 1) {
    return $sorted[[int]($count/2)]
  } else {
    $a = $sorted[($count/2)-1]
    $b = $sorted[($count/2)]
    return ($a + $b) / 2
  }
}

function Get-Quantile([double[]]$sorted, [double]$q) {
  $count = $sorted.Count
  if ($count -eq 0) { return [double]::NaN }
  $idx = [int]([math]::Ceiling($count * $q)) - 1
  if ($idx -lt 0) { $idx = 0 }
  if ($idx -ge $count) { $idx = $count - 1 }
  return $sorted[$idx]
}

function Measure-PostLatency([string]$Url, [int]$N, [int]$Warmup, [int]$Value, [int]$DelayMs) {
  $body = @{ value = $Value; delay_ms = $DelayMs } | ConvertTo-Json

  # Warmup (nicht gemessen)
  1..$Warmup | ForEach-Object { Invoke-PostOnce -Url $Url -BodyJson $body | Out-Null }

  $results = @()
  1..$N | ForEach-Object {
    $results += Invoke-PostOnce -Url $Url -BodyJson $body
  }

  $okTimes = $results | Where-Object { $_.ok } | Select-Object -ExpandProperty ms
  $failCount = ($results | Where-Object { -not $_.ok }).Count
  $statusCounts = $results | Group-Object status | ForEach-Object { "{0}:{1}" -f $_.Name, $_.Count } | Sort-Object

  $sorted = @($okTimes | Sort-Object)
  $avg = if ($sorted.Count -gt 0) { ( $sorted | Measure-Object -Average ).Average } else { [double]::NaN }
  $median = Get-Median -sorted $sorted
  $p95 = Get-Quantile -sorted $sorted -q 0.95

  return [PSCustomObject]@{
    url = $Url
    n_total = $N
    warmup = $Warmup
    ok = $sorted.Count
    failed = $failCount
    status_counts = ($statusCounts -join ", ")
    avg_ms = [math]::Round($avg, 3)
    median_ms = [math]::Round($median, 3)
    p95_ms = [math]::Round($p95, 3)
  }
}

# ---------- Run ----------
$startTime = Get-Date
"=== Benchmark setup ==="
"Time: $($startTime.ToString('o'))"
"Requests (measured): $N   Warmup: $Warmup"
"Payload: value=$Value delay_ms=$DelayMs"
"REST: $RestUrl"
"gRPC-chain: $GrpcUrl"
""

$rest = Measure-PostLatency -Url $RestUrl -N $N -Warmup $Warmup -Value $Value -DelayMs $DelayMs
$grpc = Measure-PostLatency -Url $GrpcUrl -N $N -Warmup $Warmup -Value $Value -DelayMs $DelayMs

"=== Results (ms, only successful requests) ==="
$rest
$grpc

# Optional: write docs/latency-results.md
$md = @"
# Latency results

**Timestamp:** $($startTime.ToString('o'))  
**Machine:** Windows (Docker Desktop)  
**Measured requests:** $N (plus warmup $Warmup)  
**Payload:** `{"value":$Value,"delay_ms":$DelayMs}`

## Results (ms)

| Path | OK / Total | Failed | Avg | Median | p95 |
|---|---:|---:|---:|---:|---:|
| REST (`$RestUrl`) | $($rest.ok) / $($rest.n_total) | $($rest.failed) | $($rest.avg_ms) | $($rest.median_ms) | $($rest.p95_ms) |
| gRPC-chain (`$GrpcUrl`) | $($grpc.ok) / $($grpc.n_total) | $($grpc.failed) | $($grpc.avg_ms) | $($grpc.median_ms) | $($grpc.p95_ms) |

## HTTP status counts

- REST: $($rest.status_counts)
- gRPC-chain: $($grpc.status_counts)

## How measured

Command:

```powershell
.\scripts\benchmark.ps1 -N $N -Warmup $Warmup -Value $Value -DelayMs $DelayMs
```

"@

# ensure docs folder exists
$docsDir = Split-Path $OutFile -Parent
if ($docsDir -and -not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir | Out-Null }

Set-Content -Path $OutFile -Value $md -Encoding UTF8
"Saved results to: $OutFile"