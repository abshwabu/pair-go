package main

import (
	"context"
	"errors"
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
	"github.com/abshwabu/pair/backend/internal/storage"
)

func main() {
	// Initialize structured logger
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	slog.Info("Starting Pair backend server...")

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

	// 3. Initialize storage service
	storageService, err := storage.NewS3StorageFromConfig(context.Background(), cfg)
	if err != nil {
		slog.Error("Failed to initialize S3 storage", "error", err)
		os.Exit(1)
	}

	// 4. Initialize matching worker and start background processing
	matchingRepo := matching.NewRepository(database.Write, database.Read)
	matchingWorker := matching.NewWorker(matchingRepo)
	workerCtx, workerCancel := context.WithCancel(context.Background())
	defer workerCancel()
	go matchingWorker.Start(workerCtx)

	// 5. Initialize in-memory WebSocket chat hub
	chatHub := chat.NewHub()

	// 6. Initialize scheduled jobs (daily streak resets at 00:05 UTC)
	jobScheduler := jobs.NewScheduler()
	notifier := jobs.NewStubNotificationService()
	if _, err := jobScheduler.RegisterDailyStreakReset(database.Write, database.Read, notifier); err != nil {
		slog.Error("Failed to register daily streak reset cron job", "error", err)
	}
	jobScheduler.Start()

	// 7. Initialize HTTP router
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
