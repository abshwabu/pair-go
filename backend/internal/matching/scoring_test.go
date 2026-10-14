package matching_test

import (
	"testing"
	"time"

	"github.com/abshwabu/pair/backend/internal/goals"
	"github.com/abshwabu/pair/backend/internal/matching"
)

func TestScore_IdenticalAttributes(t *testing.T) {
	now := time.Now().UTC()
	reqA := matching.Request{
		ID:                     "req-1",
		UserID:                 "user-1",
		GoalID:                 "goal-1",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
	}

	reqB := matching.Request{
		ID:                     "req-2",
		UserID:                 "user-2",
		GoalID:                 "goal-2",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
		CreatedAt:              now,
	}

	score, ok := matching.Score(reqA, reqB)
	if !ok {
		t.Fatalf("expected compatible match, got ok=false")
	}

	// 50 (base) + 40 (same pace) + 12 (0h tz diff) = 102
	expectedScore := 102
	if score != expectedScore {
		t.Errorf("expected score %d, got %d", expectedScore, score)
	}
}

func TestScore_DifferentCategory(t *testing.T) {
	reqA := matching.Request{
		UserID:                 "user-1",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 5,
		Language:               "en",
	}

	reqB := matching.Request{
		UserID:                 "user-2",
		GoalCategory:           goals.GoalCategoryFitness,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 5,
		Language:               "en",
	}

	score, ok := matching.Score(reqA, reqB)
	if ok || score != 0 {
		t.Errorf("expected incompatible for different categories, got score=%d, ok=%v", score, ok)
	}
}

func TestScore_DifferentLanguage(t *testing.T) {
	reqA := matching.Request{
		UserID:                 "user-1",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 5,
		Language:               "en",
	}

	reqB := matching.Request{
		UserID:                 "user-2",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 5,
		Language:               "es",
	}

	score, ok := matching.Score(reqA, reqB)
	if ok || score != 0 {
		t.Errorf("expected incompatible for different languages, got score=%d, ok=%v", score, ok)
	}
}

func TestScore_TimezoneTolerance(t *testing.T) {
	// America/New_York (UTC-4/5) vs Europe/London (UTC+0/1): difference ~5 hours
	reqNY := matching.Request{
		UserID:       "user-ny",
		GoalCategory: goals.GoalCategoryHabit,
		Pace:         goals.GoalPaceRelaxed,
		Timezone:     "America/New_York",
		Language:     "en",
	}

	reqLondon := matching.Request{
		UserID:       "user-lon",
		GoalCategory: goals.GoalCategoryHabit,
		Pace:         goals.GoalPaceRelaxed,
		Timezone:     "Europe/London",
		Language:     "en",
	}

	// 1. Both allow 6 hours tolerance -> compatible
	reqNY.TimezoneToleranceHours = 6
	reqLondon.TimezoneToleranceHours = 6
	score, ok := matching.Score(reqNY, reqLondon)
	if !ok {
		t.Errorf("expected compatible within 6h tolerance, got ok=false")
	}
	if score < matching.MinScoreThreshold {
		t.Errorf("expected score >= %d, got %d", matching.MinScoreThreshold, score)
	}

	// 2. One user allows only 2 hours tolerance -> incompatible
	reqNY.TimezoneToleranceHours = 2
	reqLondon.TimezoneToleranceHours = 6
	_, ok = matching.Score(reqNY, reqLondon)
	if ok {
		t.Errorf("expected incompatible when one tolerance is exceeded, got ok=true")
	}

	// 3. Invalid timezone name
	reqInvalid := reqNY
	reqInvalid.Timezone = "Invalid/Timezone_Name"
	_, ok = matching.Score(reqInvalid, reqLondon)
	if ok {
		t.Errorf("expected incompatible for invalid timezone, got ok=true")
	}
}

func TestScore_PaceSoftScoring(t *testing.T) {
	baseReq := matching.Request{
		UserID:                 "user-1",
		GoalCategory:           goals.GoalCategoryWatch,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}

	// Same pace (steady vs steady)
	samePaceReq := matching.Request{
		UserID:                 "user-same",
		GoalCategory:           goals.GoalCategoryWatch,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}
	scoreSame, okSame := matching.Score(baseReq, samePaceReq)
	if !okSame {
		t.Fatalf("expected same pace to be compatible")
	}

	// Adjacent pace (steady vs relaxed)
	adjacentPaceReq := matching.Request{
		UserID:                 "user-adj",
		GoalCategory:           goals.GoalCategoryWatch,
		Pace:                   goals.GoalPaceRelaxed,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}
	scoreAdj, okAdj := matching.Score(baseReq, adjacentPaceReq)
	if !okAdj {
		t.Fatalf("expected adjacent pace to be compatible")
	}

	// Distant pace (steady vs intense is adjacent; let's test relaxed vs intense)
	relaxedReq := matching.Request{
		UserID:                 "user-relaxed",
		GoalCategory:           goals.GoalCategoryWatch,
		Pace:                   goals.GoalPaceRelaxed,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}
	intenseReq := matching.Request{
		UserID:                 "user-intense",
		GoalCategory:           goals.GoalCategoryWatch,
		Pace:                   goals.GoalPaceIntense,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}
	scoreDistant, okDistant := matching.Score(relaxedReq, intenseReq)
	if !okDistant {
		t.Fatalf("expected distant pace to meet threshold")
	}

	// Same pace should score higher than adjacent pace
	if scoreSame <= scoreAdj {
		t.Errorf("expected scoreSame (%d) > scoreAdj (%d)", scoreSame, scoreAdj)
	}

	// Adjacent pace should score higher than distant pace
	scoreAdjRelaxed, _ := matching.Score(relaxedReq, samePaceReq) // relaxed vs steady (adj)
	if scoreAdjRelaxed <= scoreDistant {
		t.Errorf("expected scoreAdjRelaxed (%d) > scoreDistant (%d)", scoreAdjRelaxed, scoreDistant)
	}
}

func TestScore_SelfMatchPrevention(t *testing.T) {
	req := matching.Request{
		UserID:                 "user-1",
		GoalCategory:           goals.GoalCategoryRead,
		Pace:                   goals.GoalPaceSteady,
		Timezone:               "UTC",
		TimezoneToleranceHours: 3,
		Language:               "en",
	}

	score, ok := matching.Score(req, req)
	if ok || score != 0 {
		t.Errorf("expected self-matching to be rejected, got score=%d, ok=%v", score, ok)
	}
}
