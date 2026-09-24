# Analyse des coûts

**Région :** `eu-west-3` (Europe, Paris)
**Date de vérification :** 23/09/2026
**Source :** API officielle AWS Price List (`aws pricing get-products`, région d'interrogation `us-east-1`, lecture seule, aucun coût). Les prix affichés sur les pages marketing `aws.amazon.com/*/pricing/` ne détaillent pas toujours la région Paris dans leur rendu statique ; l'API renvoie les tarifs réels par région.
**Unité de facturation :** USD, hors taxes. Les prix AWS changent : à revérifier avant toute décision financière importante, en particulier si ce document a plus de quelques mois.

## Ressources de ce projet, actuellement gratuites

Ces types de ressources sont déployés (ou l'ont été) dans ce projet et ne sont facturés à aucun tarif AWS connu :

| Ressource | Utilité | Coût |
|---|---|---|
| VPC | Réseau privé virtuel | Gratuit |
| Subnet | Segmentation du VPC | Gratuit |
| Internet Gateway | Sortie/entrée Internet pour les subnets publics | Gratuit (attachement et présence) |
| Table de routage, route | Routage interne au VPC | Gratuit |
| Security Group, règle | Pare-feu stateful | Gratuit |
| Network ACL (par défaut) | Pare-feu stateless au niveau subnet | Gratuit |
| VPC Gateway Endpoint (S3, DynamoDB) | Accès privé à S3/DynamoDB sans sortie Internet | Gratuit (pas de frais horaire ni de traitement, contrairement aux Interface Endpoints ci-dessous) |
| Fournisseur OIDC IAM | Authentification de la CI | Gratuit |
| Rôle IAM, politique IAM | Permissions | Gratuit (IAM est gratuit : *« IAM is offered at no additional charge »*, FAQ AWS IAM, vérifié en Phase 7) |

## Ressources potentiellement payantes (non déployées par défaut)

| Ressource | Utilité | Coût potentiel (eu-west-3) | Niveau de risque | Suppression |
|---|---|---|---|---|
| **NAT Gateway** | Sortie Internet pour un subnet privé | **0,05 $/heure** (≈ 36 $/mois si laissé 30 jours) **+ 0,05 $/Go traité** | Élevé — facturé même sans trafic, coût continu si oublié | `terraform destroy` ou suppression manuelle de la NAT Gateway (libère aussi l'Elastic IP associée) |
| **Elastic IP (IPv4 publique)** | Adresse IP publique fixe | **0,005 $/heure** par adresse, **qu'elle soit attachée ou non** (tarif uniforme sur toutes les régions commerciales AWS depuis février 2024, page officielle `aws.amazon.com/vpc/pricing/`) | Moyen — facturé même inutilisée, facile à oublier | Libérer l'adresse (`release`) dès qu'elle n'est plus utilisée |
| **VPC Interface Endpoint** | Accès privé à un service AWS (ex. SSM) sans NAT | **0,011 $/heure** par endpoint et par AZ **+ 0,01 $/Go** traité | Moyen — multiplié par le nombre d'AZ et d'endpoints | `terraform destroy` de l'endpoint |
| **Application Load Balancer (ALB)** | Répartition de charge HTTP/HTTPS | **0,02646 $/heure** (≈ 19 $/mois) **+ 0,0084 $/LCU-heure** (capacité utilisée) | Élevé — coût continu dès la création | `terraform destroy` de l'ALB |
| **EC2 `t3.micro` (Linux, à la demande)** | Instance applicative minimale | **0,0118 $/heure** (≈ 8,50 $/mois) | Moyen — dépend de la durée d'exécution | Terminer l'instance |
| **RDS PostgreSQL `db.t4g.micro` (Single-AZ)** | Base de données managée minimale | **0,018 $/heure** (≈ 13 $/mois), hors stockage et sauvegardes | Moyen à élevé — instance + stockage + sauvegardes se cumulent | Supprimer l'instance (désactiver la suppression de snapshot final si un snapshot n'est pas voulu) |
| **VPC Flow Logs → CloudWatch Logs** | Journalisation du trafic réseau | **0,50 $/Go ingéré** (10 premiers To/mois) **+ 0,0315 $/Go-mois** de stockage | Faible à moyen selon le volume de trafic | Désactiver les Flow Logs, supprimer le groupe de logs et son contenu |

*LCU = Load Balancer Capacity Unit, unité de facturation de la capacité utilisée par un ALB (combine connexions, bande passante et évaluations de règles).*

## Estimation d'un mois de test (hypothèse, non un engagement)

Exemple purement illustratif si toutes les extensions de la Phase 11 étaient activées simultanément pendant un mois complet (30 jours) :

| Ressource | Calcul | Coût mensuel approximatif |
|---|---|---|
| 1 NAT Gateway (usage minimal) | 0,05 $ × 24 × 30 | ≈ 36 $ |
| 1 Elastic IP (associée au NAT) | 0,005 $ × 24 × 30 | ≈ 3,60 $ |
| 1 ALB (trafic minimal) | 0,02646 $ × 24 × 30 | ≈ 19 $ |
| 1 EC2 `t3.micro` | 0,0118 $ × 24 × 30 | ≈ 8,50 $ |
| 1 RDS `db.t4g.micro` | 0,018 $ × 24 × 30 | ≈ 13 $ |
| **Total approximatif** | | **≈ 80 $/mois** |

Ce total ne compte pas le trafic de données, le stockage EBS/RDS, ni les sauvegardes, qui s'ajoutent selon l'usage. **Il ne sera jamais atteint dans ce projet** : chaque extension suit le principe « capture puis cleanup », déployée quelques minutes pour une preuve, puis détruite et vérifiée.

## Alternatives moins coûteuses, par besoin

| Besoin | Option coûteuse | Alternative | Compromis |
|---|---|---|---|
| Sortie Internet pour un subnet privé | NAT Gateway (0,05 $/h) | NAT instance (EC2 `t3.micro` ≈ 0,0118 $/h) | Moins cher mais à maintenir et sécuriser soi-même (patchs, haute disponibilité) |
| Sortie Internet pour un subnet privé | NAT Gateway | VPC Gateway Endpoints (S3, DynamoDB, **gratuits**) | Ne couvre que les services compatibles Gateway Endpoint, pas une sortie Internet générale |
| Accès SSM à une instance privée | VPC Interface Endpoints (0,011 $/h × 3 endpoints mini) | NAT Gateway si déjà présent pour un autre besoin | Mutualise un coût déjà engagé plutôt que d'en ajouter un nouveau |
| Exposition HTTP(S) | Application Load Balancer (0,02646 $/h) | Exposer directement une instance avec IP publique et Security Group restrictif | Moins résilient, pas de répartition de charge ; acceptable pour une démonstration ponctuelle |
| Base de données | RDS (0,018 $/h + stockage) | Free Tier RDS si éligible (à vérifier sur le compte, ADR : ne jamais supposer son éligibilité, section 1 des règles du projet) | Le Free Tier RDS ne s'applique qu'aux nouveaux comptes et pour une durée limitée |

## Coût réel de la démonstration des 6 extensions (24/09/2026)

Contrairement à l'estimation illustrative ci-dessus (toutes les extensions actives un mois complet), voici le calcul basé sur la durée réelle de vie de chaque ressource, du déploiement (construction progressive, une extension ajoutée toutes les 20-40 minutes) au cleanup final terminé à 14h43 :

| Extension | Créée vers (proxy : heure de la capture) | Détruite | Durée approximative | Coût approximatif |
|---|---|---|---|---|
| VPC Endpoints (×3) | 12h20 | 14h43 | ≈ 2,4 h | 0,011 $ × 3 × 2,4 ≈ **0,08 $** |
| EC2 `t3.micro` | 12h41 | 14h43 | ≈ 2,0 h | 0,0118 $ × 2,0 ≈ **0,02 $** |
| NAT Gateway + EIP | 13h15 | 14h43 | ≈ 1,5 h | (0,05 $ + 0,005 $) × 1,5 ≈ **0,08 $** |
| ALB | 13h30 | 14h43 | ≈ 1,2 h | 0,02646 $ × 1,2 ≈ **0,03 $** |
| RDS `db.t4g.micro` | 14h12 | 14h43 | ≈ 0,5 h | 0,018 $ × 0,5 ≈ **0,01 $** |
| VPC Flow Logs | 14h31 | 14h43 | ≈ 0,2 h | volume négligeable (183 Ko scannés) ≈ **0,00 $** |
| **Total approximatif** | | | | **≈ 0,22 $** |

**Méthode et limites de cette estimation :** les heures de création utilisent l'horodatage des captures d'écran comme approximation (la ressource existait déjà quelques minutes avant, le temps de la tester) ; l'heure de destruction utilise l'horodatage de fin du log `terraform destroy` du cleanup final. Ce n'est **pas** un relevé de facturation AWS réel — la facturation AWS elle-même a un délai de plusieurs heures et facture au minimum à l'heure pleine pour certaines ressources (NAT Gateway, ALB, RDS, EC2 sont facturés à la seconde depuis 2017 après le premier minimum, mais toujours arrondis par AWS selon ses propres règles). Non vérifié : le montant exact qui apparaîtra sur la facture AWS Billing du compte pour cette période. Cette estimation confirme néanmoins l'ordre de grandeur annoncé (bien en dessous de 1 $), largement plus bas que le total mensuel illustratif ci-dessus, précisément parce que chaque extension n'a vécu que le temps de sa démonstration.

## Ce qui n'a pas été vérifié aujourd'hui

- La tarification exacte de l'Elastic IP n'a pas pu être confirmée via l'API Price List pour `eu-west-3` spécifiquement (la requête est devenue trop volumineuse pour être traitée de façon fiable). Le chiffre cité (0,005 $/heure) vient de la page officielle `aws.amazon.com/vpc/pricing/`, qui précise explicitement que ce tarif s'applique à toutes les régions commerciales AWS.
- Le stockage EBS, les sauvegardes RDS au-delà du stockage alloué, et le trafic sortant vers Internet (data transfer OUT) n'ont pas été chiffrés ici : ils dépendent trop du scénario pour une estimation utile sans cas d'usage précis.
- Les prix Reserved/Savings Plans n'ont pas été explorés : sans objet pour un projet de démonstration à usage intermittent.
