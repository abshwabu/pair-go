package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/httpapi"
	"github.com/abshwabu/pair/backend/internal/jobs"
	"github.com/abshwabu/pair/backend/internal/matching"
	"github.com/abshwabu/pair/backend/internal/notifications"
	"github.com/abshwabu/pair/backend/internal/storage"
	"github.com/abshwabu/pair/backend/internal/users"
)

func main() {
	// Initialize structured logger
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	slog.Info("Starting Pair backend server...")

	makeAdminEmail := flag.String("make-admin", "", "Email of the user to promote to administrator")
	flag.Parse()

	// 1. Load configuration
	cfg, err := config.Load()
	if err != nil {
		slog.Error("Failed to load configuration", "error", err)
		os.Exit(1)
	}

	// 2. Initialize database and run migrations
	database, err := db.Open(cfg.DBPath)
	if err != nil {
		slog.Error("Failed to initialize database", "error", err)
		os.Exit(1)
	}
	defer func() {
		if err := database.Close(); err != nil {
			slog.Error("Error closing database connections", "error", err)
		}
	}()

	// Initialize users repository
	usersRepo := users.NewRepository(database.Write, database.Read)

	// Handle CLI helper: promote user to administrator
	if *makeAdminEmail != "" {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		if err := usersRepo.SetAdmin(ctx, *makeAdminEmail, true); err != nil {
			slog.Error("Failed to promote user to admin", "email", *makeAdminEmail, "error", err)
			os.Exit(1)
		}
		slog.Info("Successfully promoted user to admin", "email", *makeAdminEmail)
		return
	}

	// 3. Initialize storage service
	var storageService storage.StorageService
	if cfg.S3AccessKey != "" || cfg.S3Endpoint != "" {
		s3Storage, err := storage.NewS3StorageFromConfig(context.Background(), cfg)
		if err != nil {
			slog.Error("Failed to initialize S3 storage", "error", err)
			os.Exit(1)
		}
		storageService = s3Storage
	} else {
		slog.Info("S3 storage not configured; using in-memory storage")
		storageService = storage.NewFakeStorage(cfg.S3PublicBaseURL)
	}

	// 4. Initialize matching worker and start background processing
	matchingRepo := matching.NewRepository(database.Write, database.Read)
	matchingWorker := matching.NewWorker(matchingRepo)
	workerCtx, workerCancel := context.WithCancel(context.Background())
	defer workerCancel()
	go matchingWorker.Start(workerCtx)

	// 5. Initialize notifications service and FCM client
	notificationsRepo := notifications.NewRepository(database.Write, database.Read)
	notifService := notifications.NewService(notificationsRepo, database.Read)

	var fcmClient notifications.FCMClient
	if cfg.FCMCredentialsJSON != "" && cfg.FCMProjectID != "" {
		client, err := notifications.NewGoogleFCMClient(context.Background(), cfg.FCMProjectID, cfg.FCMCredentialsJSON)
		if err != nil {
			slog.Warn("Failed to initialize Google FCM client, push notifications disabled", "error", err)
			fcmClient = notifications.NewNoopFCMClient()
		} else {
			fcmClient = client
		}
	} else {
		fcmClient = notifications.NewNoopFCMClient()
	}

	notificationsWorker := notifications.NewWorker(notificationsRepo, usersRepo, fcmClient, notifService.NotifyChan())
	go notificationsWorker.Start(workerCtx)

	// 6. Initialize in-memory WebSocket chat hub
	chatHub := chat.NewHub()

	// 7. Initialize scheduled jobs (daily streak resets at 00:05 UTC)
	jobScheduler := jobs.NewScheduler()
	if _, err := jobScheduler.RegisterDailyStreakReset(database.Write, database.Read, notifService); err != nil {
		slog.Error("Failed to register daily streak reset cron job", "error", err)
	}
	jobScheduler.Start()

	// 8. Initialize HTTP router
	router := httpapi.NewRouterWithWorker(cfg, database, storageService, matchingWorker, chatHub)

	// 7. Configure HTTP server
	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", cfg.Port),
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// 7. Start HTTP server in a separate goroutine
	shutdownChan := make(chan os.Signal, 1)
	signal.Notify(shutdownChan, os.Interrupt, syscall.SIGTERM)

	serverErrors := make(chan error, 1)
	go func() {
		slog.Info("HTTP server listening", "port", cfg.Port, "addr", server.Addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()

	// 8. Wait for termination signal or server error
	select {
	case err := <-serverErrors:
		slog.Error("Server error occurred", "error", err)
		os.Exit(1)
	case sig := <-shutdownChan:
		slog.Info("Received shutdown signal", "signal", sig.String())
	}

	// 9. Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	slog.Info("Shutting down HTTP server...")
	if err := server.Shutdown(ctx); err != nil {
		slog.Error("Server forced to shutdown", "error", err)
		if closeErr := server.Close(); closeErr != nil {
			slog.Error("Error closing server listener", "error", closeErr)
		}
	}

	workerCancel()
	jobScheduler.Stop()
	slog.Info("Server stopped cleanly.")
}
