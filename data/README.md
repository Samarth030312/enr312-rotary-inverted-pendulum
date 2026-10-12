# Experimental Data

## raw/

Immutable original measurements.

Never overwrite raw data.

## processed/

Derived data generated from raw measurements.

Every processed dataset must identify its source raw dataset and processing method.

## metadata/

Machine-readable provenance.

Every dataset should identify:

- experiment ID
- date
- source Git revision
- hardware configuration
- sampling rate
- units
- acquisition conditions
- parameter-set ID
- processing version

Raw data is evidence.

Processed data is derived evidence.

Neither may be fabricated.
