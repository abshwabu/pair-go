package storage

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"

	"github.com/abshwabu/pair/backend/internal/config"
)

// StorageService defines an interface for uploading and retrieving media files (avatars, progress proof).
type StorageService interface {
	Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error)
	Delete(ctx context.Context, key string) error
	GetURL(key string) string
}

// S3ClientAPI abstracts the PutObject and DeleteObject methods of the AWS S3 client for mocking.
type S3ClientAPI interface {
	PutObject(ctx context.Context, params *s3.PutObjectInput, optFns ...func(*s3.Options)) (*s3.PutObjectOutput, error)
	DeleteObject(ctx context.Context, params *s3.DeleteObjectInput, optFns ...func(*s3.Options)) (*s3.DeleteObjectOutput, error)
}

// S3Storage provides an S3-compatible implementation of StorageService.
type S3Storage struct {
	client        S3ClientAPI
	bucket        string
	publicBaseURL string
}

// NewS3Storage creates a new S3 storage wrapper with a given S3ClientAPI.
func NewS3Storage(client S3ClientAPI, bucket, publicBaseURL string) *S3Storage {
	return &S3Storage{
		client:        client,
		bucket:        bucket,
		publicBaseURL: publicBaseURL,
	}
}

// NewS3StorageFromConfig initializes an S3Storage instance from application config.
func NewS3StorageFromConfig(ctx context.Context, cfg *config.Config) (*S3Storage, error) {
	opts := []func(*awsconfig.LoadOptions) error{}

	region := cfg.S3Region
	if region == "" {
		region = "us-east-1"
	}
	opts = append(opts, awsconfig.WithRegion(region))

	if cfg.S3AccessKey != "" && cfg.S3SecretKey != "" {
		opts = append(opts, awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(cfg.S3AccessKey, cfg.S3SecretKey, ""),
		))
	}

	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to load AWS configuration: %w", err)
	}

	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		if cfg.S3Endpoint != "" {
			ep := cfg.S3Endpoint
			if !strings.HasPrefix(ep, "http://") && !strings.HasPrefix(ep, "https://") {
				if cfg.S3UseSSL {
					ep = "https://" + ep
				} else {
					ep = "http://" + ep
				}
			}
			o.BaseEndpoint = aws.String(ep)
		}
		o.UsePathStyle = true
	})

	return NewS3Storage(client, cfg.S3Bucket, cfg.S3PublicBaseURL), nil
}

// Upload uploads an object to the S3 bucket and returns its public URL.
func (s *S3Storage) Upload(ctx context.Context, key string, body io.Reader, contentType string) (string, error) {
	putInput := &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	}

	_, err := s.client.PutObject(ctx, putInput)
	if err != nil {
		return "", fmt.Errorf("failed to upload object to s3: %w", err)
	}

	return s.GetURL(key), nil
}

// Delete removes an object from the S3 bucket.
func (s *S3Storage) Delete(ctx context.Context, key string) error {
	deleteInput := &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}

	_, err := s.client.DeleteObject(ctx, deleteInput)
	if err != nil {
		return fmt.Errorf("failed to delete object from s3: %w", err)
	}

	return nil
}

// GetURL returns the public URL for an S3 object key.
func (s *S3Storage) GetURL(key string) string {
	base := strings.TrimRight(s.publicBaseURL, "/")
	cleanKey := strings.TrimLeft(key, "/")
	return fmt.Sprintf("%s/%s", base, cleanKey)
}
