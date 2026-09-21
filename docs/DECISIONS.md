# Décisions d'architecture (ADR)

## ADR-001 : la région de déploiement est `eu-west-3` (Paris)

- **Contexte :** la région par défaut de l'AWS CLI était `us-east-1`. L'auteur est basé en France.
- **Décision :** déployer en `eu-west-3`, exposée via la variable `aws_region`.
- **Conséquences :** aucun impact sur les coûts pour une infrastructure purement réseau ; les données restent dans l'UE. Les tarifs devront être vérifiés par région dans `COSTS.md`.

## ADR-002 : le module racine se trouve dans `terraform/environments/dev`

- **Contexte :** l'arborescence initiale prévoyait des fichiers racine dans `terraform/` et un dossier `environments/dev/`, ce qui dupliquait le point d'entrée.
- **Décision :** un seul module racine par environnement sous `terraform/environments/<env>/`, qui appelle les modules partagés de `terraform/modules/`.
- **Conséquences :** ajouter un environnement revient à ajouter un dossier, sans copier les modules. Le state et les variables restent isolés par environnement.

## ADR-003 : state local au départ, backend distant à évaluer

- **Contexte :** un backend distant (S3 avec verrouillage) est une bonne pratique, mais le bucket est lui-même une ressource à gérer et à sécuriser.
- **Décision :** démarrer avec un state local, exclu de Git. À reconsidérer avant tout déploiement partagé.
- **Conséquences :** le fichier de state ne doit jamais être commité (garanti par le `.gitignore`).

## ADR-004 : contraintes de version de Terraform et du provider

- **Décision :** `required_version >= 1.9.0, < 2.0.0` et provider AWS `~> 6.0`. Le fichier `.terraform.lock.hcl` est commité pour figer les builds exacts du provider.
- **Conséquences :** les mises à jour mineures sont autorisées, les changements majeurs nécessitent une décision explicite.

## ADR-005 : plan d'adressage `10.20.0.0/16`

- **Contexte :** le compte contient déjà deux VPC en `eu-west-3` (`10.0.0.0/16` et `192.168.0.0/16`). Un chevauchement empêcherait tout futur peering ou connexion VPN.
- **Décision :** VPC en `10.20.0.0/16`, subnets publics en `10.20.1.0/24` et `10.20.2.0/24`, subnets privés en `10.20.11.0/24` et `10.20.12.0/24`.
- **Conséquences :** le plan d'adressage ne chevauche aucun VPC existant du compte. Les plages `10.20.1-9.x` sont réservées au public et `10.20.11-19.x` au privé, ce qui laisse de la place pour une 3e zone et pour une couche « données » (par ex. `10.20.21.0/24`). Détails dans `ARCHITECTURE.md`.

## ADR-006 : pas d'IP publique automatique, même sur les subnets publics

- **Contexte :** un subnet est « public » parce que sa table de routage a une route vers l'Internet Gateway, pas à cause d'un paramètre du subnet. `map_public_ip_on_launch` ne fait qu'attribuer une IP publique au lancement.
- **Décision :** `map_public_ip_on_launch = false` par défaut dans le module `subnet`, y compris pour les subnets publics.
- **Conséquences :** une instance lancée dans un subnet public n'est pas exposée par accident. Une IP publique devra être demandée explicitement (Elastic IP ou attribution à la création), ce qui évite aussi une facturation d'IPv4 publique non voulue.

## ADR-007 : validation du contenu des CIDR sans `cidrcontains`

- **Contexte :** la fonction `cidrcontains` n'existe pas dans Terraform (elle est propre à OpenTofu). `terraform validate` n'a pas détecté l'erreur ; seul `terraform plan` l'a fait.
- **Décision :** vérifier l'appartenance d'un subnet au VPC avec `cidrhost` : le préfixe du subnet doit être au moins aussi long que celui du VPC, et son adresse, ramenée au préfixe du VPC, doit donner le même réseau.
- **Conséquences :** la validation fonctionne avec Terraform. Un `plan` reste nécessaire en CI (Phase 6), `validate` seul ne suffit pas.

## ADR-008 : la table de routage principale du VPC est gérée et laissée sans route

- **Contexte :** chaque VPC est créé avec une table de routage principale. Tout subnet qui n'est associé à aucune table explicite l'utilise. Si quelqu'un y ajoutait une route vers l'Internet Gateway, tous ces subnets deviendraient publics sans que ce soit visible dans le code.
- **Décision :** gérer cette table avec `aws_default_route_table` et `route = []`, et associer explicitement chaque subnet à une table dédiée (publique ou privée).
- **Conséquences :** un nouveau subnet oublié n'a jamais de sortie vers Internet (comportement « sûr par défaut »), et une route ajoutée à la main dans cette table est supprimée au prochain `apply`, ce qui aide aussi à détecter un drift.

## ADR-009 : une table de routage par niveau, l'Internet Gateway est facultatif dans le module `vpc`

- **Contexte :** un NAT Gateway par zone impose une table privée par zone, mais aucun NAT n'est créé dans cette version.
- **Décision :** une table publique et une table privée, partagées par les deux zones. L'Internet Gateway est créé par le module `vpc` uniquement si `create_internet_gateway = true` (désactivé par défaut, activé dans `dev`). Les routes sont passées au module `route-table` sous forme de map, ce qui permet d'ajouter plus tard une route vers un NAT sans modifier le module.
- **Conséquences :** simple et lisible aujourd'hui. Si un NAT par zone est ajouté (Phase 11), il faudra une table privée par zone : le découpage en `for_each` sera alors nécessaire.

## ADR-010 : Security Groups en chaîne `alb -> app -> db`, fermés par défaut

- **Contexte :** l'architecture cible comprend un ALB optionnel, une application privée et une base optionnelle. Aucune de ces ressources n'est créée, mais leurs groupes de sécurité ne coûtent rien et documentent le modèle d'accès.
- **Décision :** trois groupes, où chaque maillon n'accepte que le trafic du précédent, désigné par **référence à son groupe** et non par un CIDR, et ne sort que vers le suivant. L'entrée Internet du groupe `alb` est pilotée par `alb_allowed_https_cidrs`, **vide par défaut** : rien n'est ouvert tant que cela n'est pas demandé.
- **Conséquences :** un changement d'adresses IP dans un subnet ne casse aucune règle. Exposer un ALB public est un acte explicite (`["0.0.0.0/0"]`) et visible dans le code. Le groupe `db` n'a aucune règle sortante.

## ADR-011 : aucun SSH, administration sans port entrant

- **Décision :** aucun groupe ne contient de règle sur le port 22. Le module `security-group` rejette à la validation tout SSH (22) ou RDP (3389) ouvert à `0.0.0.0/0`, ainsi que toute règle entrante « tous protocoles ».
- **Conséquences :** si une instance doit être administrée, on utilisera AWS Systems Manager Session Manager, qui ne demande aucun port entrant, ni IP publique, ni clé SSH à gérer. Session Manager depuis un subnet privé sans NAT exige des VPC endpoints (`ssm`, `ssmmessages`, `ec2messages`) : ils sont facturés à l'heure et à évaluer en Phase 11.

## ADR-012 : groupe de sécurité par défaut adopté et vidé, pas de NACL personnalisée

- **Décision :** le groupe de sécurité par défaut du VPC est géré par Terraform sans aucune règle (`ingress = []`, `egress = []`). Aucune Network ACL personnalisée n'est créée : la NACL par défaut (qui autorise tout) est conservée.
- **Justification :** les Security Groups, stateful et rattachés aux ressources, portent déjà la segmentation. Une NACL est stateless : il faut autoriser explicitement le trafic retour sur les ports éphémères (1024-65535), ce qui la rend facile à mal configurer pour un bénéfice faible ici. À réévaluer si une exigence de blocage explicite d'adresses (deny) apparaît, cas où seule une NACL convient.
- **Conséquences :** une seule couche de filtrage à auditer dans cette version. Le compromis est documenté dans `SECURITY.md`.

## ADR-013 : descriptions des règles sans accents ni apostrophes

- **Contexte :** l'API AWS refuse les caractères hors `a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*` dans les descriptions de groupes et de règles. `terraform plan` ne détecte pas l'erreur : elle n'apparaît qu'à l'`apply`.
- **Décision :** valider ce jeu de caractères dans le module `security-group`.
- **Conséquences :** l'erreur est détectée dès le `plan`. Les descriptions sont en français sans accents.

## ADR-014 : validation locale par script, tflint installé depuis la release officielle

- **Contexte :** `terraform validate` ne vérifie que la syntaxe et la cohérence interne (il n'a pas détecté `cidrcontains`, voir ADR-007). Il faut une analyse statique complémentaire et un moyen de rejouer les mêmes contrôles à la main et en CI (Phase 6).
- **Décision :** `scripts/validate.sh` enchaîne `terraform fmt -check`, `init -backend=false` et `validate`, `tflint` (règles Terraform recommandées et règles AWS, plugin AWS épinglé en `0.49.0`), un garde-fou de coût et une recherche de secrets. `tflint` est installé depuis le binaire de la release GitHub, dont l'empreinte SHA-256 a été comparée à `checksums.txt`, la formule Homebrew étant introuvable sur cette machine.
- **Garde-fou de coût :** `scripts/check-aws-cost-risk.sh` échoue si le code déclare une ressource potentiellement payante (NAT Gateway, Elastic IP, load balancer, instance, base, endpoint, Flow Logs, etc.), sauf `ALLOW_PAID_RESOURCES=1`. C'est une analyse statique : elle ne remplace ni le `plan` ni la vérification des tarifs.
- **Conséquences :** aucun appel AWS ni ressource créée pendant ces contrôles. La recherche de secrets par motifs est volontairement simple (clé d'accès, clé secrète, clé privée) et ne remplace pas un vrai scanner. Les scripts ont été validés avec des cas témoins qui doivent échouer.
