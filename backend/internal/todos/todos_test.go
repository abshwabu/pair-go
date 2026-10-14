package todos_test

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/abshwabu/pair/backend/internal/db"
	"github.com/abshwabu/pair/backend/internal/todos"
)

func setupTestDB(t *testing.T) *db.DB {
	t.Helper()
	tempDir := t.TempDir()
	dbPath := filepath.Join(tempDir, "todos_test.db")

	database, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("failed to open test database: %v", err)
	}
	return database
}

func createTestUser(t *testing.T, database *db.DB, name, email string) string {
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
	return userID
}

func createTestPod(t *testing.T, database *db.DB, user1ID, user2ID string) string {
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

	goal1ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 1', 'Desc 1', 'steady', ?, ?);
	`, goal1ID, user1ID, now, now)

	goal2ID := uuid.NewString()
	_, _ = database.Write.Exec(`
		INSERT INTO goals (id, user_id, category, title, target_description, pace, created_at, updated_at)
		VALUES (?, ?, 'read', 'Goal 2', 'Desc 2', 'steady', ?, ?);
	`, goal2ID, user2ID, now, now)

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user1ID, goal1ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 1: %v", err)
	}

	_, err = database.Write.Exec(`
		INSERT INTO pod_members (id, pod_id, user_id, goal_id, joined_at)
		VALUES (?, ?, ?, ?, ?);
	`, uuid.NewString(), podID, user2ID, goal2ID, now)
	if err != nil {
		t.Fatalf("failed to insert member 2: %v", err)
	}

	return podID
}

func TestRepository_Create_Success(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()
	dueDate := "2026-10-20"
	todo := &todos.Todo{
		ID:         uuid.NewString(),
		PodID:      podID,
		CreatedBy:  u1,
		AssignedTo: &u2,
		Title:      "Read Chapter 1",
		DueDate:    &dueDate,
		IsDone:     false,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	if err := repo.Create(context.Background(), todo); err != nil {
		t.Fatalf("failed to create todo: %v", err)
	}

	// Fetch back
	saved, err := repo.GetByID(context.Background(), podID, todo.ID)
	if err != nil {
		t.Fatalf("failed to get todo: %v", err)
	}
	if saved.Title != "Read Chapter 1" {
		t.Errorf("expected title 'Read Chapter 1', got %s", saved.Title)
	}
	if saved.AssignedTo == nil || *saved.AssignedTo != u2 {
		t.Errorf("expected assigned_to %s, got %v", u2, saved.AssignedTo)
	}
	if saved.DueDate == nil || *saved.DueDate != "2026-10-20" {
		t.Errorf("expected due date '2026-10-20', got %v", saved.DueDate)
	}
	if saved.IsDone {
		t.Errorf("expected is_done to be false")
	}
}

func TestRepository_Create_NonMemberRejected(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	nonMember := createTestUser(t, database, "Charlie", "charlie@example.com")
	podID := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()
	todo := &todos.Todo{
		ID:         uuid.NewString(),
		PodID:      podID,
		CreatedBy:  u1,
		AssignedTo: &nonMember,
		Title:      "Read Chapter 1",
		IsDone:     false,
		CreatedAt:  now,
		UpdatedAt:  now,
	}

	err := repo.Create(context.Background(), todo)
	if err != todos.ErrInvalidMember {
		t.Fatalf("expected ErrInvalidMember, got %v", err)
	}
}

func TestRepository_GetByID_CrossPodIsolation(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	pod1 := createTestPod(t, database, u1, u2)
	pod2 := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()
	todo := &todos.Todo{
		ID:        uuid.NewString(),
		PodID:     pod1,
		CreatedBy: u1,
		Title:     "Pod 1 Todo",
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := repo.Create(context.Background(), todo); err != nil {
		t.Fatalf("failed to create todo: %v", err)
	}

	// Access with pod1 -> OK
	_, err := repo.GetByID(context.Background(), pod1, todo.ID)
	if err != nil {
		t.Fatalf("expected to find todo in pod1: %v", err)
	}

	// Access with pod2 -> ErrTodoNotFound
	_, err = repo.GetByID(context.Background(), pod2, todo.ID)
	if err != todos.ErrTodoNotFound {
		t.Fatalf("expected ErrTodoNotFound across pods, got %v", err)
	}
}

func TestRepository_List_FiltersAndSorting(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	tNow := time.Now().UTC()
	d1 := "2026-10-15"
	d2 := "2026-10-25"

	// 1. Open, due 2026-10-25, assigned to u1
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: uuid.NewString(), PodID: podID, CreatedBy: u1, AssignedTo: &u1,
		Title: "Task 1", DueDate: &d2, IsDone: false, CreatedAt: tNow, UpdatedAt: tNow,
	})
	// 2. Open, due 2026-10-15, shared (nil)
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: uuid.NewString(), PodID: podID, CreatedBy: u1, AssignedTo: nil,
		Title: "Task 2", DueDate: &d1, IsDone: false, CreatedAt: tNow.Add(1 * time.Second), UpdatedAt: tNow.Add(1 * time.Second),
	})
	// 3. Open, due nil, assigned to u2
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: uuid.NewString(), PodID: podID, CreatedBy: u1, AssignedTo: &u2,
		Title: "Task 3", DueDate: nil, IsDone: false, CreatedAt: tNow.Add(2 * time.Second), UpdatedAt: tNow.Add(2 * time.Second),
	})
	// 4. Done, due 2026-10-10, assigned to u1
	dOld := "2026-10-10"
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: uuid.NewString(), PodID: podID, CreatedBy: u1, AssignedTo: &u1,
		Title: "Task 4", DueDate: &dOld, IsDone: true, CreatedAt: tNow.Add(3 * time.Second), UpdatedAt: tNow.Add(3 * time.Second),
	})

	// Filter by assigned_to = "shared"
	sharedVal := "shared"
	sharedList, err := repo.List(context.Background(), todos.ListFilter{PodID: podID, AssignedTo: &sharedVal})
	if err != nil {
		t.Fatalf("failed to list shared: %v", err)
	}
	if len(sharedList) != 1 || sharedList[0].Title != "Task 2" {
		t.Fatalf("expected 1 shared todo (Task 2), got %d", len(sharedList))
	}

	// Filter by assigned_to = u1
	u1List, err := repo.List(context.Background(), todos.ListFilter{PodID: podID, AssignedTo: &u1})
	if err != nil {
		t.Fatalf("failed to list for u1: %v", err)
	}
	if len(u1List) != 2 {
		t.Fatalf("expected 2 todos for u1, got %d", len(u1List))
	}

	// Filter by is_done = false
	isDoneFalse := false
	openTodos, err := repo.List(context.Background(), todos.ListFilter{PodID: podID, IsDone: &isDoneFalse})
	if err != nil {
		t.Fatalf("failed to list open todos: %v", err)
	}
	if len(openTodos) != 3 {
		t.Fatalf("expected 3 open todos, got %d", len(openTodos))
	}

	// Default sort: open first, then due_date (nulls last), then created_at
	defaultList, err := repo.List(context.Background(), todos.ListFilter{PodID: podID})
	if err != nil {
		t.Fatalf("failed to list default: %v", err)
	}
	if len(defaultList) != 4 {
		t.Fatalf("expected 4 todos, got %d", len(defaultList))
	}
	// Expected open order: Task 2 (due 10-15), Task 1 (due 10-25), Task 3 (due nil), Task 4 (done)
	if defaultList[0].Title != "Task 2" {
		t.Errorf("expected 1st todo to be Task 2, got %s", defaultList[0].Title)
	}
	if defaultList[1].Title != "Task 1" {
		t.Errorf("expected 2nd todo to be Task 1, got %s", defaultList[1].Title)
	}
	if defaultList[2].Title != "Task 3" {
		t.Errorf("expected 3rd todo to be Task 3, got %s", defaultList[2].Title)
	}
	if defaultList[3].Title != "Task 4" {
		t.Errorf("expected 4th todo to be Task 4, got %s", defaultList[3].Title)
	}

	// Sort = due_date (nulls last)
	dueDateSorted, err := repo.List(context.Background(), todos.ListFilter{PodID: podID, Sort: "due_date"})
	if err != nil {
		t.Fatalf("failed to list sort=due_date: %v", err)
	}
	// Expected: Task 4 (10-10), Task 2 (10-15), Task 1 (10-25), Task 3 (nil due date last)
	if dueDateSorted[0].Title != "Task 4" {
		t.Errorf("expected 1st todo to be Task 4, got %s", dueDateSorted[0].Title)
	}
	if dueDateSorted[3].Title != "Task 3" {
		t.Errorf("expected 4th todo (null due date) to be Task 3, got %s", dueDateSorted[3].Title)
	}
}

func TestRepository_Update_CompletedAtToggle(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()
	todo := &todos.Todo{
		ID:        uuid.NewString(),
		PodID:     podID,
		CreatedBy: u1,
		Title:     "Initial Task",
		IsDone:    false,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := repo.Create(context.Background(), todo); err != nil {
		t.Fatalf("failed to create todo: %v", err)
	}

	// 1. Toggle is_done to true -> completed_at must be populated
	trueVal := true
	updated, err := repo.Update(context.Background(), podID, todo.ID, todos.UpdateTodoInput{
		IsDone: &trueVal,
	})
	if err != nil {
		t.Fatalf("failed to update todo to done: %v", err)
	}
	if !updated.IsDone {
		t.Errorf("expected is_done true")
	}
	if updated.CompletedAt == nil {
		t.Errorf("expected completed_at to be non-nil when is_done is toggled true")
	}

	// 2. Toggle is_done to false -> completed_at must be cleared to nil
	falseVal := false
	updated2, err := repo.Update(context.Background(), podID, todo.ID, todos.UpdateTodoInput{
		IsDone: &falseVal,
	})
	if err != nil {
		t.Fatalf("failed to update todo to not done: %v", err)
	}
	if updated2.IsDone {
		t.Errorf("expected is_done false")
	}
	if updated2.CompletedAt != nil {
		t.Errorf("expected completed_at to be nil when is_done is toggled false")
	}

	// 3. Update assigned_to to non-member -> ErrInvalidMember
	nonMember := createTestUser(t, database, "NonMember", "nonmember@example.com")
	_, err = repo.Update(context.Background(), podID, todo.ID, todos.UpdateTodoInput{
		AssignedTo: &nonMember,
	})
	if err != todos.ErrInvalidMember {
		t.Fatalf("expected ErrInvalidMember when updating assignee to non-member, got %v", err)
	}
}

func TestRepository_Delete_Authorization(t *testing.T) {
	database := setupTestDB(t)
	defer database.Close()

	repo := todos.NewRepository(database.Write, database.Read)
	u1 := createTestUser(t, database, "Alice", "alice@example.com")
	u2 := createTestUser(t, database, "Bob", "bob@example.com")
	podID := createTestPod(t, database, u1, u2)

	now := time.Now().UTC()

	// 1. Assigned todo created by u1, assigned to u1
	assignedTodoID := uuid.NewString()
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: assignedTodoID, PodID: podID, CreatedBy: u1, AssignedTo: &u1,
		Title: "U1 Task", CreatedAt: now, UpdatedAt: now,
	})

	// 2. Shared todo created by u1, assigned to nil
	sharedTodoID := uuid.NewString()
	_ = repo.Create(context.Background(), &todos.Todo{
		ID: sharedTodoID, PodID: podID, CreatedBy: u1, AssignedTo: nil,
		Title: "Shared Task", CreatedAt: now, UpdatedAt: now,
	})

	// Bob (u2) attempts to delete u1's assigned todo -> ErrForbidden (403)
	err := repo.Delete(context.Background(), podID, assignedTodoID, u2)
	if err != todos.ErrForbidden {
		t.Fatalf("expected ErrForbidden for non-creator deleting assigned todo, got %v", err)
	}

	// Bob (u2) attempts to delete shared todo -> Allowed!
	err = repo.Delete(context.Background(), podID, sharedTodoID, u2)
	if err != nil {
		t.Fatalf("expected Bob to be able to delete shared todo, got: %v", err)
	}

	// Alice (u1) deletes her own assigned todo -> Allowed!
	err = repo.Delete(context.Background(), podID, assignedTodoID, u1)
	if err != nil {
		t.Fatalf("expected creator Alice to delete assigned todo, got: %v", err)
	}

	// Deleting already deleted todo -> ErrTodoNotFound (404)
	err = repo.Delete(context.Background(), podID, assignedTodoID, u1)
	if err != todos.ErrTodoNotFound {
		t.Fatalf("expected ErrTodoNotFound, got %v", err)
	}
}
