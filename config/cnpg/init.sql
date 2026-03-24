-- Databases managed by the homelab cluster
-- Adding a new database here triggers a new Job run (via configMap hash)
-- Passwords are injected via envsubst from the init-db-secrets Secret

-- memos

SELECT 'CREATE ROLE memos WITH LOGIN PASSWORD ''$${MEMOS_PASSWORD}'''
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'memos')\gexec

ALTER ROLE memos WITH LOGIN PASSWORD '$${MEMOS_PASSWORD}';

SELECT 'CREATE DATABASE memos OWNER memos'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'memos')\gexec

GRANT ALL PRIVILEGES ON DATABASE memos TO memos;

-- norish

SELECT 'CREATE ROLE norish WITH LOGIN PASSWORD ''$${NORISH_PASSWORD}'''
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'norish')\gexec

ALTER ROLE norish WITH LOGIN PASSWORD '$${NORISH_PASSWORD}';

SELECT 'CREATE DATABASE norish OWNER norish'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'norish')\gexec

GRANT ALL PRIVILEGES ON DATABASE norish TO norish;
