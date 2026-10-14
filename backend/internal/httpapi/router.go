package httpapi

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/chat"
	"github.com/abshwabu/pair/backend/internal/config"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/goals"
	"github.com/abshwabu/pair/backend/internal/matching"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/storage"
	"github.com/abshwabu/pair/backend/internal/todos"
	"github.com/abshwabu/pair/backend/internal/users"
)

// NewRouter sets up the Chi router with optional storage service.
func NewRouter(cfg *config.Config, database *db.DB, storageServices ...storage.StorageService) chi.Router {
	var storageService storage.StorageService
	if len(storageServices) > 0 && storageServices[0] != nil {
		storageService = storageServices[0]
	} else {
		storageService = storage.NewFakeStorage(cfg.S3PublicBaseURL)
	}
	return NewRouterWithWorker(cfg, database, storageService, nil)
}

// NewRouterWithWorker sets up the Chi router with explicit storage, matching worker, and optional chat hub dependencies.
func NewRouterWithWorker(cfg *config.Config, database *db.DB, storageService storage.StorageService, worker *matching.Worker, chatHubs ...*chat.Hub) chi.Router {
	r := chi.NewRouter()

	// Standard chi middlewares
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(60 * time.Second))

	// CORS configuration
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token", "X-Request-Id"},
		ExposedHeaders:   []string{"Link", "X-Request-Id"},
		AllowCredentials: false,
		MaxAge:           300,
	}))

	// Repositories and handlers
	authRepo := auth.NewRepository(database.Write, database.Read)
	usersRepo := users.NewRepository(database.Write, database.Read)
	authHandler := NewAuthHandler(authRepo, usersRepo)
	authMW := AuthMiddleware(authRepo, usersRepo)

	if storageService == nil {
		storageService = storage.NewFakeStorage(cfg.S3PublicBaseURL)
	}
	profileHandler := NewProfileHandler(usersRepo, storageService)

	goalsRepo := goals.NewRepository(database.Write, database.Read)
	goalsHandler := goals.NewHandler(goalsRepo)

	matchingRepo := matching.NewRepository(database.Write, database.Read)
	if worker == nil {
		worker = matching.NewWorker(matchingRepo)
	}
	matchingHandler := matching.NewHandler(matchingRepo, goalsRepo, worker)

	podsRepo := pods.NewRepository(database.Write, database.Read)
	podsHandler := pods.NewHandler(podsRepo)

	todosRepo := todos.NewRepository(database.Write, database.Read)
	todosHandler := todos.NewHandler(todosRepo)

	var chatHub *chat.Hub
	if len(chatHubs) > 0 && chatHubs[0] != nil {
		chatHub = chatHubs[0]
	} else {
		chatHub = chat.NewHub()
	}
	chatRepo := chat.NewRepository(database.Write, database.Read)
	chatHandler := chat.NewHandler(chatRepo, chatHub)

	// /healthz endpoint - responds with HTTP 200 and standard envelope
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		dbStatus := "ok"
		if err := database.Write.PingContext(r.Context()); err != nil {
			dbStatus = "degraded"
		}

		OK(w, http.StatusOK, map[string]any{
			"status":   "ok",
			"database": dbStatus,
			"time":     time.Now().UTC().Format(time.RFC3339),
		})
	})

	// REST API v1 routes
	r.Route("/api/v1", func(r chi.Router) {
		r.Get("/ping", func(w http.ResponseWriter, r *http.Request) {
			OK(w, http.StatusOK, map[string]string{
				"message": "pong",
			})
		})

		// Auth routes
		r.Route("/auth", func(r chi.Router) {
			r.Post("/register", authHandler.Register)
			r.Post("/login", authHandler.Login)

			// Authenticated routes
			r.Group(func(r chi.Router) {
				r.Use(authMW)
				r.Post("/logout", authHandler.Logout)
				r.Get("/me", authHandler.Me)
			})
		})

		// Profile routes (all require authentication)
		r.Route("/profile", func(r chi.Router) {
			r.Use(authMW)
			r.Get("/", profileHandler.GetProfile)
			r.Patch("/", profileHandler.UpdateProfile)
			r.Post("/avatar", profileHandler.UploadAvatar)
		})

		// Goal routes (all require authentication)
		r.Route("/goals", func(r chi.Router) {
			r.Use(authMW)
			r.Post("/", goalsHandler.Create)
			r.Get("/", goalsHandler.List)
			r.Get("/{id}", goalsHandler.GetByID)
			r.Patch("/{id}", goalsHandler.Update)
			r.Delete("/{id}", goalsHandler.Delete)
		})

		// Matching routes (all require authentication)
		matchingHandler.RegisterRoutes(r, authMW)

		// Pods, Todos, and Chat routes (all require authentication and active membership)
		r.Route("/pods", func(r chi.Router) {
			r.Use(authMW)
			r.Get("/", podsHandler.List)

			r.Route("/{pod}", func(r chi.Router) {
				r.Use(pods.RequireMember())
				r.Get("/", podsHandler.GetByID)
				r.Post("/leave", podsHandler.Leave)

				// Todo routes
				r.Route("/todos", func(r chi.Router) {
					r.Get("/", todosHandler.List)
					r.Post("/", todosHandler.Create)
					r.Route("/{todo}", func(r chi.Router) {
						r.Patch("/", todosHandler.Update)
						r.Delete("/", todosHandler.Delete)
					})
				})

				// Chat routes (WebSocket + REST)
				r.Get("/ws", chatHandler.ServeWS)
				r.Get("/messages", chatHandler.ListMessages)
				r.Post("/messages", chatHandler.SendMessage)
				r.Post("/typing", chatHandler.SendTyping)
			})
		})
	})

	return r
}
