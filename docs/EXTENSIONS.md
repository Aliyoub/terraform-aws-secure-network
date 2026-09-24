# Extensions (Phase 11)

Six extensions optionnelles, toutes désactivées par défaut (`var.enable_...` dans `terraform/environments/dev`, voir ADR-019). Construites progressivement, chacune ajoutée par-dessus la précédente, avec un test réel à chaque étape plutôt qu'une simple création. Coûts vérifiés dans `docs/COSTS.md`. Un seul cleanup final après les 6 démonstrations.

## Étape 1/6 : VPC Interface Endpoints

![Les 3 endpoints (ssm, ssmmessages, ec2messages), tous disponibles](../screenshots/13-vpc-endpoints.png)

*Console AWS, VPC → Points de terminaison.*

**Ce que ça déploie.** Trois VPC Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`), chacun dans les deux subnets privés, protégés par un Security Group dédié qui n'autorise le HTTPS (443) que depuis le CIDR du VPC. Une règle de sortie a été ajoutée sur le groupe `app` vers ce nouveau Security Group.

**Pourquoi ces trois services précisément.** Systems Manager Session Manager (l'administration sans SSH, ADR-011) a besoin des trois pour fonctionner depuis un subnet privé sans NAT : `ssm` pour le service lui-même, `ssmmessages` et `ec2messages` pour les canaux de communication de l'agent SSM installé sur l'instance.

**Ce que cette étape ne prouve pas encore.** Aucune instance n'existe pour l'instant : ces endpoints sont prêts, mais rien ne les utilise. La preuve d'usage réel vient à l'étape 2.

**Coût :** 0,011 $/heure par endpoint × 3 = 0,033 $/heure, plus 0,01 $/Go traité (négligeable pour cette démonstration).

## Étape 2/6 : EC2 (administration sans SSH)

![Session Session Manager interactive : whoami, hostname, curl local, tous fonctionnels](../screenshots/14-ec2-session-manager.png)

*Terminal, `aws ssm start-session --target i-08bf2c8ce9377c555`.*

**Ce que ça déploie.** Une instance `t3.micro` (Amazon Linux 2023) dans le subnet privé, sans clé SSH (`key_name = null`), avec IMDSv2 imposé, un rôle IAM dédié (`AmazonSSMManagedInstanceCore`) distinct du rôle OIDC de la CI (Phase 7). Un script `user_data` lance un petit serveur HTTP sur le port 8080, qui servira de cible à l'ALB (étape 4).

**Ce que la capture prouve.** Une vraie session shell, ouverte sans SSH ni IP publique, en s'appuyant sur les VPC Endpoints de l'étape 1 : `whoami` (`ssm-user`), `hostname` (confirme l'instance), et `curl http://localhost:8080/` qui renvoie le contenu posé par `user_data` — le serveur de démonstration fonctionne déjà.

**Un vrai bug d'API trouvé et corrigé.** Le premier `terraform apply` a échoué à la création de l'instance : `InvalidBlockDeviceMapping: Volume of size 8GB is smaller than snapshot ... expect size >= 30GB`. L'AMI Amazon Linux 2023 la plus récente exige un volume racine d'au moins 30 Go. Ni `terraform validate` ni `terraform plan` n'avaient détecté cette contrainte : elle n'apparaît qu'au moment de l'appel réel `RunInstances`. Corrigé en portant `root_volume_size` à 30 (variable dédiée dans le module `ec2-instance`, avec une validation qui l'impose). Les 3 ressources IAM déjà créées lors du premier essai n'ont pas eu besoin d'être recréées : `terraform apply` n'a rejoué que la ressource manquante.

**Coût :** 0,0118 $/heure pour l'instance, plus le stockage EBS (30 Go × 0,0928 $/Go-mois, négligeable pour la durée du test). Le rôle IAM est gratuit.

## Étape 3/6 : NAT Gateway

![Session Session Manager : curl réel vers Internet, HTTP 200](../screenshots/15-nat-connectivity-test.png)

*Terminal, même instance qu'à l'étape 2, `curl https://www.example.com`.*

**Ce que ça déploie.** Un NAT Gateway (Elastic IP `15.224.130.190`) dans le subnet public `a`, et une route ajoutée à la table privée : `0.0.0.0/0 → nat-0d6398254376377d2`. Une règle de sortie HTTPS a été ajoutée sur le groupe `app` vers `0.0.0.0/0`, explicitement, uniquement pour ce test (voir ADR-019).

**Ce que la capture prouve.** La même instance qu'à l'étape 2, dans le même subnet privé, avec la même configuration réseau à l'exception de cette nouvelle route, peut désormais joindre Internet : `curl` renvoie `200`. Avant cette étape, aucune route de sortie n'existait sur la table privée (vérifié en Phases 9 et 10 avec `scripts/network-isolation-check.sh`) : la même requête aurait échoué.

**Pourquoi c'est la preuve la plus significative de la Phase 9/11.** La Phase 9 avait explicitement écarté ce test faute d'instance EC2. C'est la première preuve de connectivité réelle (pas seulement une lecture de configuration) de tout le projet.

**Coût :** 0,05 $/heure (NAT) + 0,005 $/heure (EIP) + 0,05 $/Go traité (trafic négligeable pour ce test).

## Étape 4/6 : ALB

![Requête HTTP complète via l'ALB : connexion, en-têtes, contenu, HTTP 200](../screenshots/16-alb-http-test.png)

*Terminal, `curl -sv http://terraform-aws-secure-network-dev-1041201414.eu-west-3.elb.amazonaws.com/` depuis mon poste.*

**Ce que ça déploie.** Un Application Load Balancer dans les subnets publics, un groupe de cibles sur le port 8080 (le serveur de démonstration de l'étape 2), et un listener HTTP (80). Une règle entrante a été ajoutée sur le groupe `alb`, explicitement, pour ce test.

**Ce que la capture prouve.** Une requête réelle depuis un poste extérieur au VPC, en passant par la chaîne complète : Internet → ALB (subnet public) → groupe de cibles → instance (subnet privé, port 8080). Le corps de la réponse est celui posé par `user_data` en étape 2 : la même instance sert maintenant de cible à l'ALB, sans avoir été redéployée.

**Vérification indépendante avant le test.** La cible du groupe est passée à `healthy` dès la première vérification (`aws elbv2 describe-target-health`), confirmant que le health check HTTP sur `/` fonctionne.

**Pourquoi HTTP et non HTTPS.** Un certificat TLS réel demanderait un nom de domaine et une validation ACM, hors périmètre de ce portfolio (ADR-019). Le listener écoute donc en HTTP (80), avec le CIDR autorisé explicitement en dur pour ce test.

**Coût :** 0,02646 $/heure + 0,0084 $/LCU-heure (négligeable pour ce test).

## Étape 5/6 : RDS

![Résultat de la commande SSM : connexion PostgreSQL réussie, version réelle retournée](../screenshots/17-rds-connectivity-test.png)

*Terminal, `aws ssm get-command-invocation` sur la commande ayant exécuté `psql` depuis l'instance de démonstration.*

**Ce que ça déploie.** Une instance RDS PostgreSQL (`db.t4g.micro`), dans les deux subnets privés, avec un mot de passe généré par Terraform (`random_password`, jamais écrit en dur), `skip_final_snapshot = true` et `backup_retention_period = 0` pour éviter tout stockage résiduel après suppression.

**Ce que la capture prouve.** Un test de connexion réel, pas seulement une lecture de configuration : depuis l'instance EC2 (subnet privé, groupe `app`), installation de `postgresql15` puis `psql` vers l'instance RDS (subnet privé, groupe `db`), authentifié avec le mot de passe généré, exécutant `SELECT version();`. La réponse (`PostgreSQL 16.13...`) confirme que la chaîne `app_sg → db_sg` fonctionne réellement, pas seulement sur le papier.

**Comment le mot de passe a été manipulé sans jamais apparaître à l'écran.** Récupéré depuis le state via `terraform show -json` dans une variable shell, transmis à la commande SSM sans être affiché, puis la capture finale ne montre que le résultat de la commande (`get-command-invocation`), jamais la commande d'origine contenant le mot de passe.

**Coût :** 0,018 $/heure (instance) + stockage (20 Go × 0,133 $/Go-mois, négligeable pour ce test).

## Étape 6/6 : VPC Flow Logs

![CloudWatch Logs Insights : trafic réel capturé sur le NAT Gateway, 1323 enregistrements](../screenshots/18-vpc-flow-logs.png)

*Console AWS, CloudWatch → Logs Insights, groupe `/terraform-aws-secure-network/dev/vpc-flow-logs`.*

**Ce que ça déploie.** Les VPC Flow Logs (trafic `ALL`) vers un groupe CloudWatch Logs dédié (rétention 1 jour), avec un rôle IAM restreint à l'écriture dans ce seul groupe.

**Ce que la capture prouve.** Du trafic réel, pas un VPC vide : 1 323 enregistrements capturés en moins d'une heure, généré par les étapes précédentes (curl via NAT, requêtes ALB, connexion RDS). La requête Logs Insights affiche les 20 plus récents : adresse source, destination, port, action.

**Une observation honnête, pas anticipée.** Cette vue précise ne montre que des `ACCEPT`, contrairement à un autre flux du même groupe (celui de l'ALB) observé en CLI, qui contenait des `REJECT` sur des IP externes inconnues. La vue ci-dessus correspond au réseau du NAT Gateway (`10.20.1.53`), qui reçoit du trafic entrant non sollicité (bruit de fond Internet, sur des ports aléatoires) et le journalise en `ACCEPT` : **un NAT Gateway n'a pas de Security Group** comme une instance EC2 ou un ALB, le filtrage applicatif se fait différemment (absence de session sortante correspondante, pas de blocage explicite au niveau du flux). C'est une nuance réelle découverte en préparant cette capture, plus instructive qu'une preuve univoque.

**Coût :** 0,50 $/Go ingéré (183,3 Ko scannés pour cette requête, donc négligeable) + 0,0315 $/Go-mois de stockage, rétention limitée à 1 jour.
