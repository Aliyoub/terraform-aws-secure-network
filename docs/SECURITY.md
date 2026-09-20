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
