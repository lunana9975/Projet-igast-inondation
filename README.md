Analyse de la vulnérabilité aux inondations – Normandie

Objectif:
Ce projet propose une méthode pour évaluer la vulnérabilité de sites face au risque d’inondation à l’aide de PostgreSQL/PostGIS.

Contenu:
calcul_indicateurs.sql : script principal
data/ : données et documentation

Données:
À importer (disponibles dans le dépôt):
sites fictifs
aléa inondation
cours d’eau
À importer (non fournies dans formation temp):
bâtiments (BD TOPO)
MNT (RGE ALTI)

Utilisation:
Créer une base de données PostgreSQL avec PostGIS
Importer les données (sites fictifs, aléa inondation, cours d’eau, ainsi que bâtiments et MNT)
Lancer le script calcul_indicateurs.sql

Résultat:
Les indicateurs sont calculés dans la table proj.site_enrichi.
