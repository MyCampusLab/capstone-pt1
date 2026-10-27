# Repository Guidelines

## Project Overview

`geges_smartbarber` (SmartBarber) is a multi-tenant barbershop queue, dynamic scheduling, and zero-fee QRIS payment platform built for micro-SME partner barbershops (`febrian-barbershop`, `rr-barber-studio`, `stupid-culture`). It combines a dual-flavor Flutter mobile client (`lib/main_customer.dart`, `lib/main_partner.dart`) with a Twelve-Factor Express + Socket.IO + PostgreSQL 16 backend (`backend/src/server.ts`).

Core domain capabilities:
- **Zero-Order Fuzzy Sugeno Duration Estimation**: Predicts service duration from service complexity ($X_1 \in [1, 10]$) and barber speed ($X_2 \in [15, 45]$ minutes) across 9 fuzzy rules (`backend/src/algorithms/fuzzySugeno.ts`).
- **Smart Dispatch Task Allocation**: Assigns incoming `barberId: 'smart'` bookings to the on-duty barber with the lowest total duration backlog, breaking ties by active queue count and chair number (`backend/src/algorithms/smartDispatch.ts`).
- **Zero-Fee Dynamic EMVCo QRIS & DompetKu Webhook Bridge**: Converts static merchant QRIS strings (`010211`) into nominal-locked dynamic QRIS strings (`010212` + Tag `54` + recalculated `6304` CRC16-CCITT) with collision-free unique codes (`1..50`) and HMAC-SHA256 webhook auto-reconciliation (`backend/src/algorithms/emvcoQris.ts`, `lib/utils/emvco_qris_helper.dart`).

## Architecture & Data Flow

1. **Dual-Stack Client & Backend**:
   - **Flutter Client (`lib/`)**: Uses `Provider` (`ChangeNotifierProvider`) + Firebase Auth/Firestore streams for real-time UI updates, paired with `HttpApiClient` (`lib/services/http_api_client.dart`) and `HttpQueueRepository` (`lib/services/http_queue_repository.dart`) for REST communication with the backend.
   - **Express + Socket.IO Backend (`backend/src/`)**: Exposes REST endpoints under `/api/tenants`, `/api/queue`, `/api/fuzzy`, `/api/cashier`, `/api/payments`, `/api/reports`, and `/api/media`, broadcasting real-time events (`queue:<slug>:updated`, `payment:verified`, `payment:<slug>:unmatched`) via `SocketIOServer`.
2. **Dual-Mode Database Resilience (PostgreSQL + In-Memory Fallback)**:
   - `backend/src/database/db.ts` wraps `pg.Pool` with a 3000ms fast-fail circuit breaker (`OFFLINE_COOLDOWN_MS`).
   - Every backend route and service (`queue.routes.ts`, `cashier.routes.ts`, `payment.routes.ts`, `report.routes.ts`, `paymentAllocator.ts`) reads/writes PostgreSQL first and falls back to in-memory stores (`inMemoryQueues`, `inMemoryPayments`, `inMemoryUnmatchedNotifications`, `FALLBACK_TENANTS`) when PostgreSQL is unreachable. Never return an unhandled `500` on database connection failure; preserve the in-memory fallback contract so CI tests pass without a database container.
3. **Booking & Payment Lifecycle**:
   - Booking creation (`POST /api/queue/book` or `QueueService.createQueue` Firestore transaction) computes Fuzzy Sugeno duration, dispatches a barber, and allocates a per-tenant collision-free payment amount (`expectedAmount = baseAmount + uniqueCode`) with a 15-minute expiry window.
   - `allocateUniquePayment` (`backend/src/services/paymentAllocator.ts`) retries up to 5 times on PostgreSQL `23505` unique constraint violations (`idx_unique_pending_amount_per_tenant`).
   - Incoming DompetKu notifications hit `POST /api/payments/webhook/:tenantSlug`, where `verifyDompetkuWebhookAuth` validates `X-Dompetku-Timestamp` ($\pm 300\text{s}$) and `X-Dompetku-Signature` (`HMAC-SHA256(secret, "$timestamp.$rawBody")`), filters `ALLOWED_DOMPETKU_APP_SOURCES`, enforces idempotency (`200 OK` on duplicate `dompetku_tx_id`), and transitions matching reservations to `checked_in` / `verified`.

## Key Directories

- `lib/config/` — Flavor configuration (`AppFlavorConfig` for `customer` B2C vs `partner` B2B builds).
- `lib/models/` — Dart domain models (`Barbershop`, `Barberman`, `Queue`, `Service`, `UserData`) with Firestore serialization (`fromFirestore`, `toMap`).
- `lib/services/` — Business logic and data access (`QueueService`, `QueueServiceContract`, `BarbershopService`, `AuthService`, `HttpQueueRepository`).
- `lib/screens/` — Role-segregated UI screens (`customer/`, `admin/`, `barberman/`, `super_admin/`).
- `lib/utils/` — Pure Dart helpers (`emvco_qris_helper.dart`, `fuzzy_sugeno_helper.dart`, `validation.dart`).
- `lib/l10n/` — ARB localization catalogs (`app_id.arb`, `app_en.arb`) and generated `AppLocalizations`.
- `backend/src/algorithms/` — Pure TypeScript engines (`fuzzySugeno.ts`, `smartDispatch.ts`, `emvcoQris.ts`).
- `backend/src/routes/` — Express domain routers (`queue.routes.ts`, `payment.routes.ts`, `cashier.routes.ts`, `report.routes.ts`, `tenant.routes.ts`, `media.routes.ts`).
- `backend/src/services/` — Stateful backend services (`paymentAllocator.ts`, `notification.ts`).
- `backend/src/database/` — PostgreSQL pool/circuit breaker (`db.ts`), DDL (`schema.sql`), migration runner (`migrate.ts`), and thesis dataset seeder (`seed.ts`).
- `backend/src/tests/` — Backend unit, concurrency, academic accuracy (`mae_mape.test.ts`), and E2E test suites.
- `test/` — Flutter unit (`test/unit/`), widget (`test/widget/`), service (`test/services/`), and test helper (`test/helpers/`) suites.

## Development Commands

### Root (`Makefile` & Flutter)
```bash
# Install Flutter dependencies
flutter pub get

# Static analysis (must report "No issues found!")
flutter analyze

# Run dual-flavor mobile apps
make run-customer          # flutter run -t lib/main_customer.dart
make run-partner           # flutter run -t lib/main_partner.dart

# Build release APKs
make build-customer        # flutter build apk --release -t lib/main_customer.dart
make build-partner         # flutter build apk --release -t lib/main_partner.dart

# Start/stop local PostgreSQL 16 + MinIO containers (uses backend/docker-compose.yml)
make db-up
make db-down
make db-migrate            # cd backend && bun run db:migrate
make db-seed               # cd backend && bun run db:seed
```

### Backend (`backend/`)
```bash
cd backend

# Install dependencies
bun install

# Start development server with hot reload (port 4000)
bun run dev

# TypeScript strict typecheck
bun x tsc --noEmit

# Run full backend test suite (live PostgreSQL if up, otherwise in-memory fallback)
bun test

# Simulate CI offline-DB test run (must pass 100% without PostgreSQL)
DATABASE_URL="postgresql://invalid:5432/none" bun test
```

## Code Conventions & Common Patterns

- **TypeScript ESM Imports (`backend/`)**: `backend/tsconfig.json` uses `"module": "NodeNext"` and `"moduleResolution": "NodeNext"` with `"strict": true`. All local relative imports in `backend/src/**/*.ts` **must** end with `.js` (e.g., `import { query } from '../database/db.js';`).
- **Input & Environment Validation**: Validate all Express payloads and environment variables with `zod` (`safeParse`). Add new backend env variables to `envSchema` in `backend/src/config/env.ts` with safe development defaults so CI and tests boot without `.env` files.
- **Admin Endpoint Protection**: Sensitive tenant/payment admin routes (`/dompetku-config`, `/qris-config`, `/verify-manual`, `/unmatched`) require `requireAdminKey(req, res, tenant.webhook_secret)` in `backend/src/routes/payment.routes.ts`, accepting either header `x-admin-key` (`env.ADMIN_API_KEY`) or `x-dompetku-secret` compared via `crypto.timingSafeEqual`.
- **Bounded In-Memory Fallback Stores**: When pushing to in-memory arrays (`inMemoryPayments`, `inMemoryUnmatchedNotifications`), cap array length at 200 items (`splice(0, list.length - 200)`) to prevent unbounded memory growth.
- **Flutter Service Dependency Injection**: Services accept optional `FirebaseFirestore?` and `FirebaseAuth?` constructor parameters (e.g., `QueueService({FirebaseFirestore? firestore, FirebaseAuth? auth})`) and screens accept `QueueServiceContract?` (`lib/services/queue_service_contract.dart`) so widget tests can inject `FakeFirebaseFirestore`, `MockFirebaseAuth`, or lightweight fakes without initializing live Firebase plugins.
- **Tenant Isolation on Fallbacks**: Never fall back to `febrian-barbershop` payment credentials or QRIS payloads when `barbershopId` belongs to another tenant (`rr-barber-studio`, `stupid-culture`).

## Important Files

- `lib/main.dart` (`bootstrapApp`) — Shared Flutter bootstrap (Sentry, Firebase Core, App Check, Localization, Provider tree); invoked by `lib/main_customer.dart` and `lib/main_partner.dart`.
- `lib/screens/customer/payment_screen.dart` — Customer dynamic QRIS display, deterministic/server unique code resolution, countdown timer, and manual transfer proof upload.
- `lib/screens/admin/payment_verification_screen.dart` — Cashier 3-tab reconciliation workspace (Antrean QRIS Aktif, Uang Masuk Belum Cocok, Bukti Transfer Manual).
- `lib/screens/admin/barbershop_settings_screen.dart` — Partner static QRIS validator and 1-click DompetKu Smart Paste URL generator.
- `backend/src/server.ts` — Express + Socket.IO server entry point; preserves `req.rawBody` for DompetKu HMAC-SHA256 verification.
- `backend/src/routes/payment.routes.ts` — DompetKu webhook handler, HMAC-SHA256 verifier, status mapper (`toPaymentStatusDto`), and manual cashier reconciliation endpoints.
- `backend/src/services/paymentAllocator.ts` — `allocateUniquePayment` and `expireStalePendingPayments`.
- `backend/src/database/schema.sql` & `backend/src/database/seed.ts` — Relational schema (7 tables + 2 views) and calibrated 3-tenant seed dataset.
- `.github/workflows/ci.yml` — GitHub Actions pipeline running `backend-checks` (`bun x tsc --noEmit` + `bun test`) and `flutter-checks` (`flutter analyze` + stable unit/widget test suite).

## Runtime/Tooling Preferences

- **Backend Runtime & Package Manager**: Prefer `bun` (`bun install`, `bun test`, `bun x tsc --noEmit`) inside `backend/`. `backend/bun.lock` is the canonical lockfile.
- **Docker Compose Path**: `docker-compose.yml` resides in `backend/docker-compose.yml` (PostgreSQL 16 on port `5432`, MinIO on ports `9000`/`9001`).
- **Localization**: Strings in UI screens use `AppLocalizations.of(context)!` configured via `l10n.yaml` (`lib/l10n/app_id.arb`, `lib/l10n/app_en.arb`).

## Testing & QA

- **Backend Tests (`backend/src/tests/*.test.ts`)**:
  - Written with `node:test` (`describe`, `test`, `before`, `after`) and `node:assert/strict`, executed via `bun test`.
  - E2E tests check `fetch('http://localhost:4000/health')` in `before()` and start `server.listen(4000)` if not already listening.
  - When writing tests that insert fixed external transaction IDs (e.g., `dompetku_tx_id`), clean up both `inMemory*` arrays and PostgreSQL tables in `before()` so repeated local runs against live PostgreSQL remain idempotent.
  - Always verify backend changes in both modes:
    ```bash
    cd backend && bun x tsc --noEmit && bun test && DATABASE_URL="postgresql://invalid:5432/none" bun test
    ```
- **Flutter Tests (`test/`)**:
  - `test/flutter_test_config.dart` automatically blocks real HTTP calls via `disableNetworkCalls()`.
  - Wrap widgets under test with `wrapWithLocalization(...)` from `test/helpers/test_helpers.dart`.
  - Run the CI-enforced analyzer and test gate from the repository root:
    ```bash
    flutter analyze && flutter test test/unit/emvco_qris_helper_test.dart test/widget/auth/login_register_ui_test.dart test/widget/payment/payment_screen_widget_test.dart test/widget/payment_screen_blocking_v2_test.dart test/widget/payment/payment_screen_tenant_snackbar_test.dart
    ```
