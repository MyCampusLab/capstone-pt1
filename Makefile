.PHONY: help dev build test db-up db-down db-migrate db-seed clean status tunnel

help:
	@echo "================================================================="
	@echo "  SMARTBARBER ECOSYSTEM (12-FACTOR MULTI-TENANT CORE)"
	@echo "================================================================="
	@echo "  make dev         - Jalankan backend TypeScript watch mode"
	@echo "  make test        - Jalankan seluruh rangkaian unit & integration test"
	@echo "  make build       - Kompilasi backend TypeScript ke dist/"
	@echo "  make db-up       - Jalankan PostgreSQL & MinIO S3 via Docker Compose"
	@echo "  make db-down     - Hentikan kontainer database"
	@echo "  make db-migrate  - Eksekusi migrasi skema PostgreSQL multi-tenant"
	@echo "  make db-seed     - Masukkan data awal 3 barbershop mitra (Febrian, RR, Stupid Culture)"
	@echo "  make status      - Periksa status kontainer & proses backend"
	@echo "  make tunnel      - Buka tunnel HTTPS publik gratis ke port 4000 via Cloudflare"
	@echo "================================================================="

dev:
	cd backend && bun run dev

build:
	cd backend && bun run build

test:
	cd backend && bun test

db-up:
	cd backend && docker compose up -d

db-down:
	cd backend && docker compose down

db-migrate:
	cd backend && bun run db:migrate

db-seed:
	cd backend && bun run db:seed

status:
	@echo "--- Docker Containers ---"
	cd backend && docker compose ps
	@echo "\n--- Node/Bun Processes ---"
	pgrep -fl "bun|node" || true

tunnel:
	cloudflared tunnel --url http://localhost:4000

clean:
	rm -rf backend/dist backend/node_modules/.cache
