package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all configuration values for the Pair backend.
type Config struct {
	Port   string
	DBPath string

	// Auth & Token settings (Opaque bearer tokens, no JWT)
	TokenExpiryDays int
	TokenByteLength int

	// S3 Compatible Storage
	S3Endpoint      string
	S3Bucket        string
	S3Region        string
	S3AccessKey     string
	S3SecretKey     string
	S3UseSSL        bool
	S3PublicBaseURL string

	// Firebase Cloud Messaging
	FCMCredentialsJSON string
	FCMProjectID       string
}

// TokenExpiryDuration returns the duration of token validity.
func (c *Config) TokenExpiryDuration() time.Duration {
	return time.Duration(c.TokenExpiryDays) * 24 * time.Hour
}

// Load loads configuration from environment variables with safe defaults.
func Load() (*Config, error) {
	cfg := &Config{
		Port:               getEnv("PORT", "8080"),
		DBPath:             getEnv("DB_PATH", "pair.db"),
		TokenExpiryDays:    getEnvInt("TOKEN_EXPIRY_DAYS", 30),
		TokenByteLength:    getEnvInt("TOKEN_BYTE_LENGTH", 32),
		S3Endpoint:         getEnv("S3_ENDPOINT", ""),
		S3Bucket:           getEnv("S3_BUCKET", "pair-media"),
		S3Region:           getEnv("S3_REGION", "us-east-1"),
		S3AccessKey:        getEnv("S3_ACCESS_KEY", ""),
		S3SecretKey:        getEnv("S3_SECRET_KEY", ""),
		S3UseSSL:           getEnvBool("S3_USE_SSL", false),
		S3PublicBaseURL:    getEnv("S3_PUBLIC_BASE_URL", "http://localhost:9000/pair-media"),
		FCMCredentialsJSON: getEnv("FCM_CREDENTIALS_JSON", ""),
		FCMProjectID:       getEnv("FCM_PROJECT_ID", ""),
	}

	if cfg.Port == "" {
		return nil, fmt.Errorf("PORT cannot be empty")
	}
	if cfg.DBPath == "" {
		return nil, fmt.Errorf("DB_PATH cannot be empty")
	}

	return cfg, nil
}

func getEnv(key, defaultVal string) string {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		return val
	}
	return defaultVal
}

func getEnvInt(key string, defaultVal int) int {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		if parsed, err := strconv.Atoi(val); err == nil {
			return parsed
		}
	}
	return defaultVal
}

func getEnvBool(key string, defaultVal bool) bool {
	if val, ok := os.LookupEnv(key); ok && val != "" {
		if parsed, err := strconv.ParseBool(val); err == nil {
			return parsed
		}
	}
	return defaultVal
}
