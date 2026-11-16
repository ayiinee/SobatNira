-- Canonical B1 weight unit is kg. Legacy gram columns remain for deployed clients.
ALTER TABLE IF EXISTS weighings ADD COLUMN IF NOT EXISTS cane_weight_kg numeric;
ALTER TABLE IF EXISTS weighings ADD COLUMN IF NOT EXISTS sugar_weight_kg numeric;
ALTER TABLE IF EXISTS batch_grades ADD COLUMN IF NOT EXISTS sugar_weight_kg numeric;
ALTER TABLE IF EXISTS reworks ADD COLUMN IF NOT EXISTS weight_kg numeric;
UPDATE weighings SET cane_weight_kg = cane_weight_grams / 1000.0 WHERE cane_weight_kg IS NULL AND cane_weight_grams IS NOT NULL;
UPDATE weighings SET sugar_weight_kg = sugar_weight_grams / 1000.0 WHERE sugar_weight_kg IS NULL;
UPDATE batch_grades SET sugar_weight_kg = sugar_weight_grams / 1000.0 WHERE sugar_weight_kg IS NULL;
UPDATE reworks SET weight_kg = weight_grams / 1000.0 WHERE weight_kg IS NULL;
