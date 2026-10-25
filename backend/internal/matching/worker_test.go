package matching_test

import (
	"context"
	"errors"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/matching"
	"github.com/abshwabu/pair/backend/internal/safety"
)

type sentNotif struct {
	userID string
	t      string
	p      map[string]any
}

type fakeNotifier struct {
	mu     sync.Mutex
	notifs []sentNotif
}

func (f *fakeNotifier) Send(ctx context.Context, userID, notificationType string, payload map[string]any) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.notifs = append(f.notifs, sentNotif{userID: userID, t: notificationType, p: payload})
	return nil
}

func (f *fakeNotifier) GetAll() []sentNotif {
	f.mu.Lock()
	defer f.mu.Unlock()
	copied := make([]sentNotif, len(f.notifs))
	copy(copied, f.notifs)
	return copied
}

func (f *fakeNotifier) Clear() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.notifs = nil
}

type fakeClock struct {
	mu  sync.Mutex
	now time.Time
}

func (f *fakeClock) Now() time.Time {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.now
}

func (f *fakeClock) Advance(d time.Duration) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.now = f.now.Add(d)
}

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "matching_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUserAndGoal(t *testing.T, database *db.DB, email, timezone, language, category, pace string) (string, string) {
	t.Helper()
	now := time.Now().UTC().Format(time.RFC3339)
	userID := uuid.NewString()

	_, err := database.Write.Exec(`
		INSERT INTO users (id, name, email, password_hash, timezone, language, is_admin, created_at, updated_at)
		VALUES (?, 'Test User', ?, 'hash', ?, ?, 0, ?, ?);
	`, userID, email, timezone, language, now, now)
	if err != nil {
		t.Fatalf("failed to insert user: %v", err)
	}

	goalID := uuid.NewString()
	_, err = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, ?, 'Test Goal', 'Description', ?, ?, ?);
	`, goalID, userID, category, pace, now, now)
	if err != nil {
		t.Fatalf("failed to insert goal: %v", err)
	}

	return userID, goalID
}

func TestWorker_ProposeCreatesProposalAndNoPod(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	notifier := &fakeNotifier{}
	worker := matching.NewWorker(repo, matching.WithClock(clk), matching.WithNotifier(notifier))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	if err := repo.Create(ctx, req1); err != nil {
		t.Fatalf("create req1: %v", err)
	}
	if err := repo.Create(ctx, req2); err != nil {
		t.Fatalf("create req2: %v", err)
	}

	if err := worker.ProcessRequest(ctx, req1.ID); err != nil {
		t.Fatalf("process request: %v", err)
	}

	// 1. Verify NO pod was created
	var podCount int
	if err := database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount); err != nil {
		t.Fatalf("count pods: %v", err)
	}
	if podCount != 0 {
		t.Fatalf("expected 0 pods, got %d", podCount)
	}

	// 2. Verify match_proposals row exists with status pending and expires_at = now + 12h
	var propID, propStatus, userAResp, userBResp, expiresAtStr string
	err := database.Read.QueryRow(`
		SELECT id, status, user_a_response, user_b_response, expires_at
		FROM match_proposals
		WHERE user_a_id IN (?, ?) AND user_b_id IN (?, ?);
	`, user1ID, user2ID, user1ID, user2ID).Scan(&propID, &propStatus, &userAResp, &userBResp, &expiresAtStr)
	if err != nil {
		t.Fatalf("fetch proposal: %v", err)
	}
	if propStatus != "pending" || userAResp != "pending" || userBResp != "pending" {
		t.Fatalf("expected pending proposal, got status=%s aResp=%s bResp=%s", propStatus, userAResp, userBResp)
	}

	expTime, err := time.Parse(time.RFC3339, expiresAtStr)
	if err != nil {
		t.Fatalf("parse expires_at: %v", err)
	}
	if !expTime.Equal(now.Add(12 * time.Hour)) {
		t.Fatalf("expected expires_at %v, got %v", now.Add(12*time.Hour), expTime)
	}

	// 3. Verify both requests are proposed with proposal_id
	pReq1, err := repo.GetByID(ctx, req1.ID)
	if err != nil || pReq1.Status != matching.PodRequestStatusProposed || pReq1.ProposalID == nil || *pReq1.ProposalID != propID {
		t.Fatalf("expected req1 to be proposed with proposal %s, got %+v", propID, pReq1)
	}
	pReq2, err := repo.GetByID(ctx, req2.ID)
	if err != nil || pReq2.Status != matching.PodRequestStatusProposed || pReq2.ProposalID == nil || *pReq2.ProposalID != propID {
		t.Fatalf("expected req2 to be proposed with proposal %s, got %+v", propID, pReq2)
	}

	// 4. Verify match_proposed notification sent to both users
	notifs := notifier.GetAll()
	if len(notifs) != 2 {
		t.Fatalf("expected 2 notifications, got %d", len(notifs))
	}
	for _, n := range notifs {
		if n.t != "match_proposed" {
			t.Errorf("expected notification type match_proposed, got %s", n.t)
		}
		if n.p["proposal_id"] != propID {
			t.Errorf("expected proposal_id %s, got %v", propID, n.p["proposal_id"])
		}
	}
}

func TestWorker_AcceptFlowCreatesPodOnSecondAccept(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// First user accepts
	res1, err := repo.AcceptProposal(ctx, propID, user1ID)
	if err != nil {
		t.Fatalf("first accept failed: %v", err)
	}
	if res1.BothAccepted {
		t.Fatalf("expected BothAccepted=false after first accept")
	}

	// Verify still no pod
	var podCount int
	_ = database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount)
	if podCount != 0 {
		t.Fatalf("expected 0 pods after single accept, got %d", podCount)
	}

	// Proposal status should still be pending
	prop, err := repo.GetProposalByID(ctx, propID)
	if err != nil {
		t.Fatalf("get proposal: %v", err)
	}
	if prop.Status != matching.ProposalStatusPending {
		t.Fatalf("expected proposal to still be pending, got %s", prop.Status)
	}

	// Second user accepts
	res2, err := repo.AcceptProposal(ctx, propID, user2ID)
	if err != nil {
		t.Fatalf("second accept failed: %v", err)
	}
	if !res2.BothAccepted {
		t.Fatalf("expected BothAccepted=true after second accept")
	}
	if res2.PodID == "" {
		t.Fatalf("expected valid pod ID in result")
	}

	// Verify pod created
	_ = database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount)
	if podCount != 1 {
		t.Fatalf("expected exactly 1 pod after second accept, got %d", podCount)
	}

	// Verify both pod_members created
	var memberCount int
	_ = database.Read.QueryRow(`SELECT COUNT(*) FROM pod_members WHERE pod_id = ?`, res2.PodID).Scan(&memberCount)
	if memberCount != 2 {
		t.Fatalf("expected 2 members, got %d", memberCount)
	}

	// Verify streaks row
	var streakCount, currentStreak, bestStreak int
	_ = database.Read.QueryRow(`SELECT COUNT(*), current_streak, best_streak FROM streaks WHERE pod_id = ?`, res2.PodID).
		Scan(&streakCount, &currentStreak, &bestStreak)
	if streakCount != 1 || currentStreak != 0 || bestStreak != 0 {
		t.Fatalf("expected 1 zeroed streak row, got count=%d cur=%d best=%d", streakCount, currentStreak, bestStreak)
	}

	// Verify both requests are matched
	pReq1After, _ := repo.GetByID(ctx, req1.ID)
	pReq2After, _ := repo.GetByID(ctx, req2.ID)
	if pReq1After.Status != matching.PodRequestStatusMatched || pReq2After.Status != matching.PodRequestStatusMatched {
		t.Fatalf("expected both requests matched, got req1=%s req2=%s", pReq1After.Status, pReq2After.Status)
	}
}

func TestWorker_ConcurrentAcceptsProduceExactlyOnePod(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// Two goroutines accepting concurrently
	var wg sync.WaitGroup
	wg.Add(2)

	var err1, err2 error
	go func() {
		defer wg.Done()
		_, err1 = repo.AcceptProposal(ctx, propID, user1ID)
	}()
	go func() {
		defer wg.Done()
		_, err2 = repo.AcceptProposal(ctx, propID, user2ID)
	}()

	wg.Wait()

	if err1 != nil {
		t.Fatalf("goroutine 1 error: %v", err1)
	}
	if err2 != nil {
		t.Fatalf("goroutine 2 error: %v", err2)
	}

	var podCount int
	_ = database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount)
	if podCount != 1 {
		t.Fatalf("expected exactly 1 pod from concurrent accepts, got %d", podCount)
	}
}

func TestWorker_RejectReopensBothRequestsAndExcludesPair(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")
	user3ID, goal3ID := createTestUserAndGoal(t, database, "user3@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req3 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user3ID,
		GoalID:                 goal3ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = repo.Create(ctx, req3)

	// Pair user1 and user2
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// User1 rejects the proposal
	res, err := repo.RejectProposal(ctx, propID, user1ID)
	if err != nil {
		t.Fatalf("reject proposal failed: %v", err)
	}
	if res.PartnerID != user2ID {
		t.Errorf("expected partner user2, got %s", res.PartnerID)
	}

	// 1. Verify NO pod was created
	var podCount int
	_ = database.Read.QueryRow(`SELECT COUNT(*) FROM pods`).Scan(&podCount)
	if podCount != 0 {
		t.Fatalf("expected 0 pods, got %d", podCount)
	}

	// 2. Verify both requests returned to open with proposal_id NULL
	pReq1After, _ := repo.GetByID(ctx, req1.ID)
	pReq2After, _ := repo.GetByID(ctx, req2.ID)
	if pReq1After.Status != matching.PodRequestStatusOpen || pReq1After.ProposalID != nil {
		t.Fatalf("expected req1 open with nil proposal, got %+v", pReq1After)
	}
	if pReq2After.Status != matching.PodRequestStatusOpen || pReq2After.ProposalID != nil {
		t.Fatalf("expected req2 open with nil proposal, got %+v", pReq2After)
	}

	// 3. Verify user1 and user2 are never proposed to each other again,
	// but user1 can match with user3!
	if err := worker.ProcessRequest(ctx, req1.ID); err != nil {
		t.Fatalf("process request user1: %v", err)
	}

	pReq1New, _ := repo.GetByID(ctx, req1.ID)
	if pReq1New.Status != matching.PodRequestStatusProposed {
		t.Fatalf("expected req1 to be proposed with someone else, got %s", pReq1New.Status)
	}
	newProp, _ := repo.GetProposalByID(ctx, *pReq1New.ProposalID)
	// Must be matched with user3, NOT user2!
	otherUser := newProp.UserBID
	if newProp.UserAID != user1ID {
		otherUser = newProp.UserAID
	}
	if otherUser != user3ID {
		t.Fatalf("expected user1 to match with user3, got %s (user2 should have been blacklisted)", otherUser)
	}
}

func TestWorker_ClosedProposalReturns409AndNonParticipant403(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")
	outsiderID, _ := createTestUserAndGoal(t, database, "outsider@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// Non-participant gets ErrForbidden
	_, err := repo.AcceptProposal(ctx, propID, outsiderID)
	if !errors.Is(err, matching.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for outsider accept, got %v", err)
	}
	_, err = repo.RejectProposal(ctx, propID, outsiderID)
	if !errors.Is(err, matching.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for outsider reject, got %v", err)
	}

	// Reject proposal
	_, _ = repo.RejectProposal(ctx, propID, user1ID)

	// After proposal closed, accept and reject return ErrProposalClosed (409 proposal_closed)
	_, err = repo.AcceptProposal(ctx, propID, user2ID)
	if !errors.Is(err, matching.ErrProposalClosed) {
		t.Fatalf("expected ErrProposalClosed on closed proposal, got %v", err)
	}
	_, err = repo.RejectProposal(ctx, propID, user2ID)
	if !errors.Is(err, matching.ErrProposalClosed) {
		t.Fatalf("expected ErrProposalClosed on closed proposal, got %v", err)
	}
}

func TestWorker_CancelDuringProposedReopensPartnerAndDoesNotBlacklist(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	// User1 cancels their request while proposed
	res, err := repo.CancelRequest(ctx, req1.ID, user1ID)
	if err != nil {
		t.Fatalf("cancel request: %v", err)
	}
	if !res.WasProposed || res.PartnerID != user2ID || res.PartnerReqID != req2.ID {
		t.Fatalf("unexpected cancel result: %+v", res)
	}

	// Verify req1 is cancelled and req2 is reopened to open
	pReq1, _ := repo.GetByID(ctx, req1.ID)
	pReq2, _ := repo.GetByID(ctx, req2.ID)
	if pReq1.Status != matching.PodRequestStatusCancelled {
		t.Fatalf("expected req1 cancelled, got %s", pReq1.Status)
	}
	if pReq2.Status != matching.PodRequestStatusOpen || pReq2.ProposalID != nil {
		t.Fatalf("expected req2 open with nil proposal, got %+v", pReq2)
	}

	// Verify the pair is NOT blacklisted (cancelled proposal does not exclude)
	// If user1 creates a new request, they can be matched again!
	req1New := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              clk.Now(),
		UpdatedAt:              clk.Now(),
	}
	_ = repo.Create(ctx, req1New)
	if err := worker.ProcessRequest(ctx, req1New.ID); err != nil {
		t.Fatalf("process new request: %v", err)
	}

	pReq1New, _ := repo.GetByID(ctx, req1New.ID)
	if pReq1New.Status != matching.PodRequestStatusProposed {
		t.Fatalf("expected req1New to be proposed again with user2, got %s", pReq1New.Status)
	}
}

func TestWorker_ProposalExpirySweep(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	notifier := &fakeNotifier{}
	worker := matching.NewWorker(repo, matching.WithClock(clk), matching.WithNotifier(notifier))

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// User1 accepts
	_, err := repo.AcceptProposal(ctx, propID, user1ID)
	if err != nil {
		t.Fatalf("user1 accept: %v", err)
	}
	// User2 stays silent (never answers)

	// Advance clock past 12-hour TTL
	clk.Advance(13 * time.Hour)

	// Run proposal expiry sweep
	notifier.Clear()
	if err := worker.SweepExpiredProposals(ctx); err != nil {
		t.Fatalf("sweep expired proposals: %v", err)
	}

	// 1. Verify proposal status is expired
	prop, _ := repo.GetProposalByID(ctx, propID)
	if prop.Status != matching.ProposalStatusExpired {
		t.Fatalf("expected proposal expired, got %s", prop.Status)
	}

	// 2. User1 (accepted side) returns to open
	pReq1After, _ := repo.GetByID(ctx, req1.ID)
	if pReq1After.Status != matching.PodRequestStatusOpen || pReq1After.ProposalID != nil {
		t.Fatalf("expected user1 request open with nil proposal, got %+v", pReq1After)
	}

	// 3. User2 (silent side) is cancelled
	pReq2After, _ := repo.GetByID(ctx, req2.ID)
	if pReq2After.Status != matching.PodRequestStatusCancelled {
		t.Fatalf("expected user2 request cancelled, got %s", pReq2After.Status)
	}

	// 4. User1 gets notification match_declined
	notifs := notifier.GetAll()
	if len(notifs) != 1 {
		t.Fatalf("expected 1 notification for user1, got %d", len(notifs))
	}
	if notifs[0].userID != user1ID || notifs[0].t != "match_declined" {
		t.Fatalf("expected match_declined to user1, got %+v", notifs[0])
	}
}

func TestWorker_BlockCancelsPendingProposalAndReopensRequests(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	clk := &fakeClock{now: time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)}
	repo := matching.NewRepository(database.Write, database.Read, clk)
	worker := matching.NewWorker(repo, matching.WithClock(clk))
	safetyRepo := safety.NewRepository(database.Write, database.Read)

	user1ID, goal1ID := createTestUserAndGoal(t, database, "user1@pair.test", "UTC", "en", "read", "steady")
	user2ID, goal2ID := createTestUserAndGoal(t, database, "user2@pair.test", "UTC", "en", "read", "steady")

	now := clk.Now()
	req1 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user1ID,
		GoalID:                 goal1ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}
	req2 := &matching.PodRequest{
		ID:                     uuid.NewString(),
		UserID:                 user2ID,
		GoalID:                 goal2ID,
		Status:                 matching.PodRequestStatusOpen,
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	ctx := context.Background()
	_ = repo.Create(ctx, req1)
	_ = repo.Create(ctx, req2)
	_ = worker.ProcessRequest(ctx, req1.ID)

	pReq1, _ := repo.GetByID(ctx, req1.ID)
	propID := *pReq1.ProposalID

	// User1 blocks User2
	_, _, err := safetyRepo.CreateBlock(ctx, user1ID, user2ID, nil, nil)
	if err != nil {
		t.Fatalf("create block failed: %v", err)
	}

	// 1. Verify proposal is cancelled
	prop, err := repo.GetProposalByID(ctx, propID)
	if err != nil {
		t.Fatalf("get proposal: %v", err)
	}
	if prop.Status != matching.ProposalStatusCancelled {
		t.Fatalf("expected proposal cancelled after block, got %s", prop.Status)
	}

	// 2. Verify both requests are reopened to open
	pReq1After, _ := repo.GetByID(ctx, req1.ID)
	pReq2After, _ := repo.GetByID(ctx, req2.ID)
	if pReq1After.Status != matching.PodRequestStatusOpen || pReq1After.ProposalID != nil {
		t.Fatalf("expected req1 open with nil proposal, got %+v", pReq1After)
	}
	if pReq2After.Status != matching.PodRequestStatusOpen || pReq2After.ProposalID != nil {
		t.Fatalf("expected req2 open with nil proposal, got %+v", pReq2After)
	}

	// 3. Verify they are never paired again because of the block
	_ = worker.ProcessRequest(ctx, req1.ID)
	pReq1Final, _ := repo.GetByID(ctx, req1.ID)
	if pReq1Final.Status != matching.PodRequestStatusOpen {
		t.Fatalf("expected req1 to remain open and never match blocked user, got %s", pReq1Final.Status)
	}
}
