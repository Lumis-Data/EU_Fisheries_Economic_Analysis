
-- ===============================================
-- 1. CONSTRUCTION DES FONCTIONS D'AUDIT DE QUALITE
-- ===============================================

-- 1.1. FONCTION audit_raw_table()

CREATE OR REPLACE FUNCTION audit_raw_tables()

-- 1. En-tête de la fonction
RETURNS TABLE (
    df TEXT,
    cellules BIGINT,
    lignes BIGINT,
    colonnes BIGINT,
    doublons BIGINT,
    na BIGINT,
    pct_na NUMERIC
)
LANGUAGE plpgsql

AS $$
-- 2. Déclaration des variables de travail
DECLARE
    tbl RECORD;
    v_lignes BIGINT;
    v_colonnes BIGINT;
    v_cellules BIGINT;
    v_na BIGINT;
    v_doublons BIGINT;
    v_sql_nulls TEXT;
BEGIN


    FOR tbl IN
        SELECT t.table_name AS name
        FROM information_schema.tables AS t
        WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND t.table_name LIKE '%_raw'
        ORDER BY t.table_name
    
    LOOP
        -- Calcul du nombre de lignes
        EXECUTE format('SELECT COUNT(*) FROM %I', tbl.name) INTO v_lignes;

        -- Calcul du nombre de colonnes
        SELECT 
            COUNT(*),
            string_agg(format('(%s - COUNT(%I))', v_lignes, column_name), ' + ')
        INTO v_colonnes, v_sql_nulls
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = tbl.name;

        -- Calcul du nombre de cellules
        v_cellules := v_lignes * v_colonnes;

        -- Calcul de tous les NULL en un seul scan de table
        IF v_lignes > 0 AND v_colonnes > 0 THEN
            EXECUTE format('SELECT %s FROM %I', v_sql_nulls, tbl.name) INTO v_na;

            -- Calcul exact des doublons
            EXECUTE format(
                'SELECT COUNT(*) - COUNT(DISTINCT ROW(t.*)) FROM %I AS t',
                tbl.name
            ) INTO v_doublons;
        ELSE
            v_na := 0;
            v_doublons := 0;
        END IF;

        -- Assignation des retours
        df := tbl.name;
        cellules := v_cellules;
        lignes := v_lignes;
        colonnes := v_colonnes;
        doublons := v_doublons;
        na := v_na;

        pct_na := CASE WHEN v_cellules > 0 
                       THEN ROUND((v_na::NUMERIC / v_cellules) * 100, 2) 
                       ELSE 0 
                  END;

        RETURN NEXT;
    END LOOP;
END;
$$;

-- 1.2. FONCTION check_data_quality()

CREATE OR REPLACE FUNCTION check_data_quality(p_table_name TEXT)

-- 1. En-tête de la fonction
RETURNS TABLE (
    variable TEXT,
    type TEXT,
    doublon BIGINT,
    na BIGINT,
    pct_na NUMERIC,
    modalite TEXT,
    apercu TEXT
)
LANGUAGE plpgsql

AS $$
-- 2. Déclaration des variables de travail
DECLARE
    col RECORD;
    v_lignes BIGINT;
    v_colonnes BIGINT;
    v_total_na BIGINT := 0;
    v_total_doublons BIGINT;
    v_na BIGINT;
    v_modalites BIGINT;
    v_doublons BIGINT;
    v_apercu TEXT;
BEGIN

-- 3. Calculs globaux initiaux (Lignes, Colonnes et doublons)
    -- Nombre de lignes global
    EXECUTE format('SELECT COUNT(*) FROM %I', p_table_name) INTO v_lignes;

    -- Nombre de colonnes global
    SELECT COUNT(*)
    INTO v_colonnes
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = p_table_name;

    -- Doublons de lignes entières (global)
    EXECUTE format(
        'SELECT COUNT(*) FROM (SELECT ROW_NUMBER() OVER (PARTITION BY t.*) AS rn FROM %I AS t) x WHERE rn > 1',
        p_table_name
    ) INTO v_total_doublons;

-- 4. Boucle d'analyse colonne par colonne

    FOR col IN
        SELECT c.column_name, c.data_type
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = p_table_name
        ORDER BY c.ordinal_position
    LOOP

        -- Calculs de NA, Modalités et Doublons
        EXECUTE format(
            'SELECT 
                COUNT(*) - COUNT(%I),
                COUNT(DISTINCT %I),
                (COUNT(*) - COUNT(DISTINCT %I))
             FROM %I',
            col.column_name, col.column_name, col.column_name, p_table_name
        ) INTO v_na, v_modalites, v_doublons;

        v_total_na := v_total_na + v_na;

    -- Génération de l'aperçu (Exemples de valeurs)
        EXECUTE format(
            'SELECT string_agg(valeur, '' | '') FROM (SELECT DISTINCT %I::TEXT AS valeur FROM %I WHERE %I IS NOT NULL LIMIT 3) x',
            col.column_name, p_table_name, col.column_name
        ) INTO v_apercu;

-- 5. Assignation des résultats de la colonne
        variable := col.column_name;
        type := col.data_type;
        doublon := COALESCE(v_doublons, 0);
        na := v_na;
        pct_na := CASE WHEN v_lignes > 0 THEN ROUND((v_na::NUMERIC / v_lignes) * 100, 2) ELSE 0 END;
        modalite := v_modalites;
        apercu := COALESCE(v_apercu, '');

        RETURN NEXT;
    END LOOP;

-- 6. Construction de la ligne globale (Total)
    variable := '--- GLOBAL ---';
    type := '-';
    doublon := v_total_doublons;
    na := v_total_na;
    pct_na := CASE 
        WHEN v_lignes > 0 AND v_colonnes > 0 
        THEN ROUND((v_total_na::NUMERIC / (v_lignes * v_colonnes)) * 100, 2) 
        ELSE 0 
    END;
    modalite := '-';
    apercu := v_lignes::TEXT || ' lignes et ' || v_colonnes::TEXT || ' colonnes';

    RETURN NEXT;

END;
$$;

-- ============================================
-- 2. AUDIT DE QUALITE GLOBAL DES TABLES BRUTES
-- ============================================

SELECT
    GROUPING(df) AS ordre,
    COALESCE(df, 'TOTAL') AS df,
    SUM(cellules) AS cellules,
    SUM(lignes) AS lignes,
    SUM(colonnes) AS colonnes,
    SUM(doublons) AS doublons,
    SUM(na) AS na,
    ROUND((SUM(na)::NUMERIC / NULLIF(SUM(cellules), 0)) * 100, 2) AS pct_na
FROM audit_raw_tables()
GROUP BY ROLLUP(df)
ORDER BY ordre, pct_na DESC;

-- ================================================
-- 3. NETTOYAGE DES DONNEES DE species_mapping_raw
-- ================================================

-- 3.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('species_mapping_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de la table species_mapping_clean à partir des données brutes et colonnes pertinentes afin de procéder au nettoyage
DROP TABLE IF EXISTS species_mapping_clean;

CREATE TABLE species_mapping_clean AS
SELECT 
    alpha3_code,
    family,
    "order or higher taxa",
    species_category
FROM species_mapping_raw;

-- 3.2. TRAITEMENT DES VALEURS MANQUANTES

-- Remplacement des valeurs manquantes
UPDATE species_mapping_clean
SET family = 'Unidentified family'
WHERE family IS NULL;

UPDATE species_mapping_clean
SET "order or higher taxa" = 'Unidentified order or higher taxa'
WHERE "order or higher taxa" IS NULL;

-- 3.3. VALIDATION FINALE

-- Visualisation de species_mapping_clean
SELECT *
FROM species_mapping_clean
ORDER BY alpha3_code;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('species_mapping_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- ==================================
-- 4. NETTOYAGE DES DONNEES DE fs_raw
-- ==================================

-- 4.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fs_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de la table fs_clean à partir des données brutes et colonnes pertinentes afin de procéder au nettoyage
DROP VIEW IF EXISTS v_fs_deduplicated;
DROP VIEW IF EXISTS v_fs_processed;
DROP TABLE IF EXISTS fs_clean_final;
DROP TABLE IF EXISTS fs_clean;

CREATE TABLE fs_clean AS
SELECT
    origin_sheet,
    upload_date,
    fromtable,
    template_name,
    framework,
    cluster_name,
    fs_name,
    year,
    country_code,
    country_name,
    supra_reg,
    geo_indicator,
    fishery,
    activity,
    fishing_tech,
    vessel_length,
    gear,
    variable_group,
    variable_code,
    variable_name,
    unit,
    value
FROM fs_raw;

-- Suppression des colonnes non pertinentes
ALTER TABLE fs_clean
    DROP COLUMN upload_date,
    DROP COLUMN fromtable,
    DROP COLUMN template_name,
    DROP COLUMN framework,
    DROP COLUMN cluster_name,
    DROP COLUMN geo_indicator,
    DROP COLUMN fishery,
    DROP COLUMN activity,
    DROP COLUMN gear;

-- Exclusion de l'année 2023 et des flottes inactives
DELETE FROM fs_clean WHERE year = 2023;
DELETE FROM fs_clean WHERE UPPER(fishing_tech) = 'INACTIVE';

-- Vérification de la structure des données
SELECT *
FROM fs_clean
ORDER BY
    origin_sheet, fs_name, year, country_code, country_name,
    variable_group, variable_code, variable_name, supra_reg, fishing_tech, vessel_length;

-- Identification des valeurs manquantes de variable_name
SELECT
    variable_name,
    COUNT(*) AS na
FROM fs_clean
WHERE value IS NULL
GROUP BY variable_name
ORDER BY na;

-- 4.2. TRAITEMENT DES VALEURS MANQUANTES

-- 4.2.1. VUE INTERMEDIAIRE POUR L'IMPUTATION DES DONNEES (BASEE SUR LES CLES DE PROPORTION)

-- Création des vues intermédiaire
CREATE VIEW v_fs_processed AS
WITH fs_base AS (
    SELECT f.*
    FROM fs_clean AS f
    ORDER BY "origin_sheet","fs_name","year","country_code","country_name","variable_group",
             "variable_code","variable_name","supra_reg","fishing_tech","vessel_length"
    ),

fs_groups AS (
    SELECT
        fb.*,
        CONCAT('total_fs_', DENSE_RANK() OVER (ORDER BY fs_name, year, supra_reg, variable_name) - 1) AS id_total_by_fsname,
        (BOOL_OR(value IS NULL) OVER w AND COUNT(*) OVER w > 1) AS has_na_in_fsname,
        SUM(value) OVER w AS total_by_fsname
    FROM fs_base AS fb
    WINDOW w AS (PARTITION BY fs_name, year, supra_reg, variable_name)
),

fs_keys AS (
    SELECT
        fs_name,
        year,
        fishing_tech,
        vessel_length,
        SUM(value) / NULLIF(SUM(SUM(value)) OVER (PARTITION BY year, fs_name), 0) AS keys_proportion
    FROM fs_clean
    WHERE variable_name = 'Number of vessels'
    GROUP BY fs_name, year, fishing_tech, vessel_length
)

SELECT
    g.*,
    k.keys_proportion,
    ROUND(
        (CASE
            WHEN g.has_na_in_fsname = TRUE THEN g.total_by_fsname * k.keys_proportion
            ELSE g.value
        END)::NUMERIC, 2
    ) AS new_value
FROM fs_groups AS g
LEFT JOIN fs_keys AS k
    ON  g.fs_name = k.fs_name
    AND g.year = k.year
    AND g.fishing_tech = k.fishing_tech
    AND g.vessel_length = k.vessel_length;

-- Contrôle de l'imputation
SELECT
    has_na_in_fsname,
    SUM(new_value) AS new_value,
    SUM(value) AS value,
    ROUND((SUM(new_value) - SUM(value))::NUMERIC, 4) AS variance
FROM v_fs_processed
GROUP BY has_na_in_fsname
ORDER BY has_na_in_fsname;

-- Contrôle des clés de répartition
SELECT
    id_total_by_fsname,
    SUM(keys_proportion) AS somme_proportions
FROM v_fs_processed
WHERE has_na_in_fsname = TRUE
GROUP BY id_total_by_fsname
ORDER BY ABS(SUM(keys_proportion) - 1) DESC, id_total_by_fsname DESC;

-- Vérification sur des groupes ciblés
SELECT
    id_total_by_fsname,
    fs_name,
    year,
    supra_reg,
    variable_name,
    fishing_tech,
    vessel_length,
    value,
    total_by_fsname,
    keys_proportion,
    new_value,
    has_na_in_fsname
FROM v_fs_processed
WHERE id_total_by_fsname IN ('total_fs_101289', 'total_fs_52820')
ORDER BY
    id_total_by_fsname,
    value NULLS LAST;  

-- 4.2.2. DEDUPLICATION DES DONNEES

CREATE VIEW v_fs_deduplicated AS
    SELECT *
    FROM (
        SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY origin_sheet, fs_name, year, country_code, country_name, 
                         supra_reg, fishing_tech, vessel_length, variable_group, 
                         variable_code, variable_name, unit 
            ORDER BY id_total_by_fsname, value NULLS LAST
        ) AS rn
        FROM v_fs_processed
    ) AS x
    WHERE rn = 1;

-- Vérification des groupes spécifiques après déduplication
SELECT *
FROM v_fs_deduplicated
WHERE id_total_by_fsname IN ('total_fs_101289', 'total_fs_52820')
ORDER BY id_total_by_fsname, value NULLS LAST;

-- Contrôle après imputation
SELECT
    variable_name,
    SUM(value) AS value,
    SUM(new_value) AS new_value,
    ROUND((SUM(new_value) - SUM(value))::NUMERIC, 4) AS variance
FROM v_fs_deduplicated
GROUP BY variable_name

UNION ALL

SELECT
    'TOTAL' AS variable_name,
    SUM(value) AS value,
    SUM(new_value) AS new_value,
    ROUND((SUM(new_value) - SUM(value))::NUMERIC, 4) AS variance
FROM v_fs_deduplicated;

-- 4.3. VALIDATION FINALE DE fs_clean

DROP TABLE IF EXISTS fs_clean_final;

CREATE TABLE fs_clean_final AS
SELECT
    origin_sheet,
    fs_name,
    year,
    country_code,
    country_name,
    supra_reg,
    fishing_tech,
    vessel_length,
    variable_group,
    variable_code,
    variable_name,
    unit,
    COALESCE(new_value, 0) AS value
FROM v_fs_deduplicated;

-- Suppression des vues temporaires
DROP VIEW IF EXISTS v_fs_deduplicated;
DROP VIEW IF EXISTS v_fs_processed;

-- Remplacement de la table de travail par la table finale
DROP TABLE IF EXISTS fs_clean;

ALTER TABLE fs_clean_final
RENAME TO fs_clean;

-- Validation finale de la qualité
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fs_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- =========================================
-- 5. NETTOYAGE DES DONNEES DE landings_raw
-- =========================================

-- 5.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('landings_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de la table landings_clean à partir des données brutes et colonnes pertinentes afin de procéder au nettoyage
DROP TABLE IF EXISTS landings_clean;

CREATE TABLE landings_clean AS
SELECT
    origin_sheet,
    upload_date,
    fromtable,
    template_name,
    framework,
    cluster_name,
    fs_name,
    year,
    country_code,
    country_name,
    supra_reg,
    sub_reg,
    geo_indicator,
    fishery,
    activity,
    fishing_tech,
    vessel_length,
    gear,
    variable_group,
    variable_code,
    variable_name,
    species_code,
    species_name,
    unit,
    value
FROM landings_raw;

-- Suppression des colonnes non pertinentes
ALTER TABLE landings_clean
    DROP COLUMN upload_date,
    DROP COLUMN fromtable,
    DROP COLUMN template_name,
    DROP COLUMN framework,
    DROP COLUMN cluster_name,
    DROP COLUMN geo_indicator,
    DROP COLUMN fishery,
    DROP COLUMN activity,
    DROP COLUMN gear;

-- Exclusion de l'année 2023 et des flottes inactives
DELETE FROM landings_clean WHERE year = 2023;
DELETE FROM landings_clean WHERE UPPER(fishing_tech) = 'INACTIVE';

-- Contrôle visuel de la structure après filtrage
SELECT *
FROM landings_clean
ORDER BY
    origin_sheet, fs_name, year, country_code, country_name, variable_group, variable_code,
    variable_name, supra_reg, sub_reg, fishing_tech, vessel_length, species_code, species_name;

-- 5.2. TRAITEMENT DES VALEURS MANQUANTES

-- 5.2.1. TRAITEMENT DES NA DE species_name

-- Analyse des species_name manquants
SELECT
    COUNT(*) AS nb_na_species_name,
    COUNT(DISTINCT species_code) AS nb_codes_species
FROM landings_clean
WHERE species_name IS NULL;

-- Identification des codes espèces dont le nom est disponible dans la table de référence species_raw
SELECT
    l.species_code,
    s.code AS species_raw_code,
    s.common_name
FROM (
    SELECT DISTINCT species_code
    FROM landings_clean
    WHERE species_name IS NULL
) AS l
LEFT JOIN species_raw AS s
    ON l.species_code = s.code
ORDER BY l.species_code;

-- Remplacement des noms d'espèces manquants par "Unknown"
UPDATE landings_clean
SET species_name = 'Unknown'
WHERE species_name IS NULL;

-- Contrôle du nombre de valeurs manquantes restantes
SELECT 
    COUNT(*) AS nb_species_name_na
FROM landings_clean
WHERE species_name IS NULL;

-- 5.2.2. TRAITEMENT DES NA DE value

-- Analyse des valeurs manquantes
SELECT
    COUNT(*) AS nb_na_value
FROM landings_clean
WHERE value IS NULL;

-- Répartition des NA de value par pays et année
SELECT
    country_name,
    year,
    COUNT(*) AS nb_na_value,
    ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM landings_clean WHERE value IS NULL),0),2) AS pct_na_value
FROM landings_clean
WHERE value IS NULL
GROUP BY country_name, year
ORDER BY nb_na_value DESC;

-- Suppression des lignes dont la valeur est manquante
DELETE FROM landings_clean WHERE value IS NULL;

-- 5.3. VALIDATION FINALE

-- Contrôle du nombre de valeurs manquantes restantes
SELECT
    COUNT(*) AS nb_na_value
FROM landings_clean
WHERE value IS NULL;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('landings_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- =======================================
-- 6. NETTOYAGE DES DONNEES DE species_raw
-- =======================================

-- 6.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('species_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de la table species_clean à partir des données brutes et colonnes pertinentes afin de procéder au nettoyage
DROP TABLE IF EXISTS species_clean;

CREATE TABLE species_clean AS
SELECT
    code AS species_code,
    common_name AS species_name,
    scientific_name AS species_scientificname,
    origin_sheet
FROM species_raw;

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE species_clean ADD PRIMARY KEY(species_code);

-- Contrôle visuel de la structure après filtrage
SELECT *
FROM species_clean
ORDER BY species_code;

-- 6.2. TRAITEMENT DES VALEURS MANQUANTES

-- Tentative de récupération des NA de species_name à partir des noms disponibles dans landings_clean
UPDATE species_clean AS s
SET species_name = l.species_name
FROM (
    SELECT DISTINCT ON (species_code)
        species_code,
        species_name
    FROM landings_clean
    WHERE species_name <> 'Unknown' AND species_name IS NOT NULL
    ORDER BY species_code
) AS l
WHERE s.species_code = l.species_code AND s.species_name IS NULL;

-- Contrôle des NA restants après la tentative de récupération
SELECT
    COUNT(*) AS nb_species_name_na
FROM species_clean
WHERE species_name IS NULL;

-- Remplacement des NA résiduels par "Unknown"
UPDATE species_clean
SET species_name = 'Unknown'
WHERE species_name IS NULL;

-- Contrôle des NA restants après le remplacement
SELECT
    COUNT(*) AS nb_species_name_na
FROM species_clean
WHERE species_name IS NULL;

-- 6.3. VALIDATION FINALE

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('species_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- =======================================
-- 7. NETTOYAGE DES DONNEES DE country_raw
-- =======================================

-- 7.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('country_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de country_clean
DROP TABLE IF EXISTS country_clean;

CREATE TABLE country_clean AS
SELECT *
FROM country_raw
WHERE country_code NOT IN ('JRC', 'STF', 'CCR');

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE country_clean ADD PRIMARY KEY(country_code);

-- Contrôle visuel de la structure après filtrage
SELECT *
FROM country_clean;

-- 7.2. VALIDATION FINALE

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('country_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- ==================================================
-- 8. NETTOYAGE DES DONNEES DE energy_excise_duty_raw
-- ==================================================

-- 8.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('energy_excise_duty_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de energy_excise_duty_clean
DROP TABLE IF EXISTS energy_excise_duty_clean;

CREATE TABLE energy_excise_duty_clean AS
SELECT
    year,
    country_code,
    country AS country_name,
    tax_rate_eur_per_l AS excise_duty_eur_l,
    origin_sheet
FROM energy_excise_duty_raw;

-- Contrôle visuel de la structure après filtrage
SELECT *
FROM energy_excise_duty_clean;

-- 8.2. VALIDATION FINALE

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('energy_excise_duty_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC,
    pct_na DESC;

-- ===========================================
-- 9. NETTOYAGE DES DONNEES DE fishingtech_raw
-- ===========================================

-- 9.1. PREPARATION ET FILTRAGE DES DONNEES

-- Contrôle initial de la qualité des données brutes
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fishingtech_raw')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Création de fishingtech_clean
DROP TABLE IF EXISTS fishingtech_clean;

CREATE TABLE fishingtech_clean AS
SELECT
    code AS fishingtech_code,
    description AS fishingtech_name,
    origin_sheet
FROM fishingtech_raw
WHERE code <> 'INACTIVE';

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE fishingtech_clean ADD PRIMARY KEY(fishingtech_code);

-- Contrôle visuel de la structure après filtrage
SELECT *
FROM fishingtech_clean
ORDER BY fishingtech_code;

-- 9.2. VALIDATION FINALE

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fishingtech_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- ========================================
-- 10. ENRICHISSEMENT DU MODELE RELATIONNEL
-- ========================================

-- 10.1. ENRICHISSSEMENT DE species_clean

-- Ajout des colonnes provenant de species_mapping_clean
ALTER TABLE species_clean
    ADD COLUMN family TEXT,
    ADD COLUMN "order or higher taxa" TEXT,
    ADD COLUMN species_category TEXT;

-- Fusion avec la table de correspondance des espèces
UPDATE species_clean s
SET
    family = m.family,
    "order or higher taxa" = m."order or higher taxa",
    species_category = m.species_category
FROM species_mapping_clean m
WHERE s.species_code = m.alpha3_code;

-- Suppression, ajout et réenchirissement de la colonne origin_sheet à la fin
ALTER TABLE species_clean DROP COLUMN IF EXISTS origin_sheet;
ALTER TABLE species_clean ADD COLUMN origin_sheet TEXT;

UPDATE species_clean sc
SET origin_sheet = sr.origin_sheet
FROM species_raw sr
WHERE sc.species_code = sr.code;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('species_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 10.2. NOMENCLATURE DE fishingtech_clean

-- Ajout des catégories dans fishingtech_clean
ALTER TABLE fishingtech_clean
    ADD COLUMN IF NOT EXISTS fishingtech_category_code TEXT,
    ADD COLUMN IF NOT EXISTS fishingtech_category_name TEXT;

UPDATE fishingtech_clean f
SET
    fishingtech_category_code = 
        CASE
            WHEN f.fishingtech_code IN ('DFN', 'FPO', 'HOK', 'MGO', 'PGO', 'PGP', 'PG') THEN 'PG'
            WHEN f.fishingtech_code IN ('DRB', 'MGP', 'PMP') THEN 'Dre'
            WHEN f.fishingtech_code IN ('DTS', 'TBB') THEN 'TraD'
            WHEN f.fishingtech_code IN ('PS', 'TM', 'TMP') THEN 'TraP'
            WHEN f.fishingtech_code IN ('INACTIVE') THEN 'INACTIVE'
            ELSE 'INACTIVE'
        END,
    fishingtech_category_name = 
        CASE
            WHEN f.fishingtech_code IN ('DFN', 'FPO', 'HOK', 'MGO', 'PGO', 'PGP', 'PG') THEN 'Passive gears (nets, lines, traps)'
            WHEN f.fishingtech_code IN ('DRB', 'MGP', 'PMP') THEN 'Dredgers and polyvalent'
            WHEN f.fishingtech_code IN ('DTS', 'TBB') THEN 'Demersal trawlers and seiners'
            WHEN f.fishingtech_code IN ('PS', 'TM', 'TMP') THEN 'Pelagic trawlers and seiners'
            WHEN f.fishingtech_code IN ('INACTIVE') THEN 'INACTIVE'
            ELSE 'INACTIVE'
        END;

-- Suppression, ajout et réenchirissement de la colonne origin_sheet à la fin
ALTER TABLE fishingtech_clean DROP COLUMN IF EXISTS origin_sheet;
ALTER TABLE fishingtech_clean ADD COLUMN origin_sheet TEXT;

UPDATE fishingtech_clean fc
SET origin_sheet = fr.origin_sheet
FROM fishingtech_raw fr
WHERE fc.fishingtech_code = fr.code;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fishingtech_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 10.3. CATEGORISATION DES FLOTTES

-- Création de la table vessel_clean
DROP TABLE IF EXISTS vessel_clean;

CREATE TABLE vessel_clean AS
SELECT DISTINCT
    vessel_length
FROM landings_clean
WHERE vessel_length IS NOT NULL
ORDER BY vessel_length;

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE vessel_clean ADD PRIMARY KEY(vessel_length);

-- Ajout de la catégorie de navire
ALTER TABLE vessel_clean
    ADD COLUMN vessel_category TEXT;

UPDATE vessel_clean
SET vessel_category =
    CASE
        WHEN vessel_length IN ('VL0006', 'VL0008', 'VL0010', 'VL0612', 'VL0812', 'VL1012') THEN 'Inshore'
        WHEN vessel_length IN ('VL1218', 'VL1824') THEN 'Offshore'
        WHEN vessel_length IN ('VL2440', 'VL40XX') THEN 'Industrial'
        ELSE NULL
    END;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('vessel_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 10.4. CONSTRUCTION DE geozone_clean

-- Création de la table geozone_clean
DROP TABLE IF EXISTS geozone_clean;

CREATE TABLE geozone_clean AS
    SELECT * FROM (
        VALUES
            ('AREA27', 'Atlantic, Northeast'),
            ('AREA37', 'Mediterranean and Black Sea'),
            ('OFR', 'Other fishing regions')
    ) AS t(area_code, area_name);

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE geozone_clean ADD PRIMARY KEY(area_code);

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('geozone_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 10.5. CONSTRUCTION DE variable_clean

-- Création de la table variable_clean
DROP TABLE IF EXISTS variable_clean;

CREATE TABLE variable_clean AS
SELECT
    variable_code,
    variable_name,
    variable_group
FROM fs_clean

UNION

SELECT
    variable_code,
    variable_name,
    variable_group
FROM landings_clean;

-- Ajout d'une clé primaire pour garantir l'unicité et optimiser les index
ALTER TABLE variable_clean ADD PRIMARY KEY(variable_code);

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('variable_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- ========================================================================================
-- 11. HARMONISATION DES REFERENTIELS ENTRE LES TABLES DE FAITS ET LES TABLES DE DIMENSIONS
-- ========================================================================================

-- 11.1. VERIFICATION DE L'INTEGRITE REFERENTIELLE ENTRE landings_clean et LES TABLES DE DIMENSIONS

-- Vérification des codes pays
SELECT
    'country_code' AS cle,
    COUNT(DISTINCT l.country_code) AS nb_codes_faits,
    COUNT(DISTINCT l.country_code) FILTER(WHERE c.country_code IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN country_clean c ON l.country_code = c.country_code;

-- Identification des codes pays orphelins
SELECT
    DISTINCT l.country_code
FROM landings_clean l
LEFT JOIN country_clean c ON l.country_code = c.country_code
WHERE c.country_code IS NULL
ORDER BY l.country_code;

-- Vérification des zones gégraphiques
SELECT
    'supra_reg' AS cle,
    COUNT(DISTINCT l.supra_reg) AS nb_codes_faits,
    COUNT(DISTINCT l.supra_reg) FILTER (WHERE g.area_code IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN geozone_clean g ON l.supra_reg = g.area_code;

-- Vérification des techniques de pêches
SELECT
    'fishing_tech' AS cle,
    COUNT(DISTINCT l.fishing_tech) AS nb_codes_faits,
    COUNT(DISTINCT l.fishing_tech) FILTER (WHERE f.fishingtech_code IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN fishingtech_clean f ON l.fishing_tech = f.fishingtech_code;

-- Identification des techniques de pêches orphelines
SELECT
    DISTINCT l.fishing_tech
FROM landings_clean l
LEFT JOIN fishingtech_clean f ON l.fishing_tech = f.fishingtech_code
WHERE f.fishingtech_code IS NULL
ORDER BY l.fishing_tech;

-- Vérification des classes de longueur des navires
SELECT
    'vessel_length' AS cle,
    COUNT(DISTINCT l.vessel_length) AS nb_codes_faits,
    COUNT(DISTINCT l.vessel_length) FILTER(WHERE v.vessel_length IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN vessel_clean v ON l.vessel_length = v.vessel_length;

-- Identification des classes de longueur des navires orphelines
SELECT
    DISTINCT l.vessel_length
FROM landings_clean l
LEFT JOIN vessel_clean v ON l.vessel_length = v.vessel_length
WHERE v.vessel_length IS NULL
ORDER BY l.vessel_length;

-- Vérification des espèces
SELECT
    'species_code' AS cle,
    COUNT(DISTINCT l.species_code) AS nb_codes_faits,
    COUNT(DISTINCT l.species_code) FILTER (WHERE sc.species_code IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN species_clean sc ON l.species_code = sc.species_code;

-- Identification des espèces orphelines
SELECT
    DISTINCT l.species_code
FROM landings_clean l
LEFT JOIN species_clean sc ON l.species_code = sc.species_code
WHERE sc.species_code IS NULL
ORDER BY l.species_code;

-- Vérificaton des variables
SELECT
    'variable_code' AS cle,
    COUNT(DISTINCT l.variable_code) AS nb_codes_faits,
    COUNT(DISTINCT l.variable_code) FILTER(WHERE v.variable_code IS NULL) AS nb_codes_orphelins
FROM landings_clean l
LEFT JOIN variable_clean v ON l.variable_code = v.variable_code;

-- Identification des variables orphelines
SELECT
    DISTINCT l.variable_code
FROM landings_clean l
LEFT JOIN variable_clean v ON l.variable_code = v.variable_code
WHERE v.variable_code IS NULL
ORDER BY l.variable_code;

-- Harmonisation des codes géographiques
UPDATE landings_clean
SET supra_reg =
    CASE
        WHEN supra_reg = 'NAO' THEN 'AREA27'
        WHEN supra_reg = 'MBS' THEN 'AREA37'
        ELSE supra_reg
    END;

-- Vérification de la correction
SELECT
    DISTINCT supra_reg
FROM landings_clean
ORDER BY supra_reg;

-- Nouvelle vérification de l'intégrité référentielle
SELECT 
    DISTINCT l.supra_reg
FROM landings_clean l
LEFT JOIN geozone_clean g ON l.supra_reg = g.area_code
WHERE g.area_code IS NULL
ORDER BY l.supra_reg;

-- Identification des doublons
WITH landings_duplicates AS (
    SELECT
        *,
        COUNT(*) OVER(PARTITION BY
            origin_sheet,
            fs_name,
            year,
            country_code,
            country_name,
            supra_reg,
            sub_reg,
            fishing_tech,
            vessel_length,
            variable_group,
            variable_code,
            variable_name,
            species_code,
            species_name,
            unit,
            value) AS nb_occurences
    FROM landings_clean
)
SELECT *
FROM landings_duplicates
WHERE nb_occurences > 1
ORDER BY nb_occurences DESC;

-- Suppression des doublons
WITH duplicates AS (
    SELECT
        ctid,
        ROW_NUMBER() OVER(
            PARTITION BY
                origin_sheet, fs_name, year, country_code, country_name, 
                supra_reg, sub_reg, fishing_tech, vessel_length, 
                variable_group, variable_code, variable_name, 
                species_code, species_name, unit, value
            ORDER BY ctid
        ) AS rn
    FROM landings_clean
)

DELETE FROM landings_clean l
USING duplicates d
WHERE l.ctid = d.ctid AND d.rn > 1;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('landings_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 11.2. VERIFICATION DE L'INTEGRITE REFERENTIELLE ENTRE fs_clean et LES TABLES DE DIMENSIONS

-- Préparation de la clé primaire country_year dans energy_excise_duty_clean
ALTER TABLE energy_excise_duty_clean
    ADD COLUMN IF NOT EXISTS country_year TEXT;

UPDATE energy_excise_duty_clean
SET country_year = country_code || '-' || year::TEXT;

ALTER TABLE energy_excise_duty_clean ADD PRIMARY KEY(country_year);

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('energy_excise_duty_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Préparation de la clé étrangère country_year dans fs_clean
ALTER TABLE fs_clean
    ADD COLUMN country_year TEXT;

UPDATE fs_clean
SET country_year = country_code || '-' || year::TEXT;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fs_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Vérification de l'intégrité référentielle

-- Vérification de country_code
SELECT
    DISTINCT f.country_code AS code_orphelin
FROM fs_clean f
LEFT JOIN country_clean c ON f.country_code = c.country_code
WHERE f.country_code IS NOT NULL AND c.country_code IS NULL
ORDER BY f.country_code;

-- Vérification de fishing_tech
SELECT
    DISTINCT f.fishing_tech AS code_orphelin
FROM fs_clean f
LEFT JOIN fishingtech_clean ft ON f.fishing_tech = ft.fishingtech_code
WHERE f.fishing_tech IS NOT NULL AND ft.fishingtech_code IS NULL
ORDER BY f.fishing_tech;

-- Vérification de vessel_length
SELECT
    DISTINCT f.vessel_length AS code_orphelin
FROM fs_clean f
LEFT JOIN vessel_clean v ON f.vessel_length = v.vessel_length
WHERE f.vessel_length IS NOT NULL AND v.vessel_length IS NULL
ORDER BY f.vessel_length;

-- Vérification de supra_reg
SELECT
    DISTINCT f.supra_reg AS code_orphelin
FROM fs_clean f
LEFT JOIN geozone_clean g ON f.supra_reg = g.area_code
WHERE f.supra_reg IS NOT NULL AND g.area_code IS NULL
ORDER BY f.supra_reg;

-- Vérification de variable_code
SELECT
    DISTINCT f.variable_code AS code_orphelin
FROM fs_clean f
LEFT JOIN variable_clean v ON f.variable_code = v.variable_code
WHERE f.variable_code IS NOT NULL AND v.variable_code IS NULL
ORDER BY f.variable_code;

-- Vérification de country_year
SELECT
    DISTINCT f.country_year AS code_orphelin
FROM fs_clean f
LEFT JOIN energy_excise_duty_clean e ON f.country_year = e.country_year
WHERE f.country_year IS NOT NULL AND e.country_year IS NULL
ORDER BY f.country_year;

-- Harmonisation des codes géographiques
UPDATE fs_clean
SET supra_reg =
    CASE
        WHEN supra_reg = 'NAO' THEN 'AREA27'
        WHEN supra_reg = 'MBS' THEN 'AREA37'
        ELSE supra_reg
    END;

-- Vérification de supra_reg
SELECT
    DISTINCT f.supra_reg AS code_orphelin
FROM fs_clean f
LEFT JOIN geozone_clean g ON f.supra_reg = g.area_code
WHERE f.supra_reg IS NOT NULL AND g.area_code IS NULL
ORDER BY f.supra_reg;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fs_clean')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- =====================================
-- 12. EXPORTATION DU MODELE RELATIONNEL
-- =====================================

-- 12.1. CREATION DES TABLES DE FAITS

-- Création de fact_fs
DROP TABLE IF EXISTS fact_fs;

CREATE TABLE fact_fs AS
SELECT
    origin_sheet,
    fs_name,
    year,
    country_code,
    country_year,
    supra_reg,
    fishing_tech,
    vessel_length,
    variable_code,
    unit,
    value
FROM fs_clean;

-- Création de fact_landings
DROP TABLE IF EXISTS fact_landings;

CREATE TABLE fact_landings AS
SELECT
    origin_sheet,
    fs_name,
    year,
    country_code,
    --country_year,
    supra_reg,
    sub_reg,
    fishing_tech,
    vessel_length,
    variable_code,
    unit,
    species_code,
    value
FROM landings_clean;

-- Contrôle final de la qualité des données
SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fact_fs')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fact_landings')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 12.2. CREATION DES TABLES DE DIMENSIONS

-- Création de dim_species
DROP TABLE IF EXISTS dim_species;
CREATE TABLE dim_species AS
SELECT *
FROM species_clean;

-- Création de dim_fishingtech
DROP TABLE IF EXISTS dim_fishingtech;
CREATE TABLE dim_fishingtech AS
SELECT *
FROM fishingtech_clean;

-- Création de dim_vessel
DROP TABLE IF EXISTS dim_vessel;
CREATE TABLE dim_vessel AS
SELECT *
FROM vessel_clean;

-- Création de dim_geozone
DROP TABLE IF EXISTS dim_geozone;
CREATE TABLE dim_geozone AS
SELECT *
FROM geozone_clean;

-- Création de dim_country
DROP TABLE IF EXISTS dim_country;
CREATE TABLE dim_country AS
SELECT *
FROM country_clean;

-- Création de dim_variable
DROP TABLE IF EXISTS dim_variable;
CREATE TABLE dim_variable AS
SELECT *
FROM variable_clean;

-- Création de dim_energy_excise_duty
DROP TABLE IF EXISTS dim_energy_excise_duty;
CREATE TABLE dim_energy_excise_duty AS
SELECT *
FROM energy_excise_duty_clean;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fact_fs')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('fact_landings')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- Contrôle final de la qualité des données

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_country')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_fishingtech')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_geozone')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_species')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_vessel')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_variable')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

SELECT variable, type, doublon, na, pct_na, modalite, apercu
FROM check_data_quality('dim_energy_excise_duty')
ORDER BY 
    CASE WHEN variable = '--- GLOBAL ---' THEN 1 ELSE 0 END ASC, 
    pct_na DESC;

-- 12.3. EXPORTATION DU MODELE EN CSV

-- Export de fact_fs
COPY (SELECT * FROM fact_fs)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/fact_fs.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de fact_landings
COPY (SELECT * FROM fact_landings)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/fact_landings.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_species
COPY (SELECT * FROM dim_species)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_species.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_fishingtech
COPY (SELECT * FROM dim_fishingtech)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_fishingtech.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_vessel
COPY (SELECT * FROM dim_vessel)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_vessel.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_geozone
COPY (SELECT * FROM dim_geozone)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_geozone.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_country
COPY (SELECT * FROM dim_country)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_country.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_variable
COPY (SELECT * FROM dim_variable)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_variable.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');

-- Export de dim_energy_excise_duty
COPY (SELECT * FROM dim_energy_excise_duty)
TO '/Users/juliengrapin/Documents/04. Formation/Reconversion/Data analyst/Projet data/Pêche dans l''UE/Data/Processed/dim_energy_excise_duty.csv' 
WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', ENCODING 'UTF8');