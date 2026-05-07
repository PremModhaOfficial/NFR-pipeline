# Evolution Log — python-connection-pool-tuning

## 1.0.0 — v0.5.0-phase-b — 2026-04-28
Initial authorship. Sizing heuristic ceil(throughput × p99_latency); per-library mapping (aiohttp.TCPConnector limit + limit_per_host + enable_cleanup_closed; asyncpg.create_pool min/max/max_inactive_connection_lifetime/command_timeout; redis.ConnectionPool max_connections + health_check_interval; httpx.Limits; aiokafka max_in_flight); PoolExhaustedError as the typed surface; pool-depth observable gauge; idle-lifetime recycle for cloud DB silent-kill; fork-unsafe module-level pool warning; asyncio.Semaphore for shared global cap; DNS TTL trade-off.
