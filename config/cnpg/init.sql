-- Databases managed by the homelab cluster
-- Adding a new database here triggers a new Job run (via configMap hash)
-- Passwords are injected via envsubst from the init-db-secrets Secret

-- memos

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'memos') THEN
    CREATE ROLE memos WITH LOGIN PASSWORD '${MEMOS_PASSWORD}';
  END IF;
END $$;

SELECT 'CREATE DATABASE memos OWNER memos'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'memos')\gexec

GRANT ALL PRIVILEGES ON DATABASE memos TO memos;
