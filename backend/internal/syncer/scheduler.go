package syncer

import (
	"context"
	"database/sql"
	"log"
	"sync"
	"time"

	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/mailclient"
	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/rules"
)

// Scheduler 负责后台定时扫描到期邮箱并支持按需立即触发同步。
type Scheduler struct {
	db      *sql.DB
	cfg     *config.Config
	hub     *Hub
	mu      sync.Mutex
	running map[int64]bool
}

// NewScheduler 创建后台邮件同步调度器。
func NewScheduler(conn *sql.DB, cfg *config.Config, hub *Hub) *Scheduler {
	return &Scheduler{
		db:      conn,
		cfg:     cfg,
		hub:     hub,
		running: make(map[int64]bool),
	}
}

// Start 启动定时同步循环，直到 ctx 被取消。
func (s *Scheduler) Start(ctx context.Context) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.scanDueAccounts()
		}
	}
}

func (s *Scheduler) scanDueAccounts() {
	rows, err := s.db.Query(`
		SELECT id, user_id, label, email_address, provider_id, imap_host, imap_port, imap_tls,
		       smtp_host, smtp_port, smtp_tls, username, encrypted_password, color, is_default,
		       sync_enabled, sync_interval_sec, last_sync_at, last_sync_status, last_sync_error, created_at
		FROM mail_accounts
		WHERE sync_enabled = 1`)
	if err != nil {
		return
	}

	var due []models.MailAccount
	now := time.Now()
	for rows.Next() {
		acct, err := scanAccount(rows)
		if err != nil {
			continue
		}
		if acct.LastSyncAt == nil || now.Sub(*acct.LastSyncAt) >= time.Duration(acct.SyncIntervalSec)*time.Second {
			due = append(due, acct)
		}
	}
	_ = rows.Close()

	for _, acct := range due {
		a := acct
		go s.SyncAccountNow(a)
	}
}

// TriggerSyncByID 异步触发指定邮箱账号的立即同步。
func (s *Scheduler) TriggerSyncByID(accountID int64) bool {
	row := s.db.QueryRow(`
		SELECT id, user_id, label, email_address, provider_id, imap_host, imap_port, imap_tls,
		       smtp_host, smtp_port, smtp_tls, username, encrypted_password, color, is_default,
		       sync_enabled, sync_interval_sec, last_sync_at, last_sync_status, last_sync_error, created_at
		FROM mail_accounts WHERE id = ?`, accountID)
	acct, err := scanAccount(row)
	if err != nil {
		return false
	}
	go s.SyncAccountNow(acct)
	return true
}

// SyncAccountNow 执行单个账号同步（防重入），并自动运行规则引擎和推送 SSE 事件。
func (s *Scheduler) SyncAccountNow(acct models.MailAccount) {
	s.mu.Lock()
	if s.running[acct.ID] {
		s.mu.Unlock()
		return
	}
	s.running[acct.ID] = true
	s.mu.Unlock()

	defer func() {
		s.mu.Lock()
		delete(s.running, acct.ID)
		s.mu.Unlock()
	}()

	_, _ = s.db.Exec(`UPDATE mail_accounts SET last_sync_status = 'syncing', last_sync_error = '' WHERE id = ?`, acct.ID)
	s.hub.Publish(acct.UserID, Event{
		Type:      "sync_started",
		AccountID: acct.ID,
		Label:     acct.Label,
	})

	password, err := crypto.Decrypt(acct.EncryptedPassword, s.cfg.EncKey)
	if err != nil {
		s.failSync(acct, "解密邮箱凭证失败: "+err.Error())
		return
	}

	newMsgs, err := mailclient.SyncAccount(s.db, acct, password, s.cfg.DataDir)
	if err != nil {
		s.failSync(acct, err.Error())
		return
	}

	// 对新同步入库的邮件运行自动分类规则
	for _, m := range newMsgs {
		if err := rules.ApplyToMessage(s.db, acct.UserID, m); err != nil {
			log.Printf("rules apply error msg=%d: %v", m.ID, err)
		}
	}

	now := time.Now()
	_, _ = s.db.Exec(`
		UPDATE mail_accounts
		SET last_sync_at = ?, last_sync_status = 'ok', last_sync_error = ''
		WHERE id = ?`, now, acct.ID)

	if len(newMsgs) > 0 {
		s.hub.Publish(acct.UserID, Event{
			Type:      "new_messages",
			AccountID: acct.ID,
			Label:     acct.Label,
			Count:     len(newMsgs),
			Message:   acct.Label + " 收到新邮件",
		})
	}
	s.hub.Publish(acct.UserID, Event{
		Type:      "sync_completed",
		AccountID: acct.ID,
		Label:     acct.Label,
		Count:     len(newMsgs),
	})
}

func (s *Scheduler) failSync(acct models.MailAccount, msg string) {
	now := time.Now()
	_, _ = s.db.Exec(`
		UPDATE mail_accounts
		SET last_sync_at = ?, last_sync_status = 'error', last_sync_error = ?
		WHERE id = ?`, now, msg, acct.ID)
	s.hub.Publish(acct.UserID, Event{
		Type:      "sync_error",
		AccountID: acct.ID,
		Label:     acct.Label,
		Message:   msg,
	})
}

type accountScanner interface {
	Scan(dest ...interface{}) error
}

func scanAccount(s accountScanner) (models.MailAccount, error) {
	var a models.MailAccount
	var isDef, syncEn int
	var lastSync sql.NullTime
	err := s.Scan(
		&a.ID, &a.UserID, &a.Label, &a.EmailAddress, &a.ProviderID,
		&a.IMAPHost, &a.IMAPPort, &a.IMAPTLS,
		&a.SMTPHost, &a.SMTPPort, &a.SMTPTLS,
		&a.Username, &a.EncryptedPassword, &a.Color, &isDef,
		&syncEn, &a.SyncIntervalSec, &lastSync, &a.LastSyncStatus, &a.LastSyncError, &a.CreatedAt,
	)
	if err != nil {
		return a, err
	}
	a.IsDefault = isDef == 1
	a.SyncEnabled = syncEn == 1
	if lastSync.Valid {
		t := lastSync.Time
		a.LastSyncAt = &t
	}
	return a, nil
}
