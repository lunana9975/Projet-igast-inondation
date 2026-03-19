Analyse de la vulnérabilité aux inondations – Normandie

Projet universitaire réalisé à Géodata Paris (2025–2026)

📋 Objectif

L’objectif de ce projet est de proposer une méthode pour évaluer la vulnérabilité de sites logistiques face au risque d’inondation.

L’analyse est réalisée avec PostgreSQL et PostGIS à partir de plusieurs données géographiques (aléa, MNT, bâtiments, cours d’eau).

📂 Contenu du dépôt
Projet/
├── calcul_indicateurs.sql   # Script principal
└── data/                    # Données et instructions

calcul_indicateurs.sql : script SQL permettant de calculer les indicateurs

data/ : contient les données légères (sites fictifs, etc.) et les instructions pour récupérer les autres

📦 Données
Disponibles dans le dépôt

Sites fictifs

Aléa inondation

Cours d’eau

À récupérer

Bâtiments (BD TOPO)

MNT (RGE ALTI 1 m)

👉 Voir data/README.md pour les détails

Toutes les données doivent être en Lambert 93 (EPSG:2154).

🚀 Utilisation
1. Créer la base de données
createdb analyse_vulnerabilite
psql -d analyse_vulnerabilite -c "CREATE EXTENSION postgis;"
psql -d analyse_vulnerabilite -c "CREATE EXTENSION postgis_raster;"
psql -d analyse_vulnerabilite -c "CREATE SCHEMA proj;"
2. Importer les données

Importer les différentes couches (sites, aléa, cours d’eau, bâtiments, MNT).
Les commandes sont précisées dans data/README.md.

3. Lancer le script
psql -d analyse_vulnerabilite -f calcul_indicateurs.sql
📊 Résultats

Les résultats sont enregistrés dans la table :

proj.site_enrichi

Elle contient plusieurs indicateurs liés :

à l’exposition aux inondations

au relief (altitude, pente)

à la proximité des cours d’eau

à la présence de bâtiments

⚠️ Remarques

Les sites utilisés sont fictifs (projet méthodologique)

Certaines données ne sont pas fournies car trop volumineuses

Le temps de calcul dépend des données utilisées

👥 Auteurs

Karine Anaïs Imadalou
Luna Roca
