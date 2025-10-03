-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================================================
-- CORE ENTITIES
-- =====================================================

-- Service provider companies that manage HVAC units
CREATE TABLE service_providers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    license_code VARCHAR(100),
    service_titan_id VARCHAR(100),
    website VARCHAR(255),

    -- Address fields
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    zip_code VARCHAR(20) NOT NULL,

    -- Contact info
    primary_contact_name VARCHAR(255) NOT NULL,
    primary_contact_phone VARCHAR(20) NOT NULL,
    secondary_contact_name VARCHAR(255),
    secondary_contact_phone VARCHAR(20),

    -- Metadata
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Physical locations where HVAC units are installed
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,

    -- Address fields
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(50) NOT NULL,
    zip_code VARCHAR(20) NOT NULL,

    -- Contact info
    primary_contact_name VARCHAR(255) NOT NULL,
    primary_contact_phone VARCHAR(20) NOT NULL,
    secondary_contact_name VARCHAR(255),
    secondary_contact_phone VARCHAR(20),

    -- Relationships
    fk_provider_id UUID NOT NULL REFERENCES service_providers(id),

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_locations_provider ON locations(fk_provider_id);

-- =====================================================
-- EQUIPMENT TABLES
-- =====================================================

-- Define refrigerant type enum
CREATE TYPE refrigerant_enum AS ENUM (
    'R134A', 'R410A', 'R32', 'R454B', 'R22', 'R427A',
    'R407C', 'R422B', 'R438A', 'R404A', 'R448A',
    'R449A', 'R454C', 'R513A'
);

-- Air handler equipment specs
CREATE TABLE air_handler_equipment (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manufacturer VARCHAR(255) NOT NULL,
    model_number VARCHAR(255) NOT NULL,
    serial_number VARCHAR(255) UNIQUE NOT NULL,
    product_number VARCHAR(255),

    -- Electrical specs
    unit_volts VARCHAR(50),
    motor_hp DECIMAL(5,2),
    motor_fla DECIMAL(6,2),
    phase_hertz VARCHAR(50),

    -- Other specs
    test_static VARCHAR(100),
    refrigerant_type refrigerant_enum,
    accessories TEXT,

    manufacture_date DATE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Compressor equipment specs
CREATE TABLE compressor_equipment (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    manufacturer VARCHAR(255) NOT NULL,
    model_number VARCHAR(255) NOT NULL,
    serial_number VARCHAR(255) UNIQUE NOT NULL,
    product_number VARCHAR(255),

    -- Electrical specs
    volts VARCHAR(50),
    phase INTEGER,
    hertz INTEGER,
    min_volts INTEGER,
    max_volts INTEGER,
    rla DECIMAL(6,2),
    lra DECIMAL(6,2),
    min_circuit_amps DECIMAL(6,2),
    max_fuse INTEGER,
    max_breaker INTEGER,

    -- Fan specs
    fan_volts VARCHAR(50),
    fan_fla DECIMAL(6,2),

    -- Pressure specs
    hi_psi INTEGER,
    lo_psi INTEGER,
    design_pressure VARCHAR(100),
    test_pressure_gauge VARCHAR(100),

    -- Charge info
    factory_charged DECIMAL(6,2),
    piston_indoor INTEGER,
    piston_outdoor INTEGER,
    indoor_txv_sub_cool INTEGER,

    created_at TIMESTAMP DEFAULT NOW()
);

-- HVAC units (main entity)
CREATE TABLE hvac_units (
    pk_serial_number VARCHAR(100) PRIMARY KEY,
    fk_location_id UUID NOT NULL REFERENCES locations(id),
    fk_provider_id UUID NOT NULL REFERENCES service_providers(id),

    -- Equipment references
    fk_air_handler_id UUID REFERENCES air_handler_equipment(id),
    fk_compressor_id UUID REFERENCES compressor_equipment(id),

    -- Current operational state (updated from telemetry)
    current_state JSONB,
    last_telemetry_at TIMESTAMP,

    -- Installation info
    installed_by VARCHAR(255), -- Name of technician
    installation_date DATE,
    installation_notes TEXT,

    -- Configuration
    refrigerant_type refrigerant_enum DEFAULT 'R410A',
    fast_scan_enabled BOOLEAN DEFAULT false,
    fast_scan_until TIMESTAMP,

    -- Status (uptime_days will be updated from IoT logs)
    is_active BOOLEAN DEFAULT true,
    uptime_days INTEGER DEFAULT 0,

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_units_location ON hvac_units(fk_location_id);
CREATE INDEX idx_units_provider ON hvac_units(fk_provider_id);
CREATE INDEX idx_units_active ON hvac_units(is_active) WHERE is_active = true;

-- =====================================================
-- TELEMETRY & TIME-SERIES DATA
-- =====================================================

-- Partitioned table for high-volume telemetry data
CREATE TABLE hvac_telemetry (
    pk_fk_serial_number VARCHAR(100) NOT NULL REFERENCES hvac_units(pk_serial_number),
    pk_timestamp TIMESTAMP NOT NULL,

    -- Compressor readings
    pressure_suction DECIMAL(6,2),
    pressure_liquid DECIMAL(6,2),
    pressure_heat DECIMAL(6,2),
    compressor_amps DECIMAL(5,2),
    fan_amps DECIMAL(5,2),
    reversing_temp DECIMAL(5,2),
    liquid_temp DECIMAL(5,2),
    suction_temp DECIMAL(5,2),
    compressor_temp DECIMAL(5,2),
    fan_temp DECIMAL(5,2),
    ambient_temp DECIMAL(5,2),

    -- Air handler readings
    supply_air DECIMAL(5,2),
    return_air DECIMAL(5,2),
    final_rms_voltage DECIMAL(5,2),
    blower_amps DECIMAL(5,2),
    peak_pressure DECIMAL(6,2),

    -- Status flags
    fuse_ok SMALLINT,
    float_sw_ok SMALLINT,
    call_4_cool SMALLINT,
    call_4_fan SMALLINT,
    call_4_heat SMALLINT,
    pan_wet SMALLINT,
    heartbeat_ok SMALLINT,
    a2l_detected SMALLINT,
    uptime_days INTEGER,

    PRIMARY KEY (pk_fk_serial_number, pk_timestamp)
) PARTITION BY RANGE (pk_timestamp);

-- Create initial monthly partitions
CREATE TABLE hvac_telemetry_2025_01 PARTITION OF hvac_telemetry
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE hvac_telemetry_2025_02 PARTITION OF hvac_telemetry
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');

-- Index for efficient queries
CREATE INDEX idx_telemetry_serial_time ON hvac_telemetry (pk_fk_serial_number, pk_timestamp DESC);

-- Hourly aggregated telemetry (kept for 90 days)
CREATE TABLE hvac_telemetry_hourly (
    pk_fk_serial_number VARCHAR(100) NOT NULL REFERENCES hvac_units(pk_serial_number),
    pk_hour TIMESTAMP NOT NULL,

    -- Aggregated metrics stored as JSONB
    -- Format: {field_name: {min: x, max: y, avg: z}, ...}
    metrics JSONB NOT NULL,

    -- Number of raw readings in this hour (normally 360 if every 10 seconds)
    sample_count INTEGER NOT NULL,

    PRIMARY KEY (pk_fk_serial_number, pk_hour)
);

CREATE INDEX idx_telemetry_hourly_time ON hvac_telemetry_hourly (pk_hour DESC);

-- Daily aggregated telemetry (kept indefinitely)
CREATE TABLE hvac_telemetry_daily (
    pk_fk_serial_number VARCHAR(100) NOT NULL REFERENCES hvac_units(pk_serial_number),
    pk_date DATE NOT NULL,

    metrics JSONB NOT NULL,
    sample_count INTEGER NOT NULL,

    PRIMARY KEY (pk_fk_serial_number, pk_date)
);

CREATE INDEX idx_telemetry_daily_date ON hvac_telemetry_daily (pk_date DESC);

-- =====================================================
-- ALERTS SYSTEM
-- =====================================================

-- Alert rules that trigger based on telemetry values
CREATE TABLE alert_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,

    -- Condition
    field_name VARCHAR(100) NOT NULL,
    operator VARCHAR(10) NOT NULL CHECK (operator IN ('>', '<', '>=', '<=', '=', '!=')),
    threshold_value DECIMAL(10,2) NOT NULL,

    -- Optional: only apply to specific units or providers
    fk_provider_id UUID REFERENCES service_providers(id),
    fk_serial_number VARCHAR(100) REFERENCES hvac_units(pk_serial_number),

    -- Alert configuration
    severity VARCHAR(20) DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_rules_active ON alert_rules(is_active) WHERE is_active = true;

-- Triggered alerts
CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fk_rule_id UUID NOT NULL REFERENCES alert_rules(id),
    fk_serial_number VARCHAR(100) NOT NULL REFERENCES hvac_units(pk_serial_number),

    -- Alert details
    triggered_at TIMESTAMP NOT NULL DEFAULT NOW(),
    triggered_value DECIMAL(10,2) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    message TEXT,

    -- Prevent duplicate alerts within same minute
    UNIQUE(fk_rule_id, fk_serial_number, triggered_at)
);

CREATE INDEX idx_alerts_serial ON alerts(fk_serial_number, triggered_at DESC);
CREATE INDEX idx_alerts_unack ON alerts(is_acknowledged) WHERE is_acknowledged = false;

-- =====================================================
-- MEDIA STORAGE
-- =====================================================

-- Simplified media table for installation photos
CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    fk_serial_number VARCHAR(100) REFERENCES hvac_units(pk_serial_number),
    fk_location_id UUID REFERENCES locations(id),

    description TEXT,
    s3_key VARCHAR(500) NOT NULL, -- S3 object key/URL

    uploaded_by VARCHAR(255), -- Name of person who uploaded
    uploaded_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_media_serial ON media(fk_serial_number);
CREATE INDEX idx_media_location ON media(fk_location_id);

-- =====================================================
-- HELPER FUNCTIONS
-- =====================================================

-- Function to automatically create monthly partitions
CREATE OR REPLACE FUNCTION create_monthly_partition()
RETURNS void AS $$
DECLARE
    start_date DATE;
    end_date DATE;
    partition_name TEXT;
BEGIN
    -- Get the first day of next month
    start_date := DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month');
    end_date := start_date + INTERVAL '1 month';
    partition_name := 'hvac_telemetry_' || TO_CHAR(start_date, 'YYYY_MM');

    -- Check if partition already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = partition_name
    ) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF hvac_telemetry FOR VALUES FROM (%L) TO (%L)',
            partition_name, start_date, end_date
        );
        RAISE NOTICE 'Created partition: %', partition_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old telemetry data
CREATE OR REPLACE FUNCTION cleanup_old_telemetry()
RETURNS void AS $$
BEGIN
    -- Delete raw data older than 30 days
    DELETE FROM hvac_telemetry WHERE pk_timestamp < NOW() - INTERVAL '30 days';

    -- Delete hourly data older than 90 days
    DELETE FROM hvac_telemetry_hourly WHERE pk_hour < NOW() - INTERVAL '90 days';

    -- Daily data kept indefinitely
    RAISE NOTICE 'Cleanup completed at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- Trigger to update hvac_units current state and uptime
CREATE OR REPLACE FUNCTION update_unit_current_state()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE hvac_units
    SET
        current_state = row_to_json(NEW)::jsonb - 'pk_fk_serial_number' - 'pk_timestamp',
        last_telemetry_at = NEW.pk_timestamp,
        uptime_days = NEW.uptime_days,
        updated_at = NOW()
    WHERE pk_serial_number = NEW.pk_fk_serial_number;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_current_state_trigger
AFTER INSERT ON hvac_telemetry
FOR EACH ROW EXECUTE FUNCTION update_unit_current_state();

-- Schedule monthly partition creation (requires pg_cron extension)
SELECT cron.schedule('create-monthly-partition', '0 0 25 * *', 'SELECT create_monthly_partition()');
SELECT cron.schedule('cleanup-old-telemetry', '0 2 * * *', 'SELECT cleanup_old_telemetry()');
