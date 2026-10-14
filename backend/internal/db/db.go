package db

import (
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"time"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite"

	"github.com/abshwabu/pair/backend/migrations"
)

// DB encapsulates both the single write connection and the read connection pool
// according to SQLite concurrency rules.
type DB struct {
	Write *sql.DB
	Read  *sql.DB
}

// Close closes both the write and read database connection pools.
func (d *DB) Close() error {
	var errs []error
	if d.Write != nil {
		if err := d.Write.Close(); err != nil {
			errs = append(errs, fmt.Errorf("error closing write db: %w", err))
		}
	}
	if d.Read != nil {
		if err := d.Read.Close(); err != nil {
			errs = append(errs, fmt.Errorf("error closing read db: %w", err))
		}
	}
	if len(errs) > 0 {
		return errors.Join(errs...)
	}
	return nil
}

// Open initializes the SQLite database with WAL mode, foreign keys, and busy timeout,
// configures a single write handle and a separate read pool, and runs embedded migrations.
func Open(dbPath string) (*DB, error) {
	// Ensure parent directory exists (especially important for mounted Docker volumes like /data)
	dir := filepath.Dir(dbPath)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create database directory %s: %w", dir, err)
		}
	}

	// SQLite DSN with PRAGMA settings applied to every connection
	dsn := fmt.Sprintf("%s?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=synchronous(NORMAL)", dbPath)

	// 1. Initialize the Write handle with MaxOpenConns = 1
	writeDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open write db handle: %w", err)
	}
	writeDB.SetMaxOpenConns(1)
	writeDB.SetMaxIdleConns(1)

	if err := configurePragmas(writeDB); err != nil {
		_ = writeDB.Close()
		return nil, fmt.Errorf("failed to configure pragmas on write db: %w", err)
	}

	if err := writeDB.Ping(); err != nil {
		_ = writeDB.Close()
		return nil, fmt.Errorf("failed to ping write db: %w", err)
	}

	// 2. Run embedded goose migrations on startup on the write handle
	if err := RunMigrations(writeDB); err != nil {
		_ = writeDB.Close()
		return nil, fmt.Errorf("failed to run database migrations: %w", err)
	}

	// 3. Initialize the Read handle pool
	readDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		_ = writeDB.Close()
		return nil, fmt.Errorf("failed to open read db handle: %w", err)
	}

	maxReadConns := runtime.NumCPU() * 2
	if maxReadConns < 4 {
		maxReadConns = 4
	}
	readDB.SetMaxOpenConns(maxReadConns)
	readDB.SetMaxIdleConns(maxReadConns / 2)
	readDB.SetConnMaxLifetime(1 * time.Hour)
	readDB.SetConnMaxIdleTime(15 * time.Minute)

	if err := configurePragmas(readDB); err != nil {
		_ = writeDB.Close()
		_ = readDB.Close()
		return nil, fmt.Errorf("failed to configure pragmas on read db: %w", err)
	}

	if err := readDB.Ping(); err != nil {
		_ = writeDB.Close()
		_ = readDB.Close()
		return nil, fmt.Errorf("failed to ping read db: %w", err)
	}

	slog.Info("SQLite database initialized successfully", "path", dbPath, "max_read_conns", maxReadConns)

	return &DB{
		Write: writeDB,
		Read:  readDB,
	}, nil
}

func configurePragmas(db *sql.DB) error {
	pragmas := []string{
		"PRAGMA journal_mode = WAL;",
		"PRAGMA busy_timeout = 5000;",
		"PRAGMA foreign_keys = ON;",
		"PRAGMA synchronous = NORMAL;",
	}
	for _, p := range pragmas {
		if _, err := db.Exec(p); err != nil {
			return fmt.Errorf("executing %q: %w", p, err)
		}
	}
	return nil
}

// RunMigrations applies all pending migrations using the embedded migrations filesystem.
func RunMigrations(db *sql.DB) error {
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("sqlite3"); err != nil {
		return fmt.Errorf("set dialect: %w", err)
	}
	if err := goose.Up(db, "."); err != nil {
		return fmt.Errorf("goose up: %w", err)
	}
	return nil
}

// RollbackAll rolls back all applied migrations down to 0 using embedded migrations filesystem.
func RollbackAll(db *sql.DB) error {
	goose.SetBaseFS(migrations.FS)
	if err := goose.SetDialect("sqlite3"); err != nil {
		return fmt.Errorf("set dialect: %w", err)
	}
	if err := goose.Reset(db, "."); err != nil {
		return fmt.Errorf("goose reset: %w", err)
	}
	return nil
}
