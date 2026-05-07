---
name: go-testcontainers-setup
description: >
  Use this when writing integration tests that need a real backing service —
  PostgreSQL, NATS JetStream, Redis, Dragonfly, MinIO, LocalStack, Kafka, or
  RabbitMQ — set up via testcontainers-go. Covers shared TestMain, sync.Once
  container reuse, schema-per-tenant isolation, and reproducible-isolated test
  infrastructure. Triggers: testcontainers, TestMain, sync.Once, integration
  test, container reuse, postgres container, nats container, redis container,
  dragonfly, minio, localstack, kafka, rabbitmq, docker.
---



# Testcontainers Setup

Standardizes integration test infrastructure across all microservices.
Every service that talks to PostgreSQL, NATS, or Redis uses these
patterns for reproducible, isolated integration tests.

## When to Activate
- When writing integration tests that need a real database
- When testing NATS JetStream pub/sub or request-reply
- When verifying schema-per-tenant isolation
- When setting up TestMain for shared containers
- Used by: test-generator, code-generator, simulated-qa-engineer

## PostgreSQL Container

```go
func setupPostgres(t *testing.T) *pgxpool.Pool {
    t.Helper()
    ctx := context.Background()
    container, err := postgres.Run(ctx, "duckdb/duckdb:latest",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"), postgres.WithPassword("test"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
    )
    if err != nil { t.Fatalf("starting postgres: %v", err) }
    t.Cleanup(func() { _ = container.Terminate(ctx) })

    connStr, _ := container.ConnectionString(ctx, "sslmode=disable")
    pool, err := pgxpool.New(ctx, connStr)
    if err != nil { t.Fatalf("connecting: %v", err) }
    t.Cleanup(pool.Close)
    runMigrations(t, pool) // golang-migrate or embedded SQL
    return pool
}
```

## Embedded NATS JetStream

Use in-process NATS server for fast, no-Docker messaging tests.

```go
func setupNATS(t *testing.T) (*nats.Conn, jetstream.JetStream) {
    t.Helper()
    srv, err := server.NewServer(&server.Options{
        Port: -1, JetStream: true, StoreDir: t.TempDir(),
    })
    if err != nil { t.Fatalf("creating nats server: %v", err) }
    srv.Start()
    t.Cleanup(srv.Shutdown)
    if !srv.ReadyForConnections(5 * time.Second) { t.Fatal("nats not ready") }

    nc, err := nats.Connect(srv.ClientURL())
    if err != nil { t.Fatalf("connecting: %v", err) }
    t.Cleanup(nc.Close)
    js, err := jetstream.New(nc)
    if err != nil { t.Fatalf("creating jetstream: %v", err) }
    return nc, js
}
```

## Redis Container

```go
func setupRedis(t *testing.T) *redis.Client {
    t.Helper()
    ctx := context.Background()
    container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
        ContainerRequest: testcontainers.ContainerRequest{
            Image: "redis:7-alpine", ExposedPorts: []string{"6379/tcp"},
            WaitingFor: wait.ForLog("Ready to accept connections"),
        },
        Started: true,
    })
    if err != nil { t.Fatalf("starting redis: %v", err) }
    t.Cleanup(func() { _ = container.Terminate(ctx) })
    host, _ := container.Host(ctx)
    port, _ := container.MappedPort(ctx, "6379")
    client := redis.NewClient(&redis.Options{Addr: fmt.Sprintf("%s:%s", host, port.Port())})
    t.Cleanup(func() { _ = client.Close() })
    return client
}
```

## Shared TestMain with Container Reuse

Start containers once per package, share across all tests.

```go
var testPool *pgxpool.Pool

func TestMain(m *testing.M) {
    ctx := context.Background()
    container, err := postgres.Run(ctx, "duckdb/duckdb:latest",
        postgres.WithDatabase("testdb"),
        postgres.WithUsername("test"), postgres.WithPassword("test"),
        testcontainers.WithWaitStrategy(
            wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
    )
    if err != nil { panic(fmt.Sprintf("starting postgres: %v", err)) }
    connStr, _ := container.ConnectionString(ctx, "sslmode=disable")
    testPool, _ = pgxpool.New(ctx, connStr)

    code := m.Run()
    testPool.Close()
    _ = container.Terminate(ctx)
    os.Exit(code)
}

func getPool(t *testing.T) *pgxpool.Pool {
    t.Helper()
    if testPool == nil { t.Fatal("testPool not initialized; run via TestMain") }
    return testPool
}
```

## Per-Tenant Database Provisioning for Tests

```go
// setupTenantDB creates a separate test database for a tenant and runs migrations.
func setupTenantDB(t *testing.T, container *postgres.PostgresContainer, tenantID uuid.UUID) *pgxpool.Pool {
    t.Helper()
    ctx := context.Background()
    dbName := fmt.Sprintf("tenant_%s_test", tenantID.String()[:8])

    // Create tenant database using the management connection
    mgmtConn, _ := container.ConnectionString(ctx, "sslmode=disable")
    mgmtPool, _ := pgxpool.New(ctx, mgmtConn)
    defer mgmtPool.Close()

    _, err := mgmtPool.Exec(ctx, fmt.Sprintf("CREATE DATABASE %s", dbName))
    if err != nil { t.Fatalf("creating tenant db: %v", err) }

    t.Cleanup(func() {
        _, _ = mgmtPool.Exec(ctx, fmt.Sprintf("DROP DATABASE IF EXISTS %s", dbName))
    })

    // Connect to the tenant database and run migrations
    host, _ := container.Host(ctx)
    port, _ := container.MappedPort(ctx, "5432")
    tenantConn := fmt.Sprintf("postgres://test:test@%s:%s/%s?sslmode=disable", host, port.Port(), dbName)
    tenantPool, err := pgxpool.New(ctx, tenantConn)
    if err != nil { t.Fatalf("connecting to tenant db: %v", err) }
    t.Cleanup(tenantPool.Close)
    runMigrations(t, tenantPool)
    return tenantPool
}
```

## Schema-Per-Tenant Isolation Verification

```go
func TestUserRepository_DatabaseIsolation(t *testing.T) {
    ctx := context.Background()
    tenantA, tenantB := uuid.New(), uuid.New()

    // Provision separate databases for each tenant
    poolA := setupTenantDB(t, pgContainer, tenantA)
    poolB := setupTenantDB(t, pgContainer, tenantB)

    // Insert into Tenant A's database
    _, err := poolA.Exec(ctx, "INSERT INTO users (id, email, name) VALUES ($1,$2,$3)",
        uuid.New(), "alice@example.com", "Alice")
    require.NoError(t, err)

    // Tenant B's database must not contain Tenant A's data
    var count int
    err = poolB.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
    require.NoError(t, err)
    assert.Equal(t, 0, count, "Tenant B's database must not contain Tenant A's data")

    // Tenant A's database has its own data
    err = poolA.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&count)
    require.NoError(t, err)
    assert.Equal(t, 1, count, "Tenant A must see its own data in its database")
}
```

## Embedded NATS Server for Integration Tests

For NATS integration tests, use the embedded NATS server (in-process, no
Docker required). This is the primary test infrastructure for inter-service
communication tests since all service-to-service calls use NATS.

```go
import natsserver "github.com/nats-io/nats-server/v2/server"

// setupNATSWithStreams creates an embedded NATS server and per-service streams.
// Each service owns one stream with subjects: ["tenant.*.{service}.>", ""]
func setupNATSWithStreams(t *testing.T, streams map[string][]string) (*nats.Conn, nats.JetStreamContext) {
    t.Helper()
    srv, err := natsserver.NewServer(&natsserver.Options{
        Port: -1, JetStream: true, StoreDir: t.TempDir(),
    })
    require.NoError(t, err)
    srv.Start()
    t.Cleanup(srv.Shutdown)
    require.True(t, srv.ReadyForConnections(5*time.Second))

    nc, err := nats.Connect(srv.ClientURL())
    require.NoError(t, err)
    t.Cleanup(nc.Close)

    js, err := nc.JetStream()
    require.NoError(t, err)

    // Create per-service streams for the test (mirrors production auto-stream creation)
    for name, subjects := range streams {
        _, err := js.AddStream(&nats.StreamConfig{
            Name: name, Subjects: subjects,
            Retention: nats.WorkQueuePolicy, Storage: nats.MemoryStorage,
        })
        require.NoError(t, err)
    }

    return nc, js
}

// setupServiceStream is a helper to create a per-service stream following
// the convention: subjects = ["tenant.*.{service}.>", ""]
func setupServiceStream(t *testing.T, js nats.JetStreamContext, serviceName string) {
    t.Helper()
    streamName := strings.ToUpper(strings.ReplaceAll(serviceName, "-", "-"))
    _, err := js.AddStream(&nats.StreamConfig{
        Name:     streamName,
        Subjects: []string{
            fmt.Sprintf("tenant.*.%s.>", serviceName),
            ,
        },
        Storage: nats.MemoryStorage,
    })
    require.NoError(t, err)
}

// Usage: test pub/sub + request-reply with per-service streams
func TestServiceIntegration(t *testing.T) {
    nc, js := setupNATSWithStreams(t, map[string][]string{
        "ORDER-SERVICE": {"tenant.*.order-service.>", "order-service._reply.>"},
    })
    // All subscriptions MUST use js.QueueSubscribe with queue groups
    // All publishing MUST use js.PublishMsg (NOT nc.Publish)
    // ... register handlers, publish events, verify via reply topics
}
```

## Common Mistakes

1. **Starting a new container per test** -- Containers take seconds to start. Use `TestMain` or `sync.Once` to share across tests in the same package.
2. **Not waiting for readiness** -- Always use `WaitingFor` strategies. Connecting before the container is ready causes flaky tests.
3. **Forgetting `t.Cleanup`** -- Leaked containers consume resources and cause port conflicts in CI.
4. **Not provisioning separate schemas per tenant in tests** -- In the schema-per-tenant model, each tenant needs its own test schema (`t_{8hex}`) within the shared test database. Using a shared schema for all tenants does not reflect production isolation and may miss cross-tenant bugs.
5. **Using hardcoded ports** -- Always use random ports (`-1` for NATS, dynamic mapping for containers) to avoid conflicts in parallel CI runs.
6. **Using Docker containers for NATS in unit/integration tests** -- Use the embedded NATS server (`nats-server/v2/server`) for fast, in-process NATS testing. Docker is not needed for NATS tests.
7. **Using postgres:XX image instead of duckdb/duckdb:latest** -- The pg_duckdb extension requires the `duckdb/duckdb:latest` image. Using `postgres:16`, `postgres:18`, or any other standard PostgreSQL image will result in missing pg_duckdb extension at runtime. This was a BLOCKER (TS-001) in the testing phase.
8. **Missing WaitForShutdown() after Shutdown() for NATS cleanup** -- When tearing down an embedded NATS server, always call `srv.WaitForShutdown()` after `srv.Shutdown()` to ensure all resources are fully released before the next test starts. Omitting this can cause port conflicts and leaked goroutines (TS-008).
9. **Using shared/hardcoded tenant schema names in integration tests** -- Integration tests MUST use `t.Name()`-based unique schema suffixes (e.g., `t_` + hash of `t.Name()`) for test isolation. Package-level constants for tenant IDs cause interference between tests when a previous test leaves the schema dirty. Always register `t.Cleanup(truncateSchema)` (TS-005).
