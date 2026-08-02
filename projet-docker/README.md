# 🔧 Projet Fil Rouge — Stack Full-Stack avec Docker Compose

Application de gestion de tâches déployée sur AWS EC2 avec une architecture multi-conteneurs.

---

## 📐 Architecture cible

```
Internet
    │
    ▼
┌─────────┐  :80
│  nginx  │  Reverse Proxy
└────┬────┘
     │
     ├──── /api/*  ──────►  ┌─────┐  :8080
     │                      │ api │  Node.js + Express
     │                      └──┬──┘
     │                         │  DNS compose interne
     │                         ▼
     │                      ┌──────────┐  :5432
     │                      │ postgres │  PostgreSQL 16
     │                      └──────────┘
     │
     └──── /*      ──────►  ┌────────┐  :3000
                             │ webapp │  HTML/JS statique
                             └────────┘

Réseau Docker : projetdocker-net (bridge)
Volume Docker : postgres-data (persistance BD)
```

---

## 🗂️ Structure du projet

```
projet-docker/
├── docker-compose.yml
├── README.md
│
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf          ← routage /api → api, / → webapp
│
├── api/
│   ├── Dockerfile
│   ├── package.json
│   └── src/
│       └── index.js        ← Express + routes CRUD
│
├── webapp/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── src/
│       └── index.html      ← UI vanilla JS
│
└── postgres/
    └── init.sql            ← création table + données initiales
```

---

## 🚀 Déploiement sur AWS EC2

### Étape 1 — Lancer une instance EC2

1. Connectez-vous à la console AWS → EC2 → "Launch Instance"
2. Choisissez **Ubuntu 24.04 LTS** (free tier : `t2.micro` ou `t3.micro`)
3. Dans **Security Group**, ouvrez les ports :
   - **22** (SSH)
   - **80** (HTTP)
4. Créez ou sélectionnez une paire de clés SSH
5. Lancez l'instance et notez l'**IP publique**

---

### Étape 2 — Connexion SSH à l'instance

Connectez vous à autre instance EC2 par ssh.

---

### Étape 3 — Installer Docker et Docker Compose

```bash
# Mise à jour des paquets
sudo apt update && sudo apt upgrade -y

# Installation de Docker
curl -fsSL https://get.docker.com | sudo sh

# Ajouter l'utilisateur au groupe docker (évite le sudo)
sudo usermod -aG docker $USER
newgrp docker

# Vérification
docker --version
docker compose version
```

---

### Étape 4 — Cloner le projet

```bash
# Option A : si le projet est sur GitHub
git clone ...
cd projet-docker

# Option B : copier depuis votre machine locale
# (depuis votre machine)
scp -i clesIgor.pem -r ./projet-docker ubuntu@ec2-16-16-123-223.eu-north-1.compute.amazonaws.com:/home/ubuntu/
```

---

### Étape 5 — Lancer la stack

```bash
cd projet-docker

# Construction et démarrage de tous les conteneurs
docker compose up --build -d

# Vérifier que tout est UP
docker compose ps
```

Résultat attendu :
```
NAME       STATUS          PORTS
nginx      Up              0.0.0.0:80->80/tcp
webapp     Up              3000/tcp
api        Up              8080/tcp
postgres   Up              5432/tcp
```

---

### Étape 6 — Tester

```bash
# Health check de l'API
curl http://localhost/api/health

# Liste des tâches
curl http://localhost/api/tasks

# Créer une tâche
curl -X POST http://localhost/api/tasks \
  -H "Content-Type: application/json" \
  -d '{"title": "Ma première tâche"}'

# Basculer une tâche (toggle done)
curl -X PATCH http://localhost/api/tasks/1

# Supprimer une tâche
curl -X DELETE http://localhost/api/tasks/1
```

Depuis un navigateur : `http://<IP_PUBLIQUE>`

---

## 🌐 Endpoints API

| Méthode | Route | Description |
|---------|-------|-------------|
| GET | `/api/health` | Vérification de santé |
| GET | `/api/tasks` | Lister toutes les tâches |
| POST | `/api/tasks` | Créer une tâche `{ "title": "..." }` |
| PATCH | `/api/tasks/:id` | Basculer done/not done |
| DELETE | `/api/tasks/:id` | Supprimer une tâche |

---

## 🐳 Push sur Docker Hub

### 1. Se connecter

```bash
docker login
# Entrez votre username et password Docker Hub
```

### 2. Builder et tagger les images

```bash
export DOCKERHUB_USER=votre-username

# API
docker build -t $DOCKERHUB_USER/projetdocker-api:latest ./api
docker push $DOCKERHUB_USER/projetdocker-api:latest

# Webapp
docker build -t $DOCKERHUB_USER/projetdocker-webapp:latest ./webapp
docker push $DOCKERHUB_USER/projetdocker-webapp:latest

# Nginx
docker build -t $DOCKERHUB_USER/projetdocker-nginx:latest ./nginx
docker push $DOCKERHUB_USER/projetdocker-nginx:latest
```

### 3. Utiliser les images distantes dans docker-compose.yml

Remplacez les sections `build:` par `image:` :

```yaml
api:
  image: votre-username/projetdocker-api:latest
  # build: ./api   ← commenter cette ligne

webapp:
  image: votre-username/projetdocker-webapp:latest
  # build: ./webapp

nginx:
  image: votre-username/projetdocker-nginx:latest
  # build: ./nginx
```

---

## 🛠️ Commandes utiles

```bash
# Voir les logs en temps réel
docker compose logs -f

# Logs d'un service spécifique
docker compose logs -f api

# Redémarrer un service
docker compose restart api

# Stopper et supprimer les conteneurs
docker compose down

# Supprimer aussi les volumes (⚠️ efface la BD)
docker compose down -v

# Entrer dans le conteneur postgres
docker compose exec postgres psql -U admin -d projetdocker

# Rebuild un seul service
docker compose up --build api -d
```

---

## ⚙️ Variables d'environnement

| Variable | Valeur par défaut | Description |
|----------|-------------------|-------------|
| `DB_HOST` | `postgres` | Hostname PostgreSQL (DNS compose) |
| `DB_PORT` | `5432` | Port PostgreSQL |
| `DB_NAME` | `projetdocker` | Nom de la base |
| `DB_USER` | `admin` | Utilisateur |
| `DB_PASSWORD` | `secret123` | Mot de passe |
| `PORT` | `8080` | Port de l'API |

> ⚠️ En production, utilisez un fichier `.env` et ne commitez jamais vos secrets.

Exemple `.env` :
```env
POSTGRES_PASSWORD=motdepassefort
DB_PASSWORD=motdepassefort
```

---

## 🔒 Sécurité en production

- [ ] Changer tous les mots de passe par défaut
- [ ] Utiliser un certificat SSL/TLS (Let's Encrypt + Certbot)
- [ ] Restreindre le Security Group EC2 (ne pas exposer le port 5432 publiquement)
- [ ] Utiliser AWS Secrets Manager ou un fichier `.env` ignoré par git
- [ ] Activer les backups automatiques de PostgreSQL

---

## 📦 Technologies

| Rôle | Technologie |
|------|-------------|
| Reverse Proxy | Nginx |
| Frontend | HTML5 + Vanilla JS |
| Backend | Node.js 20 + Express 4 |
| Base de données | PostgreSQL 16 |
| Orchestration | Docker Compose v3.9 |
| Hébergement | AWS EC2 Ubuntu 24.04 |
