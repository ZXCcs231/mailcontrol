package api

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/mailclient"
	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/providers"
)

type accountReq struct {
	AccountID       int64  `json:"account_id"`
	Label           string `json:"label"`
	EmailAddress    string `json:"email_address" binding:"required"`
	ProviderID      string `json:"provider_id"`
	IMAPHost        string `json:"imap_host"`
	IMAPPort        int    `json:"imap_port"`
	IMAPTLS         string `json:"imap_tls"`
	SMTPHost        string `json:"smtp_host"`
	SMTPPort        int    `json:"smtp_port"`
	SMTPTLS         string `json:"smtp_tls"`
	Username        string `json:"username"`
	Password        string `json:"password"`
	Color           string `json:"color"`
	IsDefault       *bool  `json:"is_default"`
	SyncEnabled     *bool  `json:"sync_enabled"`
	SyncIntervalSec int    `json:"sync_interval_sec"`
}

func (s *Server) ListProviders(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"items": providers.All()})
}

func (s *Server) ListAccounts(c *gin.Context) {
	uid := currentUserID(c)
	rows, err := s.DB.Query(`
		SELECT a.id, a.user_id, a.label, a.email_address, a.provider_id,
		       a.imap_host, a.imap_port, a.imap_tls,
		       a.smtp_host, a.smtp_port, a.smtp_tls,
		       a.username, a.color, a.is_default, a.sync_enabled, a.sync_interval_sec,
		       a.last_sync_at, a.last_sync_status, a.last_sync_error, a.created_at,
		       COALESCE((SELECT SUM(f.unread_count) FROM folders f WHERE f.account_id = a.id AND f.role = 'inbox'), 0)
		FROM mail_accounts a
		WHERE a.user_id = ?
		ORDER BY a.is_default DESC, a.id ASC`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.MailAccount, 0)
	for rows.Next() {
		var a models.MailAccount
		var isDef, syncEn int
		var lastSync sql.NullTime
		if err := rows.Scan(
			&a.ID, &a.UserID, &a.Label, &a.EmailAddress, &a.ProviderID,
			&a.IMAPHost, &a.IMAPPort, &a.IMAPTLS,
			&a.SMTPHost, &a.SMTPPort, &a.SMTPTLS,
			&a.Username, &a.Color, &isDef, &syncEn, &a.SyncIntervalSec,
			&lastSync, &a.LastSyncStatus, &a.LastSyncError, &a.CreatedAt, &a.UnreadCount,
		); err == nil {
			a.IsDefault = isDef == 1
			a.SyncEnabled = syncEn == 1
			if lastSync.Valid {
				t := lastSync.Time
				a.LastSyncAt = &t
			}
			items = append(items, a)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) TestAccount(c *gin.Context) {
	uid := currentUserID(c)
	var req accountReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写邮箱地址与服务器配置"})
		return
	}
	applyPresetDefaults(&req)

	password := req.Password
	if password == "" && req.AccountID > 0 {
		var enc string
		if err := s.DB.QueryRow(`SELECT encrypted_password FROM mail_accounts WHERE id = ? AND user_id = ?`, req.AccountID, uid).Scan(&enc); err == nil {
			if dec, decErr := crypto.Decrypt(enc, s.Cfg.EncKey); decErr == nil {
				password = dec
			}
		}
	}
	if password == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入邮箱授权码或密码进行测试"})
		return
	}

	res := mailclient.TestConnection(mailclient.AccountConfig{
		ProviderID:   req.ProviderID,
		EmailAddress: req.EmailAddress,
		IMAPHost:     req.IMAPHost,
		IMAPPort:     req.IMAPPort,
		IMAPTLS:      req.IMAPTLS,
		SMTPHost:     req.SMTPHost,
		SMTPPort:     req.SMTPPort,
		SMTPTLS:      req.SMTPTLS,
		Username:     req.Username,
		Password:     password,
	})
	c.JSON(http.StatusOK, res)
}

func (s *Server) CreateAccount(c *gin.Context) {
	uid := currentUserID(c)
	var req accountReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "邮箱地址不能为空"})
		return
	}
	if strings.TrimSpace(req.Password) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入邮箱授权码或密码"})
		return
	}

	applyPresetDefaults(&req)
	if req.IMAPHost == "" || req.SMTPHost == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "IMAP 和 SMTP 服务器地址不能为空"})
		return
	}

	encPass, err := crypto.Encrypt(req.Password, s.Cfg.EncKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "加密凭证失败"})
		return
	}

	var existingCount int
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM mail_accounts WHERE user_id = ?`, uid).Scan(&existingCount)
	isDefault := existingCount == 0
	if req.IsDefault != nil {
		isDefault = *req.IsDefault
	}
	if isDefault {
		_, _ = s.DB.Exec(`UPDATE mail_accounts SET is_default = 0 WHERE user_id = ?`, uid)
	}

	syncEnabled := true
	if req.SyncEnabled != nil {
		syncEnabled = *req.SyncEnabled
	}
	interval := req.SyncIntervalSec
	if interval < 30 {
		interval = s.Cfg.DefaultSyncInterval
	}

	res, err := s.DB.Exec(`
		INSERT INTO mail_accounts (
			user_id, label, email_address, provider_id,
			imap_host, imap_port, imap_tls,
			smtp_host, smtp_port, smtp_tls,
			username, encrypted_password, color, is_default,
			sync_enabled, sync_interval_sec
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uid, req.Label, req.EmailAddress, req.ProviderID,
		req.IMAPHost, req.IMAPPort, req.IMAPTLS,
		req.SMTPHost, req.SMTPPort, req.SMTPTLS,
		req.Username, encPass, req.Color, boolInt(isDefault),
		boolInt(syncEnabled), interval,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "保存邮箱失败: " + err.Error()})
		return
	}
	acctID, _ := res.LastInsertId()
	_ = mailclient.EnsureStandardFolders(s.DB, acctID)

	acct, err := s.getAccountByID(uid, acctID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if syncEnabled {
		s.Scheduler.TriggerSyncByID(acctID)
	}
	c.JSON(http.StatusCreated, acct)
}

func (s *Server) UpdateAccount(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的账号 ID"})
		return
	}
	existing, err := s.getAccountByID(uid, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮箱账号不存在"})
		return
	}

	var req accountReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数有误"})
		return
	}
	applyPresetDefaults(&req)

	isDefault := existing.IsDefault
	if req.IsDefault != nil {
		isDefault = *req.IsDefault
	}
	if isDefault {
		_, _ = s.DB.Exec(`UPDATE mail_accounts SET is_default = 0 WHERE user_id = ?`, uid)
	}

	syncEnabled := existing.SyncEnabled
	if req.SyncEnabled != nil {
		syncEnabled = *req.SyncEnabled
	}
	interval := req.SyncIntervalSec
	if interval < 30 {
		interval = existing.SyncIntervalSec
	}

	if strings.TrimSpace(req.Password) != "" {
		encPass, err := crypto.Encrypt(req.Password, s.Cfg.EncKey)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "加密密码失败"})
			return
		}
		_, err = s.DB.Exec(`
			UPDATE mail_accounts
			SET label=?, email_address=?, provider_id=?,
			    imap_host=?, imap_port=?, imap_tls=?,
			    smtp_host=?, smtp_port=?, smtp_tls=?,
			    username=?, encrypted_password=?, color=?, is_default=?,
			    sync_enabled=?, sync_interval_sec=?
			WHERE id=? AND user_id=?`,
			req.Label, req.EmailAddress, req.ProviderID,
			req.IMAPHost, req.IMAPPort, req.IMAPTLS,
			req.SMTPHost, req.SMTPPort, req.SMTPTLS,
			req.Username, encPass, req.Color, boolInt(isDefault),
			boolInt(syncEnabled), interval, id, uid,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	} else {
		_, err = s.DB.Exec(`
			UPDATE mail_accounts
			SET label=?, email_address=?, provider_id=?,
			    imap_host=?, imap_port=?, imap_tls=?,
			    smtp_host=?, smtp_port=?, smtp_tls=?,
			    username=?, color=?, is_default=?,
			    sync_enabled=?, sync_interval_sec=?
			WHERE id=? AND user_id=?`,
			req.Label, req.EmailAddress, req.ProviderID,
			req.IMAPHost, req.IMAPPort, req.IMAPTLS,
			req.SMTPHost, req.SMTPPort, req.SMTPTLS,
			req.Username, req.Color, boolInt(isDefault),
			boolInt(syncEnabled), interval, id, uid,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}

	updated, _ := s.getAccountByID(uid, id)
	c.JSON(http.StatusOK, updated)
}

func (s *Server) DeleteAccount(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的账号 ID"})
		return
	}
	res, err := s.DB.Exec(`DELETE FROM mail_accounts WHERE id = ? AND user_id = ?`, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮箱账号不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

func (s *Server) TriggerSync(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的账号 ID"})
		return
	}
	if _, err := s.getAccountByID(uid, id); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮箱账号不存在"})
		return
	}
	s.Scheduler.TriggerSyncByID(id)
	c.JSON(http.StatusAccepted, gin.H{"started": true})
}

func (s *Server) ListFolders(c *gin.Context) {
	uid := currentUserID(c)
	acctFilter := c.Query("account_id")

	query := `
		SELECT f.id, f.account_id, f.name, f.remote_name, f.role, f.unread_count, f.total_count, f.uid_validity, f.last_uid
		FROM folders f
		JOIN mail_accounts a ON a.id = f.account_id
		WHERE a.user_id = ?`
	args := []interface{}{uid}
	if acctFilter != "" {
		query += ` AND f.account_id = ?`
		args = append(args, acctFilter)
	}
	query += ` ORDER BY f.account_id ASC, CASE f.role WHEN 'inbox' THEN 1 WHEN 'sent' THEN 2 WHEN 'drafts' THEN 3 WHEN 'archive' THEN 4 WHEN 'trash' THEN 5 WHEN 'spam' THEN 6 ELSE 7 END, f.id ASC`

	rows, err := s.DB.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.Folder, 0)
	for rows.Next() {
		var f models.Folder
		if err := rows.Scan(&f.ID, &f.AccountID, &f.Name, &f.RemoteName, &f.Role, &f.UnreadCount, &f.TotalCount, &f.UIDValidity, &f.LastUID); err == nil {
			items = append(items, f)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) GetStats(c *gin.Context) {
	uid := currentUserID(c)
	var stats models.Stats

	_ = s.DB.QueryRow(`
		SELECT COUNT(*) FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.user_id = ? AND f.role = 'inbox' AND m.is_read = 0`, uid).Scan(&stats.InboxUnread)

	_ = s.DB.QueryRow(`
		SELECT COUNT(*) FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.user_id = ? AND m.is_starred = 1 AND f.role NOT IN ('trash', 'spam')`, uid).Scan(&stats.StarredCount)

	_ = s.DB.QueryRow(`
		SELECT COUNT(*) FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.user_id = ? AND (m.is_draft = 1 OR f.role = 'drafts')`, uid).Scan(&stats.DraftsCount)

	stats.AccountCounts = make([]models.AccountStat, 0)
	rows, err := s.DB.Query(`
		SELECT a.id, COALESCE((SELECT COUNT(*) FROM messages m JOIN folders f ON f.id = m.folder_id WHERE m.account_id = a.id AND f.role = 'inbox' AND m.is_read = 0), 0)
		FROM mail_accounts a WHERE a.user_id = ?`, uid)
	if err == nil {
		defer func() { _ = rows.Close() }()
		for rows.Next() {
			var as models.AccountStat
			if err := rows.Scan(&as.AccountID, &as.UnreadCount); err == nil {
				stats.AccountCounts = append(stats.AccountCounts, as)
			}
		}
	}

	stats.TagCounts = make([]models.TagStat, 0)
	tagRows, err := s.DB.Query(`
		SELECT t.id, COALESCE((
			SELECT COUNT(*)
			FROM message_tags mt
			JOIN messages m ON m.id = mt.message_id
			JOIN folders f ON f.id = m.folder_id
			WHERE mt.tag_id = t.id AND m.user_id = ? AND m.is_read = 0 AND f.role NOT IN ('trash', 'spam')
		), 0)
		FROM tags t WHERE t.user_id = ?`, uid, uid)
	if err == nil {
		defer func() { _ = tagRows.Close() }()
		for tagRows.Next() {
			var ts models.TagStat
			if err := tagRows.Scan(&ts.TagID, &ts.UnreadCount); err == nil {
				stats.TagCounts = append(stats.TagCounts, ts)
			}
		}
	}

	c.JSON(http.StatusOK, stats)
}

func (s *Server) getAccountByID(userID, accountID int64) (models.MailAccount, error) {
	var a models.MailAccount
	var isDef, syncEn int
	var lastSync sql.NullTime
	err := s.DB.QueryRow(`
		SELECT a.id, a.user_id, a.label, a.email_address, a.provider_id,
		       a.imap_host, a.imap_port, a.imap_tls,
		       a.smtp_host, a.smtp_port, a.smtp_tls,
		       a.username, a.color, a.is_default, a.sync_enabled, a.sync_interval_sec,
		       a.last_sync_at, a.last_sync_status, a.last_sync_error, a.created_at
		FROM mail_accounts a
		WHERE a.id = ? AND a.user_id = ?`, accountID, userID,
	).Scan(
		&a.ID, &a.UserID, &a.Label, &a.EmailAddress, &a.ProviderID,
		&a.IMAPHost, &a.IMAPPort, &a.IMAPTLS,
		&a.SMTPHost, &a.SMTPPort, &a.SMTPTLS,
		&a.Username, &a.Color, &isDef, &syncEn, &a.SyncIntervalSec,
		&lastSync, &a.LastSyncStatus, &a.LastSyncError, &a.CreatedAt,
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

func applyPresetDefaults(req *accountReq) {
	req.EmailAddress = strings.TrimSpace(req.EmailAddress)
	if req.ProviderID == "" {
		req.ProviderID = providers.MatchByEmail(req.EmailAddress).ID
	}
	preset := providers.GetByID(req.ProviderID)
	if req.IMAPHost == "" {
		req.IMAPHost = preset.IMAPHost
	}
	if req.IMAPPort == 0 {
		req.IMAPPort = preset.IMAPPort
		if req.IMAPPort == 0 {
			req.IMAPPort = 993
		}
	}
	if req.IMAPTLS == "" {
		req.IMAPTLS = preset.IMAPTLS
		if req.IMAPTLS == "" {
			req.IMAPTLS = "ssl"
		}
	}
	if req.SMTPHost == "" {
		req.SMTPHost = preset.SMTPHost
	}
	if req.SMTPPort == 0 {
		req.SMTPPort = preset.SMTPPort
		if req.SMTPPort == 0 {
			req.SMTPPort = 465
		}
	}
	if req.SMTPTLS == "" {
		req.SMTPTLS = preset.SMTPTLS
		if req.SMTPTLS == "" {
			req.SMTPTLS = "ssl"
		}
	}
	if strings.TrimSpace(req.Username) == "" {
		req.Username = req.EmailAddress
	}
	if strings.TrimSpace(req.Label) == "" {
		req.Label = preset.Name
		if preset.ID == "custom" {
			req.Label = req.EmailAddress
		}
	}
	if strings.TrimSpace(req.Color) == "" {
		req.Color = "#2563eb"
	}
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
