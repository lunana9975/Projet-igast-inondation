-- SCHEMA: public

-- DROP SCHEMA IF EXISTS public ;

-- ============================================================
-- ANALYSE DE VULNÉRABILITÉ DES SITES LOGISTIQUES AUX INONDATIONS
-- Projet : CEREMA Normandie
-- Auteurs : Karine Anaïs Imadalou, Luna Roca
-- Encadrement : J. Raimbault, C. Duchêne (Géodata Paris)
-- Date : 2026-03
-- ============================================================

-- Ce script calcule 19 indicateurs de vulnérabilité pour des sites logistiques :
-- - 6 indicateurs d'exposition à l'aléa inondation
-- - 3 indicateurs altimétriques
-- - 4 indicateurs de pente
-- - 5 indicateurs de contexte bâti
-- - 1 indicateur de distance aux cours d'eau

-- PRÉREQUIS :
-- - PostgreSQL 12+ avec PostGIS 3.0+
-- - Extension PostGIS Raster activée
-- - Tables importées : proj.site_fictif, proj.alea_inondation, 
--   proj.cours_deau, proj.bdtopo_bati, proj.mnt

BEGIN;

-- ============================================================
-- ÉTAPE 0 : CONFIGURATION ET NETTOYAGE
-- ============================================================

SET search_path TO proj, public;

-- Correction des géométries invalides
UPDATE proj.site_fictif SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);
UPDATE proj.alea_inondation SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);
UPDATE proj.bdtopo_bati SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);

-- Création des index spatiaux
CREATE INDEX IF NOT EXISTS site_fictif_gix ON proj.site_fictif USING GIST (geom);
CREATE INDEX IF NOT EXISTS alea_inondation_gix ON proj.alea_inondation USING GIST (geom);
CREATE INDEX IF NOT EXISTS cours_deau_gix ON proj.cours_deau USING GIST (geom);
CREATE INDEX IF NOT EXISTS bdtopo_bati_gix ON proj.bdtopo_bati USING GIST (geom);

ANALYZE proj.site_fictif;
ANALYZE proj.alea_inondation;
ANALYZE proj.cours_deau;
ANALYZE proj.bdtopo_bati;

-- Suppression des tables temporaires existantes
DROP TABLE IF EXISTS proj.site_enrichi CASCADE;
DROP TABLE IF EXISTS proj.site_enrichi_dist CASCADE;
DROP TABLE IF EXISTS proj.site_alea_intersections_ranked CASCADE;
DROP TABLE IF EXISTS proj.site_alea_agg CASCADE;
DROP TABLE IF EXISTS proj.site_alea_max CASCADE;
DROP TABLE IF EXISTS proj.site_bati_agg CASCADE;
DROP TABLE IF EXISTS proj.mnt_slope CASCADE;


-- ============================================================
-- ÉTAPE 1 : INDICATEURS INONDATION
-- ============================================================

-- 1.1 Normalisation des niveaux d'aléa
DROP VIEW IF EXISTS proj.v_alea_inondation_norm;
CREATE VIEW proj.v_alea_inondation_norm AS
SELECT
  a.*,
  CASE
    WHEN a.lb_classem ILIKE '%derrière un ouvrage%' OR a.lb_classem ILIKE '%derriere un ouvrage%' THEN 'derriere_ouvrage'
    WHEN a.lb_classem ILIKE '%très fort%' OR a.lb_classem ILIKE '%tres fort%' THEN 'tres_fort'
    WHEN a.lb_classem ILIKE '%fort%' THEN 'fort'
    WHEN a.lb_classem ILIKE '%moyen%' THEN 'moyen'
    WHEN a.lb_classem ILIKE '%faible%' OR a.lb_classem ILIKE '%indétermin%' OR a.lb_classem ILIKE '%indetermin%' THEN 'faible'
    ELSE NULL
  END AS intensite_norm,
  CASE
    WHEN a.lb_classem ILIKE '%derrière un ouvrage%' OR a.lb_classem ILIKE '%derriere un ouvrage%' THEN 4
    WHEN a.lb_classem ILIKE '%très fort%' OR a.lb_classem ILIKE '%tres fort%' THEN 4
    WHEN a.lb_classem ILIKE '%fort%' THEN 3
    WHEN a.lb_classem ILIKE '%moyen%' THEN 2
    WHEN a.lb_classem ILIKE '%faible%' OR a.lb_classem ILIKE '%indétermin%' OR a.lb_classem ILIKE '%indetermin%' THEN 1
    ELSE 0
  END AS int_rank
FROM proj.alea_inondation a;

-- 1.2 Distance minimale au cours d'eau (KNN)
CREATE TABLE proj.site_enrichi_dist AS
SELECT
  s.id AS site_id,
  s.geom,
  (
    SELECT ST_Distance(s.geom, r.geom)
    FROM proj.cours_deau r
    ORDER BY s.geom <-> r.geom
    LIMIT 1
  ) AS dist_coursdeau_m
FROM proj.site_fictif s;

CREATE INDEX IF NOT EXISTS site_enrichi_dist_gix ON proj.site_enrichi_dist USING GIST (geom);
CREATE INDEX IF NOT EXISTS site_enrichi_dist_site_idx ON proj.site_enrichi_dist(site_id);
ANALYZE proj.site_enrichi_dist;

-- 1.3 Calcul des intersections site × aléa
CREATE TABLE proj.site_alea_intersections_ranked AS
WITH inter AS (
  SELECT
    s.id AS site_id,
    a.lb_classem,
    a.intensite_norm,
    a.int_rank,
    ST_Intersection(s.geom, a.geom) AS inter_raw
  FROM proj.site_fictif s
  JOIN proj.v_alea_inondation_norm a
    ON ST_Intersects(s.geom, a.geom)
  WHERE a.int_rank > 0
)
SELECT
  site_id,
  lb_classem,
  intensite_norm,
  int_rank,
  ST_Multi(inter_raw) AS inter_geom,
  ST_Area(inter_raw) AS inter_area_m2
FROM inter
WHERE NOT ST_IsEmpty(inter_raw);

CREATE INDEX IF NOT EXISTS site_alea_intersections_ranked_site_idx ON proj.site_alea_intersections_ranked(site_id);
CREATE INDEX IF NOT EXISTS site_alea_intersections_ranked_gix ON proj.site_alea_intersections_ranked USING GIST (inter_geom);
ANALYZE proj.site_alea_intersections_ranked;

-- 1.4 Agrégation des indicateurs par site
CREATE TABLE proj.site_alea_agg AS
WITH sa AS (
  SELECT id AS site_id, ST_Area(geom) AS site_area_m2
  FROM proj.site_fictif
),
agg AS (
  SELECT
    i.site_id,
    SUM(i.inter_area_m2) AS flood_area_m2,
    SUM(CASE WHEN i.int_rank = 1 THEN i.inter_area_m2 ELSE 0 END) AS a_faible,
    SUM(CASE WHEN i.int_rank = 2 THEN i.inter_area_m2 ELSE 0 END) AS a_moyen,
    SUM(CASE WHEN i.int_rank = 3 THEN i.inter_area_m2 ELSE 0 END) AS a_fort,
    SUM(CASE WHEN i.intensite_norm = 'tres_fort' THEN i.inter_area_m2 ELSE 0 END) AS a_tres_fort,
    SUM(CASE WHEN i.intensite_norm = 'derriere_ouvrage' THEN i.inter_area_m2 ELSE 0 END) AS a_derriere_ouvrage,
    MAX(i.int_rank) AS max_int_rank
  FROM proj.site_alea_intersections_ranked i
  GROUP BY i.site_id
)
SELECT
  sa.site_id,
  COALESCE(agg.flood_area_m2,0) AS flood_area_m2,
  CASE WHEN COALESCE(agg.flood_area_m2,0) > 0 THEN 1 ELSE 0 END AS in_flood_zone,
  ROUND((LEAST(1.0, GREATEST(0.0, COALESCE(agg.flood_area_m2,0) / NULLIF(sa.site_area_m2,0))))::numeric, 4) AS pct_overlap,
  COALESCE(ROUND((COALESCE(agg.a_faible,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_faible,
  COALESCE(ROUND((COALESCE(agg.a_moyen,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_moyen,
  COALESCE(ROUND((COALESCE(agg.a_fort,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_fort,
  COALESCE(ROUND((COALESCE(agg.a_tres_fort,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_tres_fort,
  COALESCE(ROUND((COALESCE(agg.a_derriere_ouvrage,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_derriere_ouvrage,
  (COALESCE(ROUND((COALESCE(agg.a_tres_fort,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) +
   COALESCE(ROUND((COALESCE(agg.a_derriere_ouvrage,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0)) AS pct_tres_fort_effectif,
  CASE agg.max_int_rank
    WHEN 4 THEN 'tres_fort'
    WHEN 3 THEN 'fort'
    WHEN 2 THEN 'moyen'
    WHEN 1 THEN 'faible'
    ELSE NULL
  END AS max_intensite,
  CASE agg.max_int_rank
    WHEN 4 THEN (COALESCE(ROUND((COALESCE(agg.a_tres_fort,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) +
                 COALESCE(ROUND((COALESCE(agg.a_derriere_ouvrage,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0))
    WHEN 3 THEN COALESCE(ROUND((COALESCE(agg.a_fort,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0)
    WHEN 2 THEN COALESCE(ROUND((COALESCE(agg.a_moyen,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0)
    WHEN 1 THEN COALESCE(ROUND((COALESCE(agg.a_faible,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0)
    ELSE 0
  END AS pct_alea_max
FROM sa
LEFT JOIN agg ON agg.site_id = sa.site_id;

CREATE INDEX IF NOT EXISTS site_alea_agg_site_idx ON proj.site_alea_agg(site_id);
ANALYZE proj.site_alea_agg;

-- 1.5 Géométrie de la zone d'aléa maximum
CREATE TABLE proj.site_alea_max AS
WITH m AS (
  SELECT site_id, MAX(int_rank) AS max_rank
  FROM proj.site_alea_intersections_ranked
  GROUP BY site_id
)
SELECT
  r.site_id,
  m.max_rank,
  CASE m.max_rank
    WHEN 4 THEN 'tres_fort'
    WHEN 3 THEN 'fort'
    WHEN 2 THEN 'moyen'
    WHEN 1 THEN 'faible'
    ELSE NULL
  END AS max_intensite,
  ST_UnaryUnion(ST_Collect(r.inter_geom)) AS max_int_geom,
  ST_Area(ST_UnaryUnion(ST_Collect(r.inter_geom))) AS max_int_area_m2
FROM proj.site_alea_intersections_ranked r
JOIN m ON m.site_id = r.site_id AND r.int_rank = m.max_rank
GROUP BY r.site_id, m.max_rank;

CREATE INDEX IF NOT EXISTS site_alea_max_gix ON proj.site_alea_max USING GIST (max_int_geom);
CREATE INDEX IF NOT EXISTS site_alea_max_site_idx ON proj.site_alea_max(site_id);
ANALYZE proj.site_alea_max;


-- ============================================================
-- ÉTAPE 2 : INDICATEURS ALTIMÉTRIQUES
-- ============================================================

-- Calcul des statistiques d'altitude (min, max, moyenne)
-- Nécessite que le MNT soit importé dans proj.mnt via raster2pgsql

ALTER TABLE proj.site_fictif
ADD COLUMN IF NOT EXISTS altitude_min double precision,
ADD COLUMN IF NOT EXISTS altitude_max double precision,
ADD COLUMN IF NOT EXISTS altitude_moyenne double precision;

WITH altitude_stats AS (
  SELECT
    s.id AS site_id,
    (stats).min AS altitude_min,
    (stats).max AS altitude_max,
    (stats).mean AS altitude_moyenne
  FROM (
    SELECT
      s.id,
      ST_SummaryStats(ST_Clip(ST_Union(r.rast), s.geom)) AS stats
    FROM proj.site_fictif s
    JOIN proj.mnt r ON ST_Intersects(r.rast, s.geom)
    GROUP BY s.id, s.geom
  ) AS s
)
UPDATE proj.site_fictif sf
SET
  altitude_min = a.altitude_min,
  altitude_max = a.altitude_max,
  altitude_moyenne = a.altitude_moyenne
FROM altitude_stats a
WHERE sf.id = a.site_id;


-- ============================================================
-- ÉTAPE 3 : INDICATEURS DE PENTE
-- ============================================================

-- 3.1 Calcul du raster de pente à partir du MNT
CREATE TABLE proj.mnt_slope AS
SELECT
  rid,
  ST_Slope(rast, 1, '32BF', 'PERCENT') AS rast
FROM proj.mnt;

CREATE INDEX IF NOT EXISTS mnt_slope_rast_gix ON proj.mnt_slope USING GIST (ST_ConvexHull(rast));

-- 3.2 Extraction des statistiques de pente par site
ALTER TABLE proj.site_fictif
ADD COLUMN IF NOT EXISTS slope_mean double precision,
ADD COLUMN IF NOT EXISTS slope_max double precision,
ADD COLUMN IF NOT EXISTS slope_std double precision,
ADD COLUMN IF NOT EXISTS slope_min double precision;

WITH slope_stats AS (
  SELECT
    t.site_id,
    (t.stats).min AS slope_min,
    (t.stats).mean AS slope_mean,
    (t.stats).max AS slope_max,
    (t.stats).stddev AS slope_std
  FROM (
    SELECT
      s.id AS site_id,
      ST_SummaryStats(ST_Union(ST_Clip(r.rast, s.geom, true)), 1, true) AS stats
    FROM proj.site_fictif s
    JOIN proj.mnt_slope r ON ST_Intersects(r.rast, s.geom)
    GROUP BY s.id
  ) AS t
)
UPDATE proj.site_fictif sf
SET
  slope_min = ss.slope_min,
  slope_mean = ss.slope_mean,
  slope_max = ss.slope_max,
  slope_std = ss.slope_std
FROM slope_stats ss
WHERE sf.id = ss.site_id;


-- ============================================================
-- ÉTAPE 4 : INDICATEURS BÂTIMENTS
-- ============================================================

-- 4.1 Calcul des indicateurs bâtis par site
CREATE TABLE proj.site_bati_agg AS
WITH sa AS (
  SELECT id AS site_id, geom AS site_geom, ST_Area(geom) AS site_area_m2
  FROM proj.site_fictif
),
i AS (
  SELECT
    sa.site_id,
    bt.id AS bati_id,
    ST_Area(ST_Intersection(sa.site_geom, bt.geom)) AS inter_bati_m2,
    ST_Area(bt.geom) AS bati_area_m2
  FROM sa
  JOIN proj.bdtopo_bati bt
    ON sa.site_geom && bt.geom
    AND ST_Intersects(sa.site_geom, bt.geom)
  WHERE NOT ST_IsEmpty(ST_Intersection(sa.site_geom, bt.geom))
),
agg AS (
  SELECT
    site_id,
    COUNT(*) AS nb_batiments_touchant,
    SUM(inter_bati_m2) AS surf_batie_in_site_m2,
    MAX(inter_bati_m2) AS surf_batie_piece_max_m2,
    SUM(CASE WHEN bati_area_m2 > 0 AND inter_bati_m2 / bati_area_m2 >= 0.5 THEN 1 ELSE 0 END) AS nb_batiments_majoritaires
  FROM i
  GROUP BY site_id
)
SELECT
  sa.site_id,
  COALESCE(agg.nb_batiments_touchant, 0) AS nb_batiments_touchant,
  COALESCE(agg.nb_batiments_majoritaires, 0) AS nb_batiments_majoritaires,
  COALESCE(agg.surf_batie_in_site_m2, 0) AS surf_batie_in_site_m2,
  COALESCE(agg.surf_batie_piece_max_m2, 0) AS surf_batie_piece_max_m2,
  COALESCE(ROUND((COALESCE(agg.surf_batie_in_site_m2,0) / NULLIF(sa.site_area_m2,0))::numeric * 100), 0) AS pct_surface_batie
FROM sa
LEFT JOIN agg ON agg.site_id = sa.site_id;

CREATE INDEX IF NOT EXISTS site_bati_agg_site_idx ON proj.site_bati_agg(site_id);
ANALYZE proj.site_bati_agg;


-- ============================================================
-- ÉTAPE 5 : TABLE FINALE CONSOLIDÉE
-- ============================================================

-- Création de la table site_enrichi avec tous les indicateurs
CREATE TABLE proj.site_enrichi AS
SELECT
  s.id AS site_id,
  s.geom,
  s.altitude_min,
  s.altitude_max,
  s.altitude_moyenne,
  s.slope_min,
  s.slope_mean,
  s.slope_max,
  s.slope_std
FROM proj.site_fictif s;

CREATE INDEX IF NOT EXISTS site_enrichi_gix ON proj.site_enrichi USING GIST (geom);
CREATE INDEX IF NOT EXISTS site_enrichi_site_idx ON proj.site_enrichi(site_id);

-- Ajout des colonnes indicateurs
ALTER TABLE proj.site_enrichi
  ADD COLUMN IF NOT EXISTS dist_coursdeau_m numeric,
  ADD COLUMN IF NOT EXISTS flood_area_m2 numeric,
  ADD COLUMN IF NOT EXISTS in_flood_zone int,
  ADD COLUMN IF NOT EXISTS pct_overlap numeric,
  ADD COLUMN IF NOT EXISTS pct_faible numeric,
  ADD COLUMN IF NOT EXISTS pct_moyen numeric,
  ADD COLUMN IF NOT EXISTS pct_fort numeric,
  ADD COLUMN IF NOT EXISTS pct_tres_fort numeric,
  ADD COLUMN IF NOT EXISTS pct_derriere_ouvrage numeric,
  ADD COLUMN IF NOT EXISTS pct_tres_fort_effectif numeric,
  ADD COLUMN IF NOT EXISTS max_intensite text,
  ADD COLUMN IF NOT EXISTS pct_alea_max numeric,
  ADD COLUMN IF NOT EXISTS max_int_area_m2 numeric,
  ADD COLUMN IF NOT EXISTS max_int_geom geometry(MultiPolygon, 2154),
  ADD COLUMN IF NOT EXISTS nb_batiments_touchant int,
  ADD COLUMN IF NOT EXISTS nb_batiments_majoritaires int,
  ADD COLUMN IF NOT EXISTS surf_batie_in_site_m2 numeric,
  ADD COLUMN IF NOT EXISTS surf_batie_piece_max_m2 numeric,
  ADD COLUMN IF NOT EXISTS pct_surface_batie numeric;

-- Injection distance cours d'eau
UPDATE proj.site_enrichi s
SET dist_coursdeau_m = d.dist_coursdeau_m
FROM proj.site_enrichi_dist d
WHERE d.site_id = s.site_id;

-- Injection indicateurs aléa
UPDATE proj.site_enrichi s
SET
  flood_area_m2 = a.flood_area_m2,
  in_flood_zone = a.in_flood_zone,
  pct_overlap = a.pct_overlap,
  pct_faible = a.pct_faible,
  pct_moyen = a.pct_moyen,
  pct_fort = a.pct_fort,
  pct_tres_fort = a.pct_tres_fort,
  pct_derriere_ouvrage = a.pct_derriere_ouvrage,
  pct_tres_fort_effectif = a.pct_tres_fort_effectif,
  max_intensite = a.max_intensite,
  pct_alea_max = a.pct_alea_max
FROM proj.site_alea_agg a
WHERE a.site_id = s.site_id;

-- Injection géométrie aléa max
UPDATE proj.site_enrichi s
SET
  max_int_area_m2 = m.max_int_area_m2,
  max_int_geom = m.max_int_geom
FROM proj.site_alea_max m
WHERE m.site_id = s.site_id;

-- Injection indicateurs bâtiments
UPDATE proj.site_enrichi s
SET
  nb_batiments_touchant = b.nb_batiments_touchant,
  nb_batiments_majoritaires = b.nb_batiments_majoritaires,
  surf_batie_in_site_m2 = b.surf_batie_in_site_m2,
  surf_batie_piece_max_m2 = b.surf_batie_piece_max_m2,
  pct_surface_batie = b.pct_surface_batie
FROM proj.site_bati_agg b
WHERE b.site_id = s.site_id;

ANALYZE proj.site_enrichi;

COMMIT;

-- ============================================================
-- VÉRIFICATIONS FINALES
-- ============================================================

SELECT 'Nombre de sites traités:' AS info, COUNT(*) AS valeur FROM proj.site_enrichi
UNION ALL
SELECT 'Sites en zone inondable:', SUM(in_flood_zone) FROM proj.site_enrichi;

-- Aperçu des résultats
SELECT 
  site_id,
  in_flood_zone,
  ROUND(pct_overlap::numeric, 2) AS pct_overlap,
  max_intensite,
  ROUND(altitude_moyenne::numeric, 2) AS alt_moy_m,
  ROUND(slope_mean::numeric, 2) AS pente_moy_pct,
  ROUND(dist_coursdeau_m::numeric, 0) AS dist_eau_m,
  ROUND(pct_surface_batie::numeric, 2) AS pct_bati
FROM proj.site_enrichi
ORDER BY site_id;