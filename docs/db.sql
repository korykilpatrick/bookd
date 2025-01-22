-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Drop tables in reverse dependency order
DROP TABLE IF EXISTS review_helpful_votes;
DROP TABLE IF EXISTS bookshelf_works;
DROP TABLE IF EXISTS bookshelves;
DROP TABLE IF EXISTS reviews;
DROP TABLE IF EXISTS user_works;
DROP TABLE IF EXISTS work_genres;
DROP TABLE IF EXISTS work_authors;
DROP TABLE IF EXISTS editions;
DROP TABLE IF EXISTS works;
DROP TABLE IF EXISTS authors;
DROP TABLE IF EXISTS genres;
DROP TABLE IF EXISTS publishers;
DROP TABLE IF EXISTS user_follows;
DROP TABLE IF EXISTS user_reading_compatibility;
DROP TABLE IF EXISTS recommendation_results;
DROP TABLE IF EXISTS user_book_recommendations;
DROP TABLE IF EXISTS users;

-- Create custom ENUM for author roles
CREATE TYPE author_role AS ENUM (
    'author',
    'illustrator',
    'translator',
    'editor',
    'publisher',
    'other'
);

-- Create custom ENUMs
CREATE TYPE book_format AS ENUM (
    'hardcover',
    'paperback',
    'ebook',
    'audiobook',
    'mass_market_paperback',
    'library_binding',
    'spiral_bound',
    'other'
);

CREATE TYPE reading_status AS ENUM (
    'want_to_read',
    'reading',
    'read'
);

-- Create tables
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    display_name TEXT,
    bio TEXT,

    -- Keep lat/long for simple storage
    location_lat DECIMAL(9,6),
    location_long DECIMAL(9,6),
    is_location_private BOOLEAN DEFAULT false,

    -- Additional PostGIS field for advanced geo queries
    geo_location GEOGRAPHY(POINT, 4326),

    avatar_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE publishers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE works (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    description TEXT,
    language VARCHAR(10),
    cover_image_url TEXT,
    publisher_id UUID REFERENCES publishers(id) ON DELETE SET NULL,
    goodreads_url TEXT,
    goodreads_rating DECIMAL(3,2),
    average_rating DECIMAL(3,2) DEFAULT 0,
    ratings_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE editions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), 
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    isbn_10 VARCHAR(10) UNIQUE,
    isbn_13 VARCHAR(13) UNIQUE,
    title TEXT NOT NULL,
    publication_date DATE,
    page_count INTEGER,
    cover_image_url TEXT,
    publisher_id UUID REFERENCES publishers(id) ON DELETE SET NULL,
    format book_format,
    language VARCHAR(10),
    average_rating DECIMAL(3,2) DEFAULT 0,
    ratings_count INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE authors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    biography TEXT,
    photo_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE work_authors (
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    author_id UUID REFERENCES authors(id) ON DELETE CASCADE,
    author_order INTEGER,
    role author_role DEFAULT 'author',
    PRIMARY KEY (work_id, author_id)
);

CREATE TABLE genres (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    parent_genre_id UUID REFERENCES genres(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE work_genres (
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    genre_id UUID REFERENCES genres(id) ON DELETE CASCADE,
    PRIMARY KEY (work_id, genre_id)
);

CREATE TABLE user_works (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    edition_id UUID REFERENCES editions(id) ON DELETE SET NULL,
    status reading_status NOT NULL,
    progress_percent INTEGER CHECK (progress_percent BETWEEN 0 AND 100),
    start_date DATE,
    completion_date DATE,
    is_private BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, work_id)
);

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    edition_id UUID REFERENCES editions(id) ON DELETE SET NULL,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    review_text TEXT,
    contains_spoilers BOOLEAN DEFAULT false,

    -- Keep helpful_votes as a cached count
    helpful_votes INTEGER DEFAULT 0,

    is_private BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, work_id)
);

CREATE TABLE bookshelves (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT true,
    is_default BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, name)
);

CREATE TABLE bookshelf_works (
    bookshelf_id UUID REFERENCES bookshelves(id) ON DELETE CASCADE,
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (bookshelf_id, work_id)
);

CREATE TABLE user_follows (
    follower_id UUID REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (follower_id, following_id)
);

CREATE TABLE user_reading_compatibility (
    user_id1 UUID REFERENCES users(id) ON DELETE CASCADE,
    user_id2 UUID REFERENCES users(id) ON DELETE CASCADE,

    -- Score
    compatibility_score DECIMAL(4,3),
    last_calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Enforce user_id1 < user_id2 to avoid duplicates in reverse
    CONSTRAINT user_id1_less_than_user_id2 CHECK (user_id1 < user_id2),

    PRIMARY KEY (user_id1, user_id2)
);

CREATE TABLE user_book_recommendations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    query_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE recommendation_results (
    recommendation_id UUID REFERENCES user_book_recommendations(id) ON DELETE CASCADE,
    work_id UUID REFERENCES works(id) ON DELETE CASCADE,
    confidence_score DECIMAL(4,3),
    rank INTEGER,
    reasoning TEXT,
    PRIMARY KEY (recommendation_id, work_id)
);

-- Table for individual helpful votes on reviews
CREATE TABLE review_helpful_votes (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    review_id UUID REFERENCES reviews(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, review_id)
);

CREATE TABLE edition_authors (
    edition_id UUID REFERENCES editions(id) ON DELETE CASCADE,
    author_id UUID REFERENCES authors(id) ON DELETE CASCADE,
    author_order INTEGER,
    role author_role DEFAULT 'translator',
    PRIMARY KEY (edition_id, author_id, role)
);

-- Indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_location ON users(location_lat, location_long) WHERE is_location_private = false;
CREATE INDEX idx_users_geo_location ON users USING GIST (geo_location);

CREATE INDEX idx_works_title ON works(title);
CREATE INDEX idx_works_ratings ON works(average_rating, ratings_count);

CREATE INDEX idx_editions_work_id ON editions(work_id);
CREATE INDEX idx_editions_isbn ON editions(isbn_10, isbn_13);
CREATE INDEX idx_editions_pub_date ON editions(publication_date);

CREATE INDEX idx_authors_name ON authors(name);

CREATE INDEX idx_work_authors_work_id ON work_authors(work_id);
CREATE INDEX idx_work_authors_author_id ON work_authors(author_id);
CREATE INDEX idx_work_genres_work_id ON work_genres(work_id);
CREATE INDEX idx_work_genres_genre_id ON work_genres(genre_id);

CREATE INDEX idx_user_works_user_id ON user_works(user_id);
CREATE INDEX idx_user_works_work_id ON user_works(work_id);
CREATE INDEX idx_user_works_status ON user_works(status);

CREATE INDEX idx_reviews_user_id ON reviews(user_id);
CREATE INDEX idx_reviews_work_id ON reviews(work_id);
CREATE INDEX idx_reviews_rating ON reviews(rating);
CREATE INDEX idx_reviews_created_at ON reviews(created_at);

CREATE INDEX idx_bookshelves_user_id ON bookshelves(user_id);
CREATE INDEX idx_bookshelf_works_shelf_id ON bookshelf_works(bookshelf_id);
CREATE INDEX idx_bookshelf_works_work_id ON bookshelf_works(work_id);

CREATE INDEX idx_user_follows_follower_id ON user_follows(follower_id);
CREATE INDEX idx_user_follows_following_id ON user_follows(following_id);

CREATE INDEX idx_user_reading_comp_uid1 ON user_reading_compatibility(user_id1);
CREATE INDEX idx_user_reading_comp_score ON user_reading_compatibility(compatibility_score);

CREATE INDEX idx_recommendation_results_work_id ON recommendation_results(work_id);
CREATE INDEX idx_recommendation_results_conf ON recommendation_results(confidence_score);

-- Trigram indexes for text search
CREATE INDEX idx_works_description_trgm ON works USING gin (description gin_trgm_ops);
CREATE INDEX idx_authors_biography_trgm ON authors USING gin (biography gin_trgm_ops);
CREATE INDEX idx_reviews_review_text_trgm ON reviews USING gin (review_text gin_trgm_ops);

CREATE INDEX idx_edition_authors_edition_id ON edition_authors(edition_id);
CREATE INDEX idx_edition_authors_author_id ON edition_authors(author_id);

-- Trigger function to update updated_at columns
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to relevant tables
CREATE TRIGGER update_works_updated_at
    BEFORE UPDATE ON works
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_editions_updated_at
    BEFORE UPDATE ON editions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_authors_updated_at
    BEFORE UPDATE ON authors
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_genres_updated_at
    BEFORE UPDATE ON genres
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_publishers_updated_at
    BEFORE UPDATE ON publishers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_works_updated_at
    BEFORE UPDATE ON user_works
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_reviews_updated_at
    BEFORE UPDATE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bookshelves_updated_at
    BEFORE UPDATE ON bookshelves
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bookshelf_works_updated_at
    BEFORE UPDATE ON bookshelf_works
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_follows_updated_at
    BEFORE UPDATE ON user_follows
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_edition_authors_updated_at
    BEFORE UPDATE ON edition_authors
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Update works' average_rating/ratings_count when reviews change
CREATE OR REPLACE FUNCTION update_work_ratings()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.work_id IS NOT NULL THEN
            UPDATE works
            SET 
                average_rating = (
                    SELECT COALESCE(AVG(rating), 0)
                    FROM reviews
                    WHERE work_id = NEW.work_id
                      AND rating IS NOT NULL
                ),
                ratings_count = (
                    SELECT COUNT(*)
                    FROM reviews
                    WHERE work_id = NEW.work_id
                      AND rating IS NOT NULL
                )
            WHERE id = NEW.work_id;
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        IF OLD.work_id IS NOT NULL THEN
            UPDATE works
            SET 
                average_rating = (
                    SELECT COALESCE(AVG(rating), 0)
                    FROM reviews
                    WHERE work_id = OLD.work_id
                      AND rating IS NOT NULL
                ),
                ratings_count = (
                    SELECT COUNT(*)
                    FROM reviews
                    WHERE work_id = OLD.work_id
                      AND rating IS NOT NULL
                )
            WHERE id = OLD.work_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_work_ratings_on_review
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_work_ratings();

-- Update editions' average_rating/ratings_count when reviews change
CREATE OR REPLACE FUNCTION update_edition_ratings()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
        IF NEW.edition_id IS NOT NULL THEN
            UPDATE editions
            SET 
                average_rating = (
                    SELECT COALESCE(AVG(rating), 0)
                    FROM reviews
                    WHERE edition_id = NEW.edition_id
                      AND rating IS NOT NULL
                ),
                ratings_count = (
                    SELECT COUNT(*)
                    FROM reviews
                    WHERE edition_id = NEW.edition_id
                      AND rating IS NOT NULL
                )
            WHERE id = NEW.edition_id;
        END IF;
    ELSIF (TG_OP = 'DELETE') THEN
        IF OLD.edition_id IS NOT NULL THEN
            UPDATE editions
            SET 
                average_rating = (
                    SELECT COALESCE(AVG(rating), 0)
                    FROM reviews
                    WHERE edition_id = OLD.edition_id
                      AND rating IS NOT NULL
                ),
                ratings_count = (
                    SELECT COUNT(*)
                    FROM reviews
                    WHERE edition_id = OLD.edition_id
                      AND rating IS NOT NULL
                )
            WHERE id = OLD.edition_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_edition_ratings_on_review
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_edition_ratings();

-- Track individual helpful votes and keep a cached count in reviews
CREATE OR REPLACE FUNCTION update_review_helpful_votes()
RETURNS TRIGGER AS $$
BEGIN
   IF TG_OP = 'INSERT' THEN
       UPDATE reviews
       SET helpful_votes = helpful_votes + 1
       WHERE id = NEW.review_id;
   ELSIF TG_OP = 'DELETE' THEN
       UPDATE reviews
       SET helpful_votes = helpful_votes - 1
       WHERE id = OLD.review_id;
   END IF;
   RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER inc_helpful_votes
    AFTER INSERT ON review_helpful_votes
    FOR EACH ROW
    EXECUTE FUNCTION update_review_helpful_votes();

CREATE TRIGGER dec_helpful_votes
    AFTER DELETE ON review_helpful_votes
    FOR EACH ROW
    EXECUTE FUNCTION update_review_helpful_votes();

-- Create default bookshelves for new users
CREATE OR REPLACE FUNCTION create_default_bookshelves()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO bookshelves (user_id, name, is_default)
    VALUES 
        (NEW.id, 'Want to Read', true),
        (NEW.id, 'Currently Reading', true),
        (NEW.id, 'Read', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER create_default_bookshelves_trigger
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION create_default_bookshelves();

-- Function to sync geo_location with lat/long
CREATE OR REPLACE FUNCTION sync_geo_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.geo_location = ST_SetSRID(ST_MakePoint(NEW.location_long, NEW.location_lat), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_user_geo_location
    BEFORE INSERT OR UPDATE OF location_lat, location_long ON users
    FOR EACH ROW
    WHEN (NEW.location_lat IS NOT NULL AND NEW.location_long IS NOT NULL)
    EXECUTE FUNCTION sync_geo_location();
