package pods_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/auth"
	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/pods"
	"github.com/abshwabu/pair/backend/internal/users"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "pods_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUserAndGoal(t *testing.T, database *db.DB, name, email string) (string, string) {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	userID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, ?, ?, 'hash', 'UTC', 'en', 0, ?, ?);
	`, userID, name, email, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}

	goalID := uuid.NewString()
	_, err = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Read Sci-Fi', 'Finish 3 books', 'steady', ?, ?);
	`, goalID, userID, now, now)
	if err != nil {
		t.Fatalf("failed to insert goal: %v", err)
	}

	return userID, goalID
}

func createTestPod(t *testing.T, database *db.DB, user1ID, goal1ID, user2ID, goal2ID string) string {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	podID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO pods (id, goal_category, status, capacity, created_at, updated_at)
		VALUES (?, 'read', 'active', 2, ?, ?);
	`, podID, now, now)
	if err != nil {
		t.Fatalf("failed to insert pod: %v", err)
	}

	// Add member 1
	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user1ID, goal1ID, now)
	if err != nil {
		t.Fatalf("failed to insert pod member 1: %v", err)
	}

	// Add member 2
	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user2ID, goal2ID, now)
	if err != nil {
		t.Fatalf("failed to insert pod member 2: %v", err)
	}

	// Add streak record
	_, err = database.Write.Exec(`
		INSERT INTO streaks (id, pod_id, current_streak, best_streak, last_check_in_date, updated_at)
		VALUES (?, ?, 5, 12, '2026-10-14', ?);
	`, uuid.NewString(), podID, now)
	if err != nil {
		t.Fatalf("failed to insert streak: %v", err)
	}

	return podID
}

func TestRepository_GetByID_NotFound(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)

	_, err := repo.GetByID(context.Background(), "non-existent-pod-id")
	if err != pods.ErrPodNotFound {
		t.Fatalf("expected ErrPodNotFound, got %v", err)
	}
}

func TestRepository_GetPodDetail_WithMembersAndStreak(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)

	u1, g1 := createTestUserAndGoal(t, database, "Alice", "alice@example.com")
	u2, g2 := createTestUserAndGoal(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, g1, u2, g2)

	detail, err := repo.GetPodDetail(context.Background(), podID)
	if err != nil {
		t.Fatalf("failed to get pod detail: %v", err)
	}

	if detail.ID != podID {
		t.Errorf("expected pod ID %s, got %s", podID, detail.ID)
	}
	if detail.GoalCategory != "read" {
		t.Errorf("expected goal category 'read', got %s", detail.GoalCategory)
	}
	if detail.Status != pods.PodStatusActive {
		t.Errorf("expected status 'active', got %s", detail.Status)
	}
	if len(detail.Members) != 2 {
		t.Fatalf("expected 2 members, got %d", len(detail.Members))
	}

	// Verify member 1 & 2 details
	foundAlice := false
	foundBob := false
	for _, m := range detail.Members {
		if m.User.ID == u1 {
			foundAlice = true
			if m.User.Name != "Alice" {
				t.Errorf("expected name Alice, got %s", m.User.Name)
			}
			if m.Goal.ID != g1 {
				t.Errorf("expected goal ID %s, got %s", g1, m.Goal.ID)
			}
			if m.Goal.Category != "read" {
				t.Errorf("expected goal category read, got %s", m.Goal.Category)
			}
		}
		if m.User.ID == u2 {
			foundBob = true
			if m.User.Name != "Bob" {
				t.Errorf("expected name Bob, got %s", m.User.Name)
			}
			if m.Goal.ID != g2 {
				t.Errorf("expected goal ID %s, got %s", g2, m.Goal.ID)
			}
		}
	}
	if !foundAlice || !foundBob {
		t.Errorf("expected both Alice and Bob in members list")
	}

	// Verify streaks
	if detail.Streak.CurrentStreak != 5 {
		t.Errorf("expected current streak 5, got %d", detail.Streak.CurrentStreak)
	}
	if detail.Streak.BestStreak != 12 {
		t.Errorf("expected best streak 12, got %d", detail.Streak.BestStreak)
	}
	if detail.Streak.LastCheckInDate == nil || *detail.Streak.LastCheckInDate != "2026-10-14" {
		t.Errorf("expected last check in date '2026-10-14', got %v", detail.Streak.LastCheckInDate)
	}
}

func TestRepository_ListActivePodsForUser(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)

	u1, g1 := createTestUserAndGoal(t, database, "User 1", "u1@example.com")
	u2, g2 := createTestUserAndGoal(t, database, "User 2", "u2@example.com")
	u3, g3 := createTestUserAndGoal(t, database, "User 3", "u3@example.com")

	pod1ID := createTestPod(t, database, u1, g1, u2, g2)
	pod2ID := createTestPod(t, database, u1, g1, u3, g3)

	// List active pods for u1 -> should have 2 pods
	list, err := repo.ListActivePodsForUser(context.Background(), u1)
	if err != nil {
		t.Fatalf("failed to list active pods: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("expected 2 active pods for u1, got %d", len(list))
	}

	// List for u2 -> should have 1 pod
	listU2, err := repo.ListActivePodsForUser(context.Background(), u2)
	if err != nil {
		t.Fatalf("failed to list active pods: %v", err)
	}
	if len(listU2) != 1 || listU2[0].ID != pod1ID {
		t.Fatalf("expected pod %s for u2, got %v", pod1ID, listU2)
	}

	// Now u1 leaves pod 1
	if err := repo.LeaveUser(context.Background(), pod1ID, u1); err != nil {
		t.Fatalf("failed to leave pod 1: %v", err)
	}

	// Now u1 should only have 1 active pod (pod2ID)
	listAfterLeave, err := repo.ListActivePodsForUser(context.Background(), u1)
	if err != nil {
		t.Fatalf("failed to list active pods after leave: %v", err)
	}
	if len(listAfterLeave) != 1 || listAfterLeave[0].ID != pod2ID {
		t.Fatalf("expected 1 active pod (%s) for u1, got %d", pod2ID, len(listAfterLeave))
	}
}

func TestRepository_LeaveUser_DissolvesPod(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)

	u1, g1 := createTestUserAndGoal(t, database, "User 1", "u1@example.com")
	u2, g2 := createTestUserAndGoal(t, database, "User 2", "u2@example.com")
	podID := createTestPod(t, database, u1, g1, u2, g2)

	// User 1 leaves
	err := repo.LeaveUser(context.Background(), podID, u1)
	if err != nil {
		t.Fatalf("LeaveUser failed: %v", err)
	}

	// Check pod status: active members was 2, now 1 (< 2), so status must be dissolved
	pod, err := repo.GetByID(context.Background(), podID)
	if err != nil {
		t.Fatalf("GetByID failed: %v", err)
	}
	if pod.Status != pods.PodStatusDissolved {
		t.Errorf("expected pod status dissolved, got %s", pod.Status)
	}

	// User 1 trying to leave again should return ErrAlreadyLeft
	err = repo.LeaveUser(context.Background(), podID, u1)
	if err != pods.ErrAlreadyLeft {
		t.Fatalf("expected ErrAlreadyLeft, got %v", err)
	}

	// User 3 (not a member) trying to leave should return ErrNotMember
	u3, _ := createTestUserAndGoal(t, database, "User 3", "u3@example.com")
	err = repo.LeaveUser(context.Background(), podID, u3)
	if err != pods.ErrNotMember {
		t.Fatalf("expected ErrNotMember, got %v", err)
	}

	// Leaving non-existent pod should return ErrPodNotFound
	err = repo.LeaveUser(context.Background(), "unknown-pod", u1)
	if err != pods.ErrPodNotFound {
		t.Fatalf("expected ErrPodNotFound, got %v", err)
	}
}

func TestRequireMember_Middleware(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)
	pods.SetDefaultRepository(repo)

	u1, g1 := createTestUserAndGoal(t, database, "User 1", "u1@example.com")
	u2, g2 := createTestUserAndGoal(t, database, "User 2", "u2@example.com")
	u3, _ := createTestUserAndGoal(t, database, "User 3", "u3@example.com")
	podID := createTestPod(t, database, u1, g1, u2, g2)

	// Router with RequireMember middleware
	r := chi.NewRouter()
	r.Route("/pods/{id}", func(r chi.Router) {
		r.Use(pods.RequireMember())
		r.Get("/test", func(w http.ResponseWriter, r *http.Request) {
			pod, ok := pods.PodFromContext(r.Context())
			if !ok || pod == nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			member, ok := pods.PodMemberFromContext(r.Context())
			if !ok || member == nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.WriteHeader(http.StatusOK)
		})
	})

	// Case 1: Member u1 accesses the route -> 200 OK
	req1 := httptest.NewRequest(http.MethodGet, "/pods/"+podID+"/test", nil)
	req1 = req1.WithContext(auth.WithUser(req1.Context(), &users.User{ID: u1, Email: "u1@example.com"}))
	rec1 := httptest.NewRecorder()
	r.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusOK {
		t.Errorf("expected status 200 for member, got %d", rec1.Code)
	}

	// Case 2: Non-member u3 accesses the route -> 403 Forbidden
	req2 := httptest.NewRequest(http.MethodGet, "/pods/"+podID+"/test", nil)
	req2 = req2.WithContext(auth.WithUser(req2.Context(), &users.User{ID: u3, Email: "u3@example.com"}))
	rec2 := httptest.NewRecorder()
	r.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusForbidden {
		t.Errorf("expected status 403 for non-member, got %d", rec2.Code)
	}

	// Case 3: Access non-existent pod -> 404 Not Found
	req3 := httptest.NewRequest(http.MethodGet, "/pods/non-existent-pod/test", nil)
	req3 = req3.WithContext(auth.WithUser(req3.Context(), &users.User{ID: u1, Email: "u1@example.com"}))
	rec3 := httptest.NewRecorder()
	r.ServeHTTP(rec3, req3)
	if rec3.Code != http.StatusNotFound {
		t.Errorf("expected status 404 for unknown pod, got %d", rec3.Code)
	}

	// Case 4: Unauthenticated request -> 401 Unauthorized
	req4 := httptest.NewRequest(http.MethodGet, "/pods/"+podID+"/test", nil)
	rec4 := httptest.NewRecorder()
	r.ServeHTTP(rec4, req4)
	if rec4.Code != http.StatusUnauthorized {
		t.Errorf("expected status 401 for unauthenticated request, got %d", rec4.Code)
	}

	// Case 5: u1 leaves pod, then tries to access again -> 403 Forbidden
	if err := pods.LeaveUser(context.Background(), podID, u1); err != nil {
		t.Fatalf("failed to leave pod: %v", err)
	}
	req5 := httptest.NewRequest(http.MethodGet, "/pods/"+podID+"/test", nil)
	req5 = req5.WithContext(auth.WithUser(req5.Context(), &users.User{ID: u1, Email: "u1@example.com"}))
	rec5 := httptest.NewRecorder()
	r.ServeHTTP(rec5, req5)
	if rec5.Code != http.StatusForbidden {
		t.Errorf("expected status 403 for user who left, got %d", rec5.Code)
	}
}

func TestPackageHelpers_LeaveUser_RequireMemberUser(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := pods.NewRepository(database.Write, database.Read)
	pods.SetDefaultRepository(repo)

	u1, g1 := createTestUserAndGoal(t, database, "User 1", "u1@example.com")
	u2, g2 := createTestUserAndGoal(t, database, "User 2", "u2@example.com")
	podID := createTestPod(t, database, u1, g1, u2, g2)

	// Check RequireMemberUser succeeds for u1
	member, err := pods.RequireMemberUser(context.Background(), podID, u1)
	if err != nil {
		t.Fatalf("RequireMemberUser failed for active member: %v", err)
	}
	if member.UserID != u1 {
		t.Errorf("expected member userID %s, got %s", u1, member.UserID)
	}

	// LeaveUser via package function
	if err := pods.LeaveUser(context.Background(), podID, u1); err != nil {
		t.Fatalf("package LeaveUser failed: %v", err)
	}

	// RequireMemberUser should now fail with ErrNotMember
	_, err = pods.RequireMemberUser(context.Background(), podID, u1)
	if err != pods.ErrNotMember {
		t.Fatalf("expected ErrNotMember after leaving, got %v", err)
	}
}
