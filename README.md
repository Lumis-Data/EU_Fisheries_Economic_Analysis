# 🎣 Analyse économique du secteur de la pêche dans l’Union européenne

## 🧭 Vision du projet

Le secteur de la pêche européenne est au cœur de tensions majeures : performance économique, dépendance énergétique, durabilité des ressources et cohérence des politiques publiques.

Ce projet vise à transformer des données complexes du STECF (Scientific, Technical and Economic Committee for Fisheries) en un outil d’analyse clair, interactif et exploitable, permettant d’éclairer les décisions publiques et stratégiques.

---

## 🎯 Problématique

Comment analyser la performance économique du secteur de la pêche dans l’Union européenne tout en intégrant :

* la dépendance aux ressources naturelles
* l’impact des politiques publiques
* les enjeux de durabilité

---

## 🗂️ Données

### Sources

* Données officielles du STECF (Commission européenne) : [https://stecf.ec.europa.eu/document/b9b795d9-d6c5-4a27-b977-2b73afb645d2_en?prefLang=en](https://stecf.ec.europa.eu/document/b9b795d9-d6c5-4a27-b977-2b73afb645d2_en?prefLang=en)
* Données référentielles sur les espèces
* Données sur les droits d’accises (Bulletin pétrolier)

### Datasets construits

* `fact_fs.csv` : données économiques des flottilles
* `fact_landings.csv` : données de captures (volume et valeur)
* `dim_energy_excise_duty.csv` : données sur les droits d'accises
* `dim_fishingtech.csv` : données des techniques de pêche
* `dim_geozone.csv` : données géographiques
* `dim_species.csv` : données des espèces
* `dim_variable.csv` : données des variables
* `dim_vessel.csv` : données des navires
* `dim_country.csv` : données des pays

Période analysée : **2008–2022**

---

## 🛠️ Méthodologie

### 🔹 Data Processing (Python)

* Nettoyage des valeurs manquantes
* Suppression des flottes inactives
* Réagrégation des données (confidentialité < 10 navires)
* Feature engineering (catégories de flottilles et espèces)

### 🔹 Transformation

* Structuration des variables économiques
* Réduction de la dimension des espèces (+13 000 → 5 catégories)

### 🔹 Modélisation (Power BI)

* Modèle en constellation
* 2 tables de faits (économie / captures)
* 7 tables de dimensions
* 1 table Calendar

* Mesures DAX pour indicateurs clés

<img width="465" height="352" alt="image" src="https://github.com/user-attachments/assets/a1f05452-6681-4388-a1dd-9750df1646a5" />

---

## 📈 Data Visualization

Un tableau de bord interactif permet :

* Exploration multi-dimensionnelle (pays, années, flottilles)
* Analyse des performances économiques
* Visualisation des captures par zone et espèce
* Évaluation des subventions et de leur impact

👉 Dashboard Power BI disponible dans dans le dossier `/dashboard`.

---

## 🧠 Approche analytique

Le projet repose sur une approche en trois dimensions :

### 1. Production

* Volumes et valeurs des captures
* Analyse par espèce, zone géographique et type de flottille

### 2. Performance économique

* Structure du chiffre d’affaires
* Analyse des coûts (fixes et variables)
* Rentabilité et marges opérationnelles

### 3. Analyse politique

* Étude des subventions publiques
* Focus sur la détaxe carburant
* Impact économique et environnemental

---

## 📊 Résultats clés

### 🔹 Un secteur rentable mais fragile

* Rentabilité globale positive (2008–2022)
* Forte sensibilité aux coûts énergétiques
* Dépendance structurelle aux conditions de marché

<img width="1100" height="300" alt="Capture d’écran 2026-06-10 à 16 38 46" src="https://github.com/user-attachments/assets/380ffb13-dd5b-46fb-8bd8-7bd76a3c7966" />

### 🔹 Un modèle basé sur un nombre limité d’espèces

* ~70 % du chiffre d’affaires concentré sur 5 espèces
* Vulnérabilité face aux chocs environnementaux et réglementaires

<img width="452" height="264" alt="image" src="https://github.com/user-attachments/assets/2ba66fdb-b70a-4e87-a230-a702ad53478f" />

### 🔹 Un paradoxe économique majeur

* Les espèces les plus pêchées ne sont pas les plus rentables
* La création de valeur repose davantage sur les prix que sur les volumes

<img width="435" height="352" alt="image" src="https://github.com/user-attachments/assets/3b57864d-41b1-4d20-a794-144ce43bd9b6" /> <img width="452" height="352" alt="image" src="https://github.com/user-attachments/assets/30220fd0-d57b-4bcb-9e9b-57f2a137f098" />

### 🔹 Le rôle déterminant des subventions

* ~0,9 milliard € de subventions indirectes par an
* Jusqu’à 15 % du chiffre d’affaires du secteur
* Les flottilles les plus énergivores sont les plus dépendantes aux aides

<img width="452" height="352" alt="image" src="https://github.com/user-attachments/assets/1b125a8f-0e3d-4000-ad09-dbdf0607aa2c" />

### 🔹 Un désalignement économique et environnemental

* Les activités les plus impactantes écologiquement sont souvent les plus subventionnées
* Question centrale pour les politiques publiques européennes

---

## 🌍 Impact & enjeux

Ce projet met en évidence des enjeux structurants :

* Dépendance du secteur aux subventions publiques
* Sensibilité forte aux prix de l’énergie
* Nécessité d’arbitrer entre performance économique et durabilité environnementale

Il contribue à :

* améliorer la lisibilité des données publiques
* objectiver les débats sur la pêche européenne
* soutenir la prise de décision basée sur la donnée

---

## ⚠️ Limites

* Données agrégées pour des raisons de confidentialité
* Approximations liées au retraitement des clusters
* Absence de certaines variables environnementales

---

## 🔮 Perspectives

* Intégration d’indicateurs environnementaux (CO₂, état des stocks)
* Analyse de rentabilité par zone de pêche
* Suivi dynamique des indicateurs dans le temps
* Enrichissement avec des données externes (climat, biodiversité)

---

## 📄 Rapport

Le rapport complet est disponible dans le dossier `/report`.

---

## 👤 Contact

Pour toute question ou pour obtenir le rapport complet, merci de me contacter via GitHub.

---

## 💡 À retenir

Ce projet illustre comment la data peut révéler les mécanismes profonds d’un secteur stratégique, à l’intersection de l’économie, de la politique et de l’environnement.
