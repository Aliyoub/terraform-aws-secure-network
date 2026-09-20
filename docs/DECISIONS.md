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
