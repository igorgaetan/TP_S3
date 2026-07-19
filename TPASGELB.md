## Étape 1 : Créer un Launch Template (Modèle de lancement)

Le Launch Template définit le "gabarit" des instances que l'ASG va démarrer automatiquement.

* **Nom :** `lt-web-app` (par exemple)
* **AMI :** Amazon Amazon Linux 2023
* **Type d'instance :** `t3.micro` (ou `t2.micro` selon la région/disponibilité)
* **Key Pair :** Sélectionner une clé existante ou créer sans clé si la connexion SSH n'est pas requise.
* **Security Group (SG HTTP) :** Autoriser le port `80` (HTTP) depuis `0.0.0.0/0` (ou mieux, restreindre l'accès au Security Group de l'ALB plus tard).
* **Advanced Details -> User Data :** Insérer le script Bash suivant pour installer Nginx et créer une page d'accueil dynamique (qui affiche l'IP ou l'ID de l'instance pour voir l'équilibrage de charge).

```bash
#!/bin/bash

# ==============================================================================
# 1. CONFIGURATION DE LA CAPTURE DES LOGS (DEBUG)
# ==============================================================================
# Redirige la sortie standard (stdout) et les erreurs (stderr) vers un fichier dédié
exec > /var/log/user-data.log 2>&1

# Affiche chaque commande exécutée dans le log avec un préfixe '+'
set -x

echo "=== Début de l'exécution du script User Data ==="

# ==============================================================================
# 2. VÉRIFICATION DE LA CONNECTIVITÉ RÉSEAU
# ==============================================================================
# Boucle d'attente pour s'assurer que le réseau et le DNS d'AL2023 sont prêts
echo "Vérification de la connectivité Internet..."
until curl -s --connect-timeout 2 http://www.google.com > /dev/null; do
    echo "En attente de la connectivité réseau et de la résolution DNS..."
    sleep 2
done
echo "Connexion Internet OK."

# ==============================================================================
# 3. MISE À JOUR ET INSTALLATION DE NGINX
# ==============================================================================
echo "Mise à jour des dépôts dnf..."
dnf clean all
dnf update -y

echo "Installation du paquet Nginx..."
dnf install -y nginx

# ==============================================================================
# 4. CONFIGURATION ET DÉMARRAGE DE L'APPLICATION
# ==============================================================================
# On vérifie que le paquet Nginx est bien présent sur le système avant de continuer
if rpm -q nginx; then
    echo "Nginx est bien installé. Configuration en cours..."

    # Activation au démarrage et lancement du service
    systemctl enable nginx
    systemctl start nginx

    # Récupération sécurisée des Métadonnées de l'instance (IMDSv2)
    echo "Récupération des métadonnées IMDSv2..."
    TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

    # Génération de la page d'accueil HTML dynamique
    echo "Génération du fichier index.html..."
    cat <<EOF > /usr/share/nginx/html/index.html
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Lab ASG - ALB</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 40px; 
            background-color: #f5f7fa; 
            color: #333;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 80vh;
        }
        .card { 
            background: white; 
            padding: 30px; 
            border-radius: 12px; 
            box-shadow: 0 4px 15px rgba(0,0,0,0.05); 
            text-align: center;
            border-top: 5px solid #ff9900; /* Couleur AWS */
            max-width: 500px;
            width: 100%;
        }
        h1 { color: #232f3e; margin-bottom: 20px; font-size: 24px; }
        p { font-size: 16px; line-height: 1.6; margin: 10px 0; }
        .badge {
            background-color: #e1e7ee;
            padding: 4px 8px;
            border-radius: 4px;
            font-family: 'Courier New', Courier, monospace;
            font-weight: bold;
            color: #1a2530;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>Hello depuis AWS Auto Scaling !</h1>
        <p>Cette page est servie par un serveur <strong>Nginx</strong> sur Amazon Linux 2023.</p>
        <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
        <p><strong>Instance ID :</strong> <span class="badge">$INSTANCE_ID</span></p>
        <p><strong>IP Privée :</strong> <span class="badge">$LOCAL_IP</span></p>
    </div>
</body>
</html>
EOF

    echo "Vérification finale du statut de Nginx :"
    systemctl status nginx --no-pager

else
    # Si dnf install a échoué silencieusement, on lève une alerte dans nos logs
    echo "ERREUR CRITIQUE : Le paquet Nginx n'a pas été trouvé après l'installation."
fi

echo "=== Fin de l'exécution du script User Data ==="

```

---

## Étape 2 & 3 : Créer l'Auto Scaling Group & Lier à l'ALB

Pour simplifier, il est souvent plus rapide de créer l'**ALB** et le **Target Group** juste avant ou *pendant* la création de l'ASG via l'assistant de la console AWS.

### Configuration de l'ASG :

* **Launch Template :** Choisir `lt-web-app`.
* **Réseau :** Sélectionner le VPC et **plusieurs sous-réseaux publics (multi-AZ)** (ex: `eu-west-3a`, `eu-west-3b`).
* **Load Balancing (Étape 3) :** * Sélectionner *Attach to an existing load balancer* ou *Attach to a new load balancer*.
* Choisir **Application Load Balancer (ALB)**, type *Internet-facing*.
* Créer un **Target Group** (ex: `tg-web-app`) avec le type de cible `Instances` et le protocole `HTTP:80`.


* **Health Checks :** Activer les *ELB health checks* (en plus de ceux d'EC2) pour que l'ASG remplace une instance si l'ALB la détecte comme "Unhealthy".
* **Group Size (Capacités) :**
* *Desired capacity :* 2
* *Minimum capacity :* 2
* *Maximum capacity :* 6



---

## Étape 4 : Configurer la Policy CPU (Scaling Policy)

Dans l'onglet **Automatic scaling** de l'ASG créé :

* Cliquer sur **Add scaling policy**.
* **Policy type :** *Target tracking scaling policy*.
* **Metric type :** *Average CPU utilization*.
* **Target value :** `50` (Déclenche le scaling si la moyenne du CPU du groupe dépasse 50%).
* **Instance warmup :** `300` secondes (temps accordé à l'instance pour démarrer avant d'inclure ses métriques CPU).

---

## Étape 5 : Simuler la montée en charge

Une fois les 2 instances initiales démarrées (`InService`) et saines (`Healthy`) dans le Target Group, on passe à la simulation.

### Option A : Via l'outil `stress` (Directement sur une instance)

Se connecter à l'une des instances EC2 (via SSH ou EC2 Instance Connect) et exécuter :

```bash
# Installer le dépôt EPEL puis l'outil stress
sudo amazon-linux-extras install epel -y
sudo yum install stress -y

# Lancer la charge sur 8 cœurs CPU pendant 5 minutes (300s)
stress --cpu 8 --timeout 300

```

### Option B : Via Apache Bench `ab` (Depuis une machine externe)

Depuis un terminal externe (ta machine ou une autre instance de test), envoyer des milliers de requêtes HTTP vers le **DNS de l'ALB** :

```bash
# Envoi de 50 000 requêtes, par paquets de 100 requêtes simultanées
ab -n 50000 -c 100 http://ASG-ALB-1-1458060433.eu-north-1.elb.amazonaws.com/

```

---

## Étape 6 : Observer le scaling

C'est la phase d'observation pédagogique pour les apprenants.

1. **Vérification de la charge :** Aller dans **CloudWatch -> Alarms**. Une alarme créée automatiquement par Target Tracking (`TargetTracking-xxxxx-AlarmHigh`) va passer à l'état `In alarm`.
2. **Activité de l'ASG :** Dans l'onglet **Activity** de l'ASG, observer l'apparition de la ligne : *« Launching a new EC2 instance... »*.
3. **Vérification du Dashboard EC2 :** Constater que de nouvelles instances passent de `Pending` à `Running`.
4. **Test du Load Balancing :** En rafraîchissant la page du DNS de l'ALB, montrer que l'Instance ID change (preuve que l'ALB distribue bien le trafic sur les anciennes et nouvelles instances).
5. **Scale-down :** Après l'arrêt du script `stress` (ou de la commande `ab`), attendre ~5 à 10 minutes pour observer l'alarme basse se déclencher et l'ASG résilier les instances superflues pour revenir à la capacité désirée de 2.

