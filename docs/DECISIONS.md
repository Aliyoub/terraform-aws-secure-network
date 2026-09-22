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

## ADR-015 : workflow de validation sans accès AWS, actions épinglées, script partagé

- **Contexte :** la CI doit refuser un code non conforme sans jamais pouvoir modifier l'infrastructure ni exposer de secret.
- **Décision :** `.github/workflows/terraform-validate.yml` exécute `scripts/validate.sh`, le même script qu'en local, ce qui garantit des contrôles identiques aux deux endroits. Il se déclenche sur les push vers `main`, les pull requests et à la demande. Il n'utilise aucun secret et ne se connecte pas à AWS.
- **Permissions :** `contents: read` uniquement, définies au niveau du workflow. Le checkout n'enregistre pas le jeton (`persist-credentials: false`).
- **Chaîne d'approvisionnement :** les trois actions (`checkout`, `setup-terraform`, `setup-tflint`) sont épinglées sur le SHA d'un commit, avec la version en commentaire, car un tag peut être déplacé vers un autre code. Les versions de Terraform (1.16.1) et de tflint (v0.64.0) sont fixées. `terraform init` est lancé avec `-lockfile=readonly` : si le fichier de verrouillage devait changer, la CI échoue au lieu d'accepter silencieusement un autre provider.
- **Conséquences :** l'épinglage par SHA impose de mettre les actions à jour à la main (ou via un outil de suivi des dépendances). Le plan Terraform, qui a besoin d'un accès AWS en lecture, viendra avec OIDC (Phase 7).

## ADR-016 : bootstrap OIDC/IAM dans un environnement Terraform séparé

- **Contexte :** le fournisseur OIDC de GitHub Actions et le rôle IAM qu'il peut endosser sont des ressources IAM globales, prérequises pour que la CI accède au compte. Elles ne peuvent pas être créées par la CI elle-même (problème de démarrage) et leur cycle de vie ne doit pas dépendre de celui du réseau `dev`.
- **Décision :** `terraform/environments/bootstrap/`, un module racine et un state distincts de `dev`. Ce module s'applique une fois, à la main, avec les credentials personnels déjà utilisés dans ce projet.
- **Conséquences :** détruire ou reconstruire le réseau `dev` n'affecte jamais l'accès de la CI. `scripts/validate.sh` valide désormais tous les environnements sous `terraform/environments/*/`, pas seulement `dev`.

## ADR-017 : rôle IAM OIDC restreint au dépôt, en lecture seule, sans clé statique

- **Contexte :** la CI doit pouvoir exécuter un `terraform plan` fidèle à l'état réel du compte, sans jamais pouvoir le modifier, et sans qu'une clé d'accès AWS soit stockée dans GitHub.
- **Décision :** un fournisseur OIDC (`token.actions.githubusercontent.com`) et un rôle dont la politique de confiance vérifie `aud = sts.amazonaws.com` et restreint le claim `sub` au dépôt `Aliyoub/terraform-aws-secure-network`, à la branche `main` et aux pull requests de ce dépôt. La politique de permissions ne contient que des actions `ec2:Describe*` sur les types de ressources actuellement définis : aucune action de création, modification ou suppression.
- **Empreinte du certificat :** calculée le 22/09/2026 avec `openssl s_client -connect token.actions.githubusercontent.com:443 -showcerts`, en prenant l'empreinte SHA-1 du dernier certificat de la chaîne renvoyée par le serveur. Ma première tentative, écrite de mémoire, était fausse (39 caractères au lieu de 40) : `terraform validate` l'a détectée avant tout appel AWS, ce qui illustre l'intérêt de ce contrôle.
- **Conséquences :** un fork du dépôt ou un autre dépôt ne peut pas endosser ce rôle. La liste d'actions doit être étendue au fur et à mesure des ressources ajoutées (jamais par anticipation). Le rôle ne permet aucun `apply`, en CI ou ailleurs : cette limite reste humaine.

### Incident : premier claim "sub" incorrect, corrigé après le premier run CI

Le premier déploiement (22/09/2026) restreignait `sub` au format simple `repo:Aliyoub/terraform-aws-secure-network:...`. Le premier run du workflow `terraform-plan` a échoué : `Not authorized to perform sts:AssumeRoleWithWebIdentity`.

**Diagnostic :** une recherche dans CloudTrail (région `eu-west-3`, événements `AssumeRoleWithWebIdentity`, en lecture seule avec mes propres identifiants) a montré le claim réellement envoyé par GitHub : `repo:Aliyoub@25158336/terraform-aws-secure-network@1378078820:ref:refs/heads/main`. La documentation GitHub officielle confirme la cause : *« For repositories created after July 15, 2026 [...] the sub claim includes immutable owner and repository IDs »* ([oidc-in-aws](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)). Ce dépôt a été créé le 20/09/2026, donc après cette bascule.

**Correction :** le module `github-oidc` accepte désormais `github_owner_id` et `github_repository_id` (optionnels), qui qualifient le claim `sub` avec les identifiants immuables quand ils sont fournis. Les valeurs utilisées (`25158336`, `1378078820`) ont été vérifiées par deux sources indépendantes : l'API GitHub (`gh api repos/.../... --jq '{owner_id:.owner.id, repo_id:.id}'`) et l'observation directe dans CloudTrail. `terraform apply` n'a modifié que la politique de confiance (0 création, 1 modification, 0 suppression). Le run suivant du workflow a réussi.

**Leçon retenue :** vérifier le format réel du claim `sub` (CloudTrail ou un test manuel) avant de déployer une politique de confiance OIDC pour un nouveau dépôt, plutôt que de supposer le format documenté historiquement.

## ADR-018 : `terraform-plan.yml`, ses limites assumées et ses garde-fous

- **Contexte :** le state de `dev` est local et jamais partagé avec la CI (ADR-003). Un `terraform plan` lancé sur un checkout GitHub neuf repart donc toujours d'un state vide.
- **Décision et limite assumée :** le workflow plan quand même `dev`, mais **n'affichera jamais une vraie dérive** : il montrera systématiquement les ressources comme "à créer", qu'elles existent déjà sur AWS ou non. Sa valeur réelle est de confirmer que la configuration reste déployable contre le vrai compte (résolution des data sources comme `aws_availability_zones`, région correcte, permissions suffisantes), ce qu'un `terraform validate` local ne peut pas garantir puisqu'il ne contacte jamais AWS. Ne pas confondre ce plan avec une détection de dérive : un vrai `plan` de dérive demanderait un backend distant partagé (S3 + verrouillage), non mis en place à ce stade (ADR-003).
- **Portée :** seul `dev` est planifié. `bootstrap` ne l'est pas : le rôle OIDC n'a que des permissions `ec2:Describe*` (ADR-017), pas les permissions IAM nécessaires pour lire ses propres ressources. Étendre ces permissions serait un changement d'infrastructure à part entière, nécessitant sa propre autorisation.
- **Défense en profondeur pour les pull requests :** en plus de la restriction `sub` de la politique de confiance IAM, le job est gardé par une condition qui exclut les pull requests dont le dépôt de tête diffère du dépôt principal (`github.event.pull_request.head.repo.full_name == github.repository`). Une pull request depuis un fork ne peut donc jamais déclencher l'obtention de credentials AWS, même si GitHub restreint déjà par défaut les jetons OIDC pour ce cas.
- **ARN du rôle en variable de dépôt, pas dans le code :** `vars.AWS_OIDC_PLAN_ROLE_ARN`, définie sur GitHub plutôt qu'écrite en dur dans le workflow. Cela permet de faire tourner le rôle (par ex. le recréer) sans modifier le code, et évite de coupler la définition de l'infrastructure à sa consommation. L'ARN n'est pas un secret exploitable seul (la politique de confiance protège l'usage du rôle), mais `mask-aws-account-id: true` masque quand même l'ID de compte dans les logs du workflow, par cohérence avec le masquage appliqué aux captures.
