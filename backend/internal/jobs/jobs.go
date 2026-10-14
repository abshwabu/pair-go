package jobs

import (
	"log/slog"

	"github.com/robfig/cron/v3"
)

// Scheduler manages scheduled cron jobs for streaks, check-in reminders, etc.
type Scheduler struct {
	cron *cron.Cron
}

// NewScheduler creates and configures a cron job scheduler.
func NewScheduler() *Scheduler {
	c := cron.New(cron.WithSeconds())
	return &Scheduler{
		cron: c,
	}
}

// Start begins the cron scheduler in the background.
func (s *Scheduler) Start() {
	s.cron.Start()
	slog.Info("Cron job scheduler started")
}

// Stop stops the cron scheduler.
func (s *Scheduler) Stop() {
	ctx := s.cron.Stop()
	<-ctx.Done()
	slog.Info("Cron job scheduler stopped")
}
