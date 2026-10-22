SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'db_name', :'app_user') \gexec

\connect :db_name

BEGIN;

CREATE TABLE IF NOT EXISTS public.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    image_key VARCHAR(512)
);

SELECT format('ALTER TABLE public.products OWNER TO %I', :'app_user') \gexec
SELECT format('ALTER SEQUENCE IF EXISTS public.products_id_seq OWNER TO %I', :'app_user') \gexec

SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', :'app_user') \gexec
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.products TO %I', :'app_user') \gexec
SELECT format('GRANT USAGE, SELECT, UPDATE ON SEQUENCE public.products_id_seq TO %I', :'app_user') \gexec

COMMIT;

