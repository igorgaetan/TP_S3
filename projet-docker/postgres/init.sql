-- Initialisation de la base de données Fil Rouge

CREATE TABLE IF NOT EXISTS tasks (
  id        SERIAL PRIMARY KEY,
  title     VARCHAR(255) NOT NULL,
  done      BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Données de départ
INSERT INTO tasks (title, done) VALUES
  ('Écrire les Dockerfiles', true),
  ('Rédiger le docker-compose.yml', true),
  ('Lancer docker compose up', false),
  ('Tester l''API et l''UI', false),
  ('Push sur Docker Hub', false);
