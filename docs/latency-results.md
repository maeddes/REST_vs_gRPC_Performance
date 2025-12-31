# Latency results

**Timestamp:** 2025-12-31T01:35:33.4866909+01:00  
**Machine:** Windows (Docker Desktop)  
**Measured requests:** 100 (plus warmup 5)  
**Payload:** \{"value":123,"delay_ms":0}\

## Results (ms)

| Path | OK / Total | Failed | Avg | Median | p95 |
|---|---:|---:|---:|---:|---:|
| REST ($RestUrl) | 100 / 100 | 0 | 41.66 | 38.511 | 57.96 |
| gRPC-chain ($GrpcUrl) | 100 / 100 | 0 | 92.934 | 89.76 | 119.895 |

## HTTP status counts

- REST: 200:100
- gRPC-chain: 200:100

## How measured

Command:

\\\powershell
.\scripts\benchmark.ps1 -N 100 -Warmup 5 -Value 123 -DelayMs 0
\\\

