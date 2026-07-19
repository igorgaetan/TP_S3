# TP : Haute Disponibilité avec AWS Application Load Balancer (ALB)

### Objectifs du TP :

1. Déployer deux serveurs web dans deux zones de disponibilité (AZ) différentes (Multi-AZ).
2. Configurer un Target Group et un Application Load Balancer.
3. Vérifier la répartition de charge (Load Balancing).
4. **Prouver la Haute Disponibilité** en simulant la panne d'un serveur ou d'une zone complète.

---

## Étape 1 : Création des Instances EC2 (Multi-AZ)

Pour garantir la haute disponibilité, l'erreur classique est de mettre les deux serveurs dans le même sous-réseau (Subnet). Il faut impérativement les séparer.

* **Instance 1 :**
* **Nom :** `Serveur-Web-A`
* **Réseau :** Sélectionne le VPC par défaut, mais choisis explicitement le Subnet de la **Zone A** (ex: `eu-west-3a`).
* **User Data :**
```bash
#!/bin/bash
sudo apt update -y # ou yum install -y httpd selon l'AMI
sudo apt install nginx -y
echo "<h1>Je suis le Serveur 1 - Zone A</h1>" > /var/www/html/index.html
sudo systemctl start nginx

```




* **Instance 2 :**
* **Nom :** `Serveur-Web-B`
* **Réseau :** Même VPC, mais choisis explicitement le Subnet de la **Zone B** (ex: `eu-west-3b`).
* **User Data :**
```bash
#!/bin/bash
sudo apt update -y
sudo apt install nginx -y
echo "<h1>Je suis le Serveur 2 - Zone B</h1>" > /var/www/html/index.html
sudo systemctl start nginx

```





*Note pour le Security Group des EC2 : Autoriser le port 80 (HTTP). Pour de la vraie sécu, on n'autorise que l'IP du Load Balancer, mais pour un TP simple, l'ouvrir à `0.0.0.0/0` fonctionne.*

---

## Étape 2 : Configuration du Target Group (TG)

Le Target Group va regrouper nos machines et surveiller leur état de santé.

1. Créer un Target Group de type **Instances**.
2. **Protocole :** HTTP sur le port 80.
3. **Health Checks :** Path `/` (l'ALB va régulièrement demander la page d'accueil pour voir si Nginx répond).
4. **Register Targets :** Sélectionner `Serveur-Web-A` et `Serveur-Web-B`, puis cliquer sur *"Include as pending below"*.

---

## Étape 3 : Déploiement de l'Application Load Balancer (ALB)

C'est ici qu'on configure l'entrée unique et la redondance réseau de l'AWS ELB.

1. Créer un **Application Load Balancer**.
2. **Scheme :** `Internet-facing` (pour qu'il soit accessible depuis ton navigateur).
3. **Network Mapping (Crucial pour la HA) :** Sélectionner le VPC et cocher **au moins 2 zones de disponibilité** (les sous-réseaux correspondants à la Zone A et la Zone B où résident tes EC2). AWS oblige l'ALB à être présent sur minimum 2 zones pour assurer sa propre haute disponibilité.
4. **Listeners and Routing :** * Protocol: HTTP / Port: 80.
* Forward to : Sélectionner le Target Group créé à l'étape 2.



---

## Étape 4 : Validation et Tests (La partie fun pour les étudiants)

### Test 1 : Le Load Balancing (Round-Robin)

1. Aller dans l'onglet de l'ALB, copier son **DNS Name** (ex: `mon-alb-123456.eu-west-3.elb.amazonaws.com`).
2. Le coller dans un navigateur.
3. Actualiser la page plusieurs fois (ou ouvrir un onglet privé si le navigateur garde en cache).
4. **Résultat attendu :** Tu dois voir alterner *"Je suis le Serveur 1 - Zone A"* et *"Je suis le Serveur 2 - Zone B"*.

### Test 2 : Le crash test (Preuve de la Haute Disponibilité)

C'est l'étape clé pour valider l'objectif "Haute Disponibilité" :

1. Demander aux étudiants d'aller sur la console EC2 et de **Stopper** (ou simuler une panne en coupant le service Nginx en SSH) le `Serveur-Web-A`.
2. Aller dans l'onglet **Target Group** $\rightarrow$ **Targets**.
3. **Observation :** Au bout de quelques secondes, le statut du Serveur 1 va passer de `Healthy` à `Unhealthy`.
4. Retourner sur le navigateur avec l'URL de l'ALB et rafraîchir frénétiquement.
5. **Résultat attendu :** Le site reste accessible à 100% ! Seul le *"Serveur 2 - Zone B"* répond. L'utilisateur final ne s'est rendu compte de rien (zéro coupure de service).

---

## Questions bonus à poser aux étudiants pour l'évaluation :

* *Pourquoi l'ALB refuse-t-il d'être configuré sur une seule zone de disponibilité lors de sa création ?* (Réponse : Pour éviter d'être lui-même un SPOF - Single Point of Failure).
* *Si on coupe Nginx sur une machine mais que l'instance EC2 reste "Running", est-ce que le Load Balancer continue de lui envoyer des clients ? Pourquoi ?* (Réponse : Non, car le Health Check teste l'application sur le port 80, pas seulement le statut de la VM).