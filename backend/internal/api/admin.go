package api

import (
	"archive/zip"
	"database/sql"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/crypto"
)

var serverStartTime = time.Now()

func (s *Server) AdminOverview(c *gin.Context) {
	var usersCount, accountsCount, messagesCount, attachmentsCount, errorAccounts int
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&usersCount)
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM mail_accounts`).Scan(&accountsCount)
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM messages`).Scan(&messagesCount)
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM attachments`).Scan(&attachmentsCount)
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM mail_accounts WHERE last_sync_status = 'error'`).Scan(&errorAccounts)

	allowRegister := s.getSettingBool("allow_register", true)

	var dbSize int64
	if info, err := os.Stat(filepath.Join(s.Cfg.DataDir, "mailcontrol.db")); err == nil {
		dbSize = info.Size()
	}
	attSize := dirSize(filepath.Join(s.Cfg.DataDir, "attachments"))

	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)

	c.JSON(http.StatusOK, gin.H{
		"users_count":       usersCount,
		"accounts_count":    accountsCount,
		"messages_count":    messagesCount,
		"attachments_count": attachmentsCount,
		"error_accounts":    errorAccounts,
		"allow_register":    allowRegister,
		"db_size_bytes":     dbSize,
		"att_size_bytes":    attSize,
		"mem_alloc_mb":      fmt.Sprintf("%.1f", float64(mem.Alloc)/1024.0/1024.0),
		"goroutines":        runtime.NumGoroutine(),
		"uptime_sec":        int(time.Since(serverStartTime).Seconds()),
		"go_version":        runtime.Version(),
	})
}

func (s *Server) AdminListUsers(c *gin.Context) {
	rows, err := s.DB.Query(`
		SELECT u.id, u.username, u.email, u.is_admin, u.is_disabled, u.created_at,
		       (SELECT COUNT(*) FROM mail_accounts a WHERE a.user_id = u.id),
		       (SELECT COUNT(*) FROM messages m WHERE m.user_id = u.id)
		FROM users u
		ORDER BY u.id ASC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id int64
		var username, email string
		var admInt, disInt, acctsCnt, msgsCnt int
		var createdAt time.Time
		if err := rows.Scan(&id, &username, &email, &admInt, &disInt, &createdAt, &acctsCnt, &msgsCnt); err == nil {
			items = append(items, gin.H{
				"id":             id,
				"username":       username,
				"email":          email,
				"is_admin":       admInt == 1,
				"is_disabled":    disInt == 1,
				"accounts_count": acctsCnt,
				"messages_count": msgsCnt,
				"created_at":     createdAt,
			})
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

type adminUpdateUserReq struct {
	IsAdmin     *bool  `json:"is_admin"`
	IsDisabled  *bool  `json:"is_disabled"`
	NewPassword string `json:"new_password"`
}

func (s *Server) AdminUpdateUser(c *gin.Context) {
	selfID := currentUserID(c)
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效用户 ID"})
		return
	}

	var req adminUpdateUserReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if targetID == selfID {
		if req.IsDisabled != nil && *req.IsDisabled {
			c.JSON(http.StatusBadRequest, gin.H{"error": "不能禁用当前正在操作的管理员账号"})
			return
		}
		if req.IsAdmin != nil && !*req.IsAdmin {
			c.JSON(http.StatusBadRequest, gin.H{"error": "不能取消自己的管理员权限"})
			return
		}
	}

	if req.IsAdmin != nil {
		_, _ = s.DB.Exec(`UPDATE users SET is_admin = ? WHERE id = ?`, boolInt(*req.IsAdmin), targetID)
	}
	if req.IsDisabled != nil {
		_, _ = s.DB.Exec(`UPDATE users SET is_disabled = ? WHERE id = ?`, boolInt(*req.IsDisabled), targetID)
	}
	if strings.TrimSpace(req.NewPassword) != "" {
		if len(req.NewPassword) < 6 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "新密码至少需要 6 位"})
			return
		}
		hash, err := crypto.HashPassword(req.NewPassword)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
			return
		}
		_, _ = s.DB.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, hash, targetID)
	}
	c.JSON(http.StatusOK, gin.H{"updated": true})
}

func (s *Server) AdminDeleteUser(c *gin.Context) {
	selfID := currentUserID(c)
	targetID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效用户 ID"})
		return
	}
	if targetID == selfID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "不能删除当前登录的管理员账号"})
		return
	}
	res, err := s.DB.Exec(`DELETE FROM users WHERE id = ?`, targetID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

func (s *Server) AdminListAccounts(c *gin.Context) {
	rows, err := s.DB.Query(`
		SELECT a.id, a.user_id, u.username, a.label, a.email_address, a.provider_id,
		       a.sync_enabled, a.sync_interval_sec, a.last_sync_at, a.last_sync_status, a.last_sync_error,
		       (SELECT COUNT(*) FROM messages m WHERE m.account_id = a.id)
		FROM mail_accounts a
		JOIN users u ON u.id = a.user_id
		ORDER BY a.id ASC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, userID int64
		var username, label, email, providerID, syncStatus, syncErr string
		var syncEnInt, interval, msgCount int
		var lastSync sql.NullTime
		if err := rows.Scan(&id, &userID, &username, &label, &email, &providerID, &syncEnInt, &interval, &lastSync, &syncStatus, &syncErr, &msgCount); err == nil {
			var lastSyncPtr *time.Time
			if lastSync.Valid {
				t := lastSync.Time
				lastSyncPtr = &t
			}
			items = append(items, gin.H{
				"id":                id,
				"user_id":           userID,
				"username":          username,
				"label":             label,
				"email_address":     email,
				"provider_id":       providerID,
				"sync_enabled":      syncEnInt == 1,
				"sync_interval_sec": interval,
				"last_sync_at":      lastSyncPtr,
				"last_sync_status":  syncStatus,
				"last_sync_error":   syncErr,
				"messages_count":    msgCount,
			})
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) AdminTriggerSync(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效账号 ID"})
		return
	}
	if !s.Scheduler.TriggerSyncByID(id) {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮箱账号不存在"})
		return
	}
	c.JSON(http.StatusAccepted, gin.H{"started": true})
}

func (s *Server) AdminGetSettings(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"allow_register": s.getSettingBool("allow_register", true),
	})
}

type adminSettingsReq struct {
	AllowRegister *bool `json:"allow_register"`
}

func (s *Server) AdminUpdateSettings(c *gin.Context) {
	var req adminSettingsReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.AllowRegister != nil {
		val := "false"
		if *req.AllowRegister {
			val = "true"
		}
		_, err := s.DB.Exec(`
			INSERT INTO system_settings (key, value) VALUES ('allow_register', ?)
			ON CONFLICT(key) DO UPDATE SET value = excluded.value`, val)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"allow_register": s.getSettingBool("allow_register", true),
	})
}

func (s *Server) AdminTestTranslate(c *gin.Context) {
	var req struct {
		Text       string `json:"text"`
		TargetLang string `json:"target_lang"`
	}
	_ = c.ShouldBindJSON(&req)
	if strings.TrimSpace(req.Text) == "" {
		req.Text = "Hello! MailControl free translation service is working properly."
	}
	if strings.TrimSpace(req.TargetLang) == "" {
		req.TargetLang = "zh-CN"
	}
	start := time.Now()
	out, prov, err := s.getTranslator().TranslateText(c.Request.Context(), req.Text, req.TargetLang)
	elapsedMs := time.Since(start).Milliseconds()
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"success": false, "error": err.Error(), "elapsed_ms": elapsedMs})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success":         true,
		"provider":        prov,
		"translated_text": out,
		"elapsed_ms":      elapsedMs,
	})
}

func (s *Server) AdminDownloadBackup(c *gin.Context) {
	_, _ = s.DB.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`)

	filename := fmt.Sprintf("mailcontrol-backup-%s.zip", time.Now().Format("20060102-150405"))
	c.Header("Content-Type", "application/zip")
	c.Header("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, filename))

	zw := zip.NewWriter(c.Writer)
	defer func() { _ = zw.Close() }()

	for _, name := range []string{"mailcontrol.db", "secrets.json"} {
		full := filepath.Join(s.Cfg.DataDir, name)
		f, err := os.Open(full)
		if err != nil {
			continue
		}
		w, err := zw.Create(name)
		if err == nil {
			_, _ = io.Copy(w, f)
		}
		_ = f.Close()
	}
}

func (s *Server) AdminCleanupAttachments(c *gin.Context) {
	attRoot := filepath.Join(s.Cfg.DataDir, "attachments")
	rows, err := s.DB.Query(`SELECT storage_path FROM attachments`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	known := make(map[string]bool)
	for rows.Next() {
		var p string
		if rows.Scan(&p) == nil {
			if abs, err := filepath.Abs(p); err == nil {
				known[filepath.Clean(abs)] = true
			}
			known[filepath.Clean(p)] = true
		}
	}
	_ = rows.Close()

	var removedFiles int
	var freedBytes int64
	_ = filepath.WalkDir(attRoot, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		clean := filepath.Clean(path)
		abs, _ := filepath.Abs(path)
		if !known[clean] && !known[filepath.Clean(abs)] {
			if info, statErr := d.Info(); statErr == nil {
				freedBytes += info.Size()
			}
			if os.Remove(path) == nil {
				removedFiles++
			}
		}
		return nil
	})

	c.JSON(http.StatusOK, gin.H{
		"removed_files": removedFiles,
		"freed_bytes":   freedBytes,
	})
}

func (s *Server) getSettingBool(key string, fallback bool) bool {
	var val string
	if err := s.DB.QueryRow(`SELECT value FROM system_settings WHERE key = ?`, key).Scan(&val); err != nil {
		return fallback
	}
	return strings.EqualFold(val, "true") || val == "1"
}

func dirSize(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}
