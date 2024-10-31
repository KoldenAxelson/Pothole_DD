-- Enable PostGIS extension for location data
CREATE EXTENSION IF NOT EXISTS postgis;

-- Image metadata
CREATE TABLE images (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    s3_url TEXT NOT NULL,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending',
    location POINT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Analysis results
CREATE TABLE analysis_results (
    id SERIAL PRIMARY KEY,
    image_id INTEGER REFERENCES images(id),
    confidence DECIMAL(5,2),
    detection_boxes JSONB,
    model_version VARCHAR(50),
    processing_time INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Model performance metrics
CREATE TABLE model_metrics (
    id SERIAL PRIMARY KEY,
    model_version VARCHAR(50),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metrics JSONB,
    false_positive_rate DECIMAL(5,2),
    false_negative_rate DECIMAL(5,2)
);

-- Indexes
CREATE INDEX idx_images_status ON images(status);
CREATE INDEX idx_images_upload_date ON images(upload_date);
CREATE INDEX idx_analysis_confidence ON analysis_results(confidence);
CREATE INDEX idx_analysis_image_id ON analysis_results(image_id);
CREATE INDEX idx_model_metrics ON model_metrics(model_version);

-- Add GiST index for spatial queries
CREATE INDEX idx_images_location ON images USING GIST (location);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers for updated_at
CREATE TRIGGER update_images_timestamp
    BEFORE UPDATE ON images
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER update_analysis_results_timestamp
    BEFORE UPDATE ON analysis_results
    FOR EACH ROW
    EXECUTE FUNCTION update_timestamp();

-- Create helper function for nearby potholes
CREATE OR REPLACE FUNCTION find_nearby_potholes(
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    radius_meters INTEGER DEFAULT 100
)
RETURNS TABLE (
    id INTEGER,
    distance DOUBLE PRECISION,
    confidence DECIMAL,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        i.id,
        ST_Distance(
            i.location::geometry,
            ST_SetSRID(ST_MakePoint(lon, lat), 4326)
        ) as distance,
        ar.confidence,
        i.created_at
    FROM images i
    JOIN analysis_results ar ON i.id = ar.image_id
    WHERE ST_DWithin(
        i.location::geometry,
        ST_SetSRID(ST_MakePoint(lon, lat), 4326),
        radius_meters
    )
    AND i.status = 'processed'
    AND ar.confidence > 0.7
    ORDER BY distance;
END;
$$ LANGUAGE plpgsql;