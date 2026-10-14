package goals_test

import (
	"errors"
	"testing"
	"time"

	"github.com/abshwabu/pair/backend/internal/goals"
)

func TestValidation_Category(t *testing.T) {
	validCategories := []goals.GoalCategory{
		goals.GoalCategoryRead,
		goals.GoalCategoryWatch,
		goals.GoalCategoryFitness,
		goals.GoalCategoryHabit,
		goals.GoalCategoryCustom,
	}

	for _, c := range validCategories {
		if !goals.IsValidCategory(c) {
			t.Errorf("expected category %q to be valid", c)
		}
	}

	invalidCategories := []goals.GoalCategory{
		"run", "swim", "sleep", "", "other",
	}

	for _, c := range invalidCategories {
		if goals.IsValidCategory(c) {
			t.Errorf("expected category %q to be invalid", c)
		}
	}
}

func TestValidation_Pace(t *testing.T) {
	validPaces := []goals.GoalPace{
		goals.GoalPaceRelaxed,
		goals.GoalPaceSteady,
		goals.GoalPaceIntense,
	}

	for _, p := range validPaces {
		if !goals.IsValidPace(p) {
			t.Errorf("expected pace %q to be valid", p)
		}
	}

	invalidPaces := []goals.GoalPace{
		"fast", "slow", "moderate", "", "sprint",
	}

	for _, p := range invalidPaces {
		if goals.IsValidPace(p) {
			t.Errorf("expected pace %q to be invalid", p)
		}
	}
}

func TestAuthorizeOwner(t *testing.T) {
	g := &goals.Goal{
		ID:        "goal-123",
		UserID:    "user-456",
		Category:  goals.GoalCategoryRead,
		Title:     "Read 10 Books",
		Pace:      goals.GoalPaceSteady,
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}

	// Owner passes
	if err := goals.AuthorizeOwner(g, "user-456"); err != nil {
		t.Errorf("expected nil error for goal owner, got: %v", err)
	}

	// Non-owner fails with ErrForbidden
	err := goals.AuthorizeOwner(g, "user-999")
	if !errors.Is(err, goals.ErrForbidden) {
		t.Errorf("expected ErrForbidden for non-owner, got: %v", err)
	}

	// Nil goal fails with ErrForbidden
	if err := goals.AuthorizeOwner(nil, "user-456"); !errors.Is(err, goals.ErrForbidden) {
		t.Errorf("expected ErrForbidden for nil goal, got: %v", err)
	}
}

func TestIsOwner(t *testing.T) {
	g := &goals.Goal{
		ID:     "goal-123",
		UserID: "user-456",
	}

	if !goals.IsOwner(g, "user-456") {
		t.Errorf("expected IsOwner to return true for matching user_id")
	}

	if goals.IsOwner(g, "user-789") {
		t.Errorf("expected IsOwner to return false for mismatching user_id")
	}

	if goals.IsOwner(nil, "user-456") {
		t.Errorf("expected IsOwner to return false for nil goal")
	}
}
