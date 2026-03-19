Données du projet
Fichiers disponibles dans ce dépôt
Le dépôt contient les principales données utilisées pour l’analyse.
Sites fictifs
Quatre polygones ont été créés pour simuler des sites et tester la méthodologie :
sites_fictifs.shp
sites_fictifs.dbf
sites_fictifs.shx
sites_fictifs.prj

Aléa inondation
Données issues du portail Geo-IDE Normandie (PPRI / AZI), utilisées pour identifier les zones exposées.
alea_inondation.shp
alea_inondation.dbf
alea_inondation.shx
alea_inondation.prj

Cours d’eau
Données extraites de la BD TOPO (IGN), représentant le réseau hydrographique.
cours_deau.shp
cours_deau.dbf
cours_deau.shx
cours_deau.prj

Format des données : Shapefile
Système de coordonnées : Lambert 93 (EPSG:2154)

Données non incluses
Certaines données ne sont pas présentes dans le dépôt en raison de leur volume.
Disponibles sur le serveur de formation temp.
Bâtiments (BD TOPO) MNT (RGE ALTI 1 m)


Importer le raster dans le cmd AVANT d'effectuer les requetes pente et altitude:
raster2pgsql -s 2154 -I -C -M -t 100x100  "D:\Chemin_d'acces_fichier\MNT.tif" schemas.nom_table | psql -d Nom_base -U postgres


