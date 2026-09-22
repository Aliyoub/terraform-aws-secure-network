# Sécurité

> Document en construction. Cette version couvre les Security Groups et l'isolation réseau (Phases 3 et 4). L'authentification de la CI (OIDC), les permissions IAM et la chaîne d'approvisionnement seront ajoutées avec les phases correspondantes.

## Principes

- **Moindre privilège :** rien n'est ouvert par défaut ; chaque règle est explicite et justifiée.
- **Défense en profondeur :** trois couches se cumulent pour exposer une ressource : la route vers l'Internet Gateway, une IP publique, et un Security Group qui autorise le trafic (voir `ARCHITECTURE.md`).
- **Sûr par défaut :** la table de routage principale et le groupe de sécurité par défaut du VPC sont gérés et vides (ADR-008, ADR-012).

## Security Groups

Les groupes forment une chaîne `alb -> app -> db`. Un **Security Group est stateful** : la réponse à une connexion autorisée est acceptée automatiquement, sans règle pour le retour.

| Groupe | Entrant | Sortant | Justification |
|---|---|---|---|
| `alb` | HTTPS (443) depuis les CIDR de `alb_allowed_https_cidrs` : **aucun par défaut** | Port applicatif (8080) vers le groupe `app` | Point d'entrée public optionnel, fermé tant qu'on ne l'ouvre pas |
| `app` | Port applicatif (8080) **depuis le groupe `alb` uniquement** | Port base de données (5432) vers le groupe `db` | L'application n'est joignable que par le load balancer |
| `db` | Port base de données (5432) **depuis le groupe `app` uniquement** | **Aucun** | La base ne reçoit que de l'application et n'initie aucune connexion |
| défaut du VPC | Aucun | Aucun | Une ressource sans groupe explicite n'a aucun accès réseau |

- **Références plutôt que CIDR :** une règle du type « depuis le groupe `alb` » suit les ressources, pas leurs adresses. Elle reste correcte si les IP changent et ne peut pas être élargie par erreur à un réseau entier.
- **Aucun SSH :** aucune règle sur le port 22. Le module refuse à la validation tout SSH ou RDP ouvert à `0.0.0.0/0` et toute règle entrante « tous protocoles » (ADR-011).
- **Administration :** AWS Systems Manager Session Manager, sans port entrant ni clé SSH. Il nécessite des VPC endpoints pour un subnet privé sans NAT (coût à évaluer en Phase 11).
- **Sorties restreintes :** l'usage habituel d'un `0.0.0.0/0` en sortie est volontairement absent. Sans NAT, un subnet privé n'a de toute façon aucune route vers Internet ; les règles sortantes limitent en plus le trafic *interne*.

## Security Group ou Network ACL ?

| | Security Group | Network ACL |
|---|---|---|
| Niveau | Interface réseau (ressource) | Subnet |
| État | **Stateful** (retour automatique) | **Stateless** (retour à autoriser, ports éphémères 1024-65535) |
| Règles | Autorisation uniquement | Autorisation **et** refus, évaluées par numéro |
| Référence à un autre groupe | Oui | Non (CIDR uniquement) |
| Usage dans ce projet | Segmentation principale | Non personnalisée (NACL par défaut conservée) |

Une NACL personnalisée n'apporte pas ici de bénéfice qui justifie sa complexité. Elle deviendrait pertinente pour bloquer explicitement une plage d'adresses, ce qu'un Security Group ne sait pas faire (ADR-012).

## Security trade-offs

| Choix | Bénéfice | Compromis accepté |
|---|---|---|
| Aucun accès Internet sortant depuis les subnets privés | Pas d'exfiltration ni de sortie non maîtrisée, pas de coût NAT | Les ressources privées ne peuvent pas atteindre Internet ni les API AWS sans NAT ou endpoints |
| Aucun SSH | Surface d'attaque réduite, pas de clés à gérer | Dépend de Session Manager, donc d'endpoints payants pour un subnet privé |
| Pas de NACL personnalisée | Simplicité, moins d'erreurs possibles | Pas de blocage explicite d'adresses au niveau subnet |
| Groupes `alb` et `db` créés sans ressource associée | Modèle d'accès documenté et prêt | Groupes inutilisés tant que l'ALB et la base ne sont pas déployés |
| State Terraform local | Pas de bucket à sécuriser à ce stade | Pas de verrouillage ni de partage (ADR-003) |

## Contrôles avant commit

![Exécution de scripts/validate.sh : les cinq contrôles réussissent](../screenshots/02-validate-script.png)

*Terminal, exécution de `scripts/validate.sh` à la racine du dépôt.*

**Ce que montre la capture.** Le script enchaîne cinq contrôles, tous en `OK`, puis affiche « tous les contrôles sont passés » :

| Étape | Contrôle | Ce qu'il évite |
|---|---|---|
| 1 | `terraform fmt -check` | Un formatage incohérent qui pollue les revues de code |
| 2 | `terraform init -backend=false` puis `validate` | Une configuration invalide ou incohérente |
| 3 | `tflint` (règles Terraform et AWS) | Des erreurs de fond que `validate` ne voit pas : valeur refusée par AWS, variable inutilisée, module non épinglé |
| 4 | Garde-fou de coût | L'ajout accidentel d'une ressource payante (NAT Gateway, Elastic IP, load balancer, instance, base, etc.) |
| 5 | Recherche de secrets | Un fichier de state, un `.tfvars`, une clé privée ou une clé d'accès AWS suivis par Git |

**Pourquoi cette configuration.** Ces contrôles ne font aucun appel AWS et ne créent aucune ressource : ils peuvent être rejoués sans risque de coût, à chaque commit, et par la CI. Le garde-fou de coût rend visible toute ressource facturable dès la revue du code, avant même un `plan`. L'analyse de `tflint` complète `validate`, qui n'avait pas détecté l'usage d'une fonction inexistante (ADR-007).

**Ce que ce script ne garantit pas.** La recherche de secrets ne repose que sur quelques motifs (clé d'accès AWS, clé secrète, clé privée) : elle ne remplace pas un véritable scanner. Le garde-fou de coût est une analyse statique du code : il ne vérifie ni les tarifs ni ce qui existe réellement sur le compte. Un `terraform plan` reste nécessaire avant tout déploiement.

**Bonne pratique illustrée.** Des contrôles automatisés et reproductibles « à gauche » (avant le commit) plutôt qu'une découverte tardive en production, et des contrôles eux-mêmes testés avec des cas défectueux pour prouver qu'ils échouent quand il le faut (ADR-014).

## GitHub Actions : permissions et chaîne d'approvisionnement

Le workflow `terraform-validate` applique ces règles (ADR-015) :

| Mesure | Effet |
|---|---|
| `permissions: contents: read` | Le jeton du workflow ne peut que lire le code : il ne peut ni pousser, ni modifier les pull requests, ni créer de release |
| Aucun secret, aucun accès AWS | Un workflow compromis ne peut ni créer, ni lire de ressources AWS |
| `persist-credentials: false` | Le jeton n'est pas laissé dans la configuration Git du runner |
| Actions épinglées sur un SHA de commit | Une action tierce dont le tag serait détourné ne peut pas injecter de code dans la CI |
| Versions de Terraform et de tflint fixées | Les mêmes règles s'appliquent à chaque exécution |
| `terraform init -lockfile=readonly` | Le provider ne peut pas changer sans modification visible de `.terraform.lock.hcl` |
| Aucun `terraform apply` | La CI ne peut rien déployer |

**Limite :** l'épinglage par SHA protège contre le déplacement d'un tag, pas contre une action déjà malveillante au moment où on l'épingle. Le SHA doit être relu à chaque mise à jour.
