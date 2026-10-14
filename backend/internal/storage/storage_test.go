package storage_test

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/s3"

	"github.com/abshwabu/pair/backend/internal/storage"
)

type mockS3Client struct {
	putFn    func(ctx context.Context, params *s3.PutObjectInput, optFns ...func(*s3.Options)) (*s3.PutObjectOutput, error)
	deleteFn func(ctx context.Context, params *s3.DeleteObjectInput, optFns ...func(*s3.Options)) (*s3.DeleteObjectOutput, error)
}

func (m *mockS3Client) PutObject(ctx context.Context, params *s3.PutObjectInput, optFns ...func(*s3.Options)) (*s3.PutObjectOutput, error) {
	if m.putFn != nil {
		return m.putFn(ctx, params, optFns...)
	}
	return &s3.PutObjectOutput{}, nil
}

func (m *mockS3Client) DeleteObject(ctx context.Context, params *s3.DeleteObjectInput, optFns ...func(*s3.Options)) (*s3.DeleteObjectOutput, error) {
	if m.deleteFn != nil {
		return m.deleteFn(ctx, params, optFns...)
	}
	return &s3.DeleteObjectOutput{}, nil
}

func TestFakeStorage(t *testing.T) {
	fake := storage.NewFakeStorage("http://localhost:9000/pair-media")
	ctx := context.Background()

	key := "avatars/user-1/test.png"
	content := []byte("fake-png-content")
	contentType := "image/png"

	url, err := fake.Upload(ctx, key, bytes.NewReader(content), contentType)
	if err != nil {
		t.Fatalf("unexpected upload error: %v", err)
	}

	expectedURL := "http://localhost:9000/pair-media/avatars/user-1/test.png"
	if url != expectedURL {
		t.Errorf("expected URL %q, got %q", expectedURL, url)
	}

	gotBytes, ok := fake.GetFile(key)
	if !ok || string(gotBytes) != string(content) {
		t.Errorf("expected file content %q, got %q (ok=%v)", string(content), string(gotBytes), ok)
	}

	gotCT, ok := fake.GetContentType(key)
	if !ok || gotCT != contentType {
		t.Errorf("expected content type %q, got %q", contentType, gotCT)
	}

	if err := fake.Delete(ctx, key); err != nil {
		t.Fatalf("failed to delete file: %v", err)
	}

	if fake.HasFile(key) {
		t.Errorf("expected file to be deleted")
	}
}

func TestS3Storage_UploadAndDelete(t *testing.T) {
	var capturedPutKey, capturedPutBucket, capturedPutCT string
	var capturedDeleteKey string

	mockClient := &mockS3Client{
		putFn: func(ctx context.Context, params *s3.PutObjectInput, optFns ...func(*s3.Options)) (*s3.PutObjectOutput, error) {
			if params.Bucket != nil {
				capturedPutBucket = *params.Bucket
			}
			if params.Key != nil {
				capturedPutKey = *params.Key
			}
			if params.ContentType != nil {
				capturedPutCT = *params.ContentType
			}
			return &s3.PutObjectOutput{}, nil
		},
		deleteFn: func(ctx context.Context, params *s3.DeleteObjectInput, optFns ...func(*s3.Options)) (*s3.DeleteObjectOutput, error) {
			if params.Key != nil {
				capturedDeleteKey = *params.Key
			}
			return &s3.DeleteObjectOutput{}, nil
		},
	}

	s3Store := storage.NewS3Storage(mockClient, "pair-media", "http://localhost:9000/pair-media/")
	ctx := context.Background()

	key := "avatars/123/avatar.jpg"
	url, err := s3Store.Upload(ctx, key, strings.NewReader("dummy-image"), "image/jpeg")
	if err != nil {
		t.Fatalf("unexpected upload error: %v", err)
	}

	expectedURL := "http://localhost:9000/pair-media/avatars/123/avatar.jpg"
	if url != expectedURL {
		t.Errorf("expected URL %q, got %q", expectedURL, url)
	}

	if capturedPutBucket != "pair-media" {
		t.Errorf("expected bucket pair-media, got %s", capturedPutBucket)
	}
	if capturedPutKey != key {
		t.Errorf("expected key %s, got %s", key, capturedPutKey)
	}
	if capturedPutCT != "image/jpeg" {
		t.Errorf("expected content-type image/jpeg, got %s", capturedPutCT)
	}

	if err := s3Store.Delete(ctx, key); err != nil {
		t.Fatalf("unexpected delete error: %v", err)
	}
	if capturedDeleteKey != key {
		t.Errorf("expected deleted key %s, got %s", key, capturedDeleteKey)
	}
}
