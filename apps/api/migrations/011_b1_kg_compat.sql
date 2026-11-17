-- Canonical B1 weight unit is kg. Legacy gram columns remain for deployed clients.
ALTER TABLE IF EXISTS sobatnira.weighings ADD COLUMN IF NOT EXISTS cane_weight_kg numeric;
ALTER TABLE IF EXISTS sobatnira.weighings ADD COLUMN IF NOT EXISTS sugar_weight_kg numeric;
ALTER TABLE IF EXISTS sobatnira.batch_grades ADD COLUMN IF NOT EXISTS sugar_weight_kg numeric;
ALTER TABLE IF EXISTS sobatnira.reworks ADD COLUMN IF NOT EXISTS weight_kg numeric;
UPDATE sobatnira.weighings SET cane_weight_kg = cane_weight_grams / 1000.0 WHERE cane_weight_kg IS NULL AND cane_weight_grams IS NOT NULL;
UPDATE sobatnira.weighings SET sugar_weight_kg = sugar_weight_grams / 1000.0 WHERE sugar_weight_kg IS NULL;
UPDATE sobatnira.batch_grades SET sugar_weight_kg = sugar_weight_grams / 1000.0 WHERE sugar_weight_kg IS NULL;
UPDATE sobatnira.reworks SET weight_kg = weight_grams / 1000.0 WHERE weight_kg IS NULL;

