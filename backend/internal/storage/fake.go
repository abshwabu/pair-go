package storage

import (
	"context"
	"fmt"
	"io"
	"strings"
	"sync"
)

// FakeStorage is a thread-safe in-memory implementation of StorageService for tests.
type FakeStorage struct {
	mu            sync.RWMutex
	files         map[string][]byte
	contentTypes  map[string]string
	publicBaseURL string
}

// NewFakeStorage creates a new FakeStorage instance.
func NewFakeStorage(publicBaseURL string) *FakeStorage {
	if publicBaseURL == "" {
		publicBaseURL = "http://localhost:9000/pair-media"
	}
	return &FakeStorage{
		files:         make(map[string][]byte),
		contentTypes:  make(map[string]string),
		publicBaseURL: publicBaseURL,
	}
}

// Upload stores file bytes in memory and returns the public URL.
func (f *FakeStorage) Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error) {
	data, err := io.ReadAll(body)
	if err != nil {
		return "", fmt.Errorf("failed to read body: %w", err)
	}

	f.mu.Lock()
	defer f.mu.Unlock()

	f.files[key] = data
	f.contentTypes[key] = contentType

	return f.GetURL(key), nil
}

// Delete removes a file from memory.
func (f *FakeStorage) Delete(ctx context.Context, key string) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	delete(f.files, key)
	delete(f.contentTypes, key)
	return nil
}

// GetURL returns the public URL for a key.
func (f *FakeStorage) GetURL(key string) string {
	base := strings.TrimRight(f.publicBaseURL, "/")
	cleanKey := strings.TrimLeft(key, "/")
	return fmt.Sprintf("%s/%s", base, cleanKey)
}

// GetFile retrieves the stored bytes for a key.
func (f *FakeStorage) GetFile(key string) ([]byte, bool) {
	f.mu.RLock()
	defer f.mu.RUnlock()

	data, ok := f.files[key]
	return data, ok
}

// GetContentType retrieves the content type for a key.
func (f *FakeStorage) GetContentType(key string) (string, bool) {
	f.mu.RLock()
	defer f.mu.RUnlock()

	ct, ok := f.contentTypes[key]
	return ct, ok
}

// HasFile checks if a file with the given key exists in memory.
func (f *FakeStorage) HasFile(key string) bool {
	f.mu.RLock()
	defer f.mu.RUnlock()

	_, ok := f.files[key]
	return ok
}
