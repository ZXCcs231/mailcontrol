package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"testing"

	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/db"
	"mailcontrol-backend/internal/syncer"
)

func setupTestRouter(t *testing.T) http.Handler {
	t.Helper()
	_, h := setupTestRouterWithDB(t)
	return h
}

func setupTestRouterWithDB(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	tmpDir := t.TempDir()
	t.Setenv("DATA_DIR", tmpDir)
	cfg, err := config.Load()
	if err != nil {
		t.Fatalf("config.Load failed: %v", err)
	}
	conn, err := db.Open(filepath.Join(tmpDir, "test.db"))
	if err != nil {
		t.Fatalf("db.Open failed: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })

	hub := syncer.NewHub()
	sched := syncer.NewScheduler(conn, cfg, hub)
	return conn, NewRouter(conn, cfg, hub, sched)
}

func doReq(t *testing.T, h http.Handler, method, path, token string, body interface{}) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			t.Fatal(err)
		}
	}
	req := httptest.NewRequest(method, path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

func TestEndToEndFlow(t *testing.T) {
	h := setupTestRouter(t)

	// 1. Health & Providers
	w := doReq(t, h, "GET", "/api/health", "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("health status=%d body=%s", w.Code, w.Body.String())
	}
	w = doReq(t, h, "GET", "/api/providers", "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("providers status=%d", w.Code)
	}

	// 2. Register & Login
	w = doReq(t, h, "POST", "/api/auth/register", "", map[string]string{
		"username": "tester",
		"email":    "tester@qq.com",
		"password": "password123",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("register status=%d body=%s", w.Code, w.Body.String())
	}
	var authResp struct {
		Token string `json:"token"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &authResp)
	if authResp.Token == "" {
		t.Fatal("missing token after register")
	}

	w = doReq(t, h, "POST", "/api/auth/login", "", map[string]string{
		"account":  "tester",
		"password": "password123",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("login status=%d body=%s", w.Code, w.Body.String())
	}

	// 3. Create Mail Account (sync disabled to avoid external network call in unit test)
	syncOff := false
	w = doReq(t, h, "POST", "/api/accounts", authResp.Token, map[string]interface{}{
		"label":        "我的QQ邮箱",
		"email_address": "123456@qq.com",
		"password":     "auth-code-123",
		"sync_enabled": syncOff,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create account status=%d body=%s", w.Code, w.Body.String())
	}
	var acctResp struct {
		ID         int64  `json:"id"`
		ProviderID string `json:"provider_id"`
		IMAPHost   string `json:"imap_host"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &acctResp)
	if acctResp.ProviderID != "qq" || acctResp.IMAPHost != "imap.qq.com" {
		t.Fatalf("unexpected auto-matched preset: %+v", acctResp)
	}

	// 4. Create Tag, Signature, Draft, Rule and Run Rule
	w = doReq(t, h, "POST", "/api/tags", authResp.Token, map[string]string{
		"name":  "重要",
		"color": "#ef4444",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create tag status=%d body=%s", w.Code, w.Body.String())
	}
	var tagResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &tagResp)

	w = doReq(t, h, "POST", "/api/signatures", authResp.Token, map[string]interface{}{
		"account_id":   acctResp.ID,
		"name":         "工作签名",
		"content_html": "<p>此致<br/>敬礼</p>",
		"is_default":   true,
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create signature status=%d body=%s", w.Code, w.Body.String())
	}

	w = doReq(t, h, "POST", "/api/messages/drafts", authResp.Token, map[string]interface{}{
		"account_id": acctResp.ID,
		"to":         "friend@163.com",
		"subject":    "季度报告汇总",
		"body_text":  "请查收附件中的季度报告。",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("save draft status=%d body=%s", w.Code, w.Body.String())
	}

	w = doReq(t, h, "GET", "/api/messages?view=drafts", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list drafts status=%d body=%s", w.Code, w.Body.String())
	}
	var listResp struct {
		Total int `json:"total"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &listResp)
	if listResp.Total != 1 {
		t.Fatalf("expected 1 draft, got %d", listResp.Total)
	}

	w = doReq(t, h, "POST", "/api/rules", authResp.Token, map[string]interface{}{
		"name":       "报告自动标星打标",
		"match_mode": "all",
		"conditions": []map[string]string{
			{"field": "subject", "operator": "contains", "value": "季度报告"},
		},
		"actions": []map[string]interface{}{
			{"type": "star"},
			{"type": "add_tag", "value": strconv.FormatInt(tagResp.ID, 10)},
		},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create rule status=%d body=%s", w.Code, w.Body.String())
	}
	var ruleResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &ruleResp)

	w = doReq(t, h, "POST", fmt.Sprintf("/api/rules/%d/run", ruleResp.ID), authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("run rule status=%d body=%s", w.Code, w.Body.String())
	}
	var runResp struct {
		Matched int `json:"matched"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &runResp)
	if runResp.Matched != 1 {
		t.Fatalf("expected rule to match 1 message, got %d", runResp.Matched)
	}

	w = doReq(t, h, "GET", "/api/rules/presets", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("rule presets status=%d", w.Code)
	}
	w = doReq(t, h, "POST", "/api/rules/presets/apply", authResp.Token, map[string]interface{}{})
	if w.Code != http.StatusOK {
		t.Fatalf("apply rule presets status=%d", w.Code)
	}
	var applyResp struct {
		Added int `json:"added"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &applyResp)
	if applyResp.Added != 0 {
		t.Fatalf("expected 0 added on second apply (idempotent), got %d", applyResp.Added)
	}

	w = doReq(t, h, "GET", "/api/stats", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("stats status=%d", w.Code)
	}
	var statsResp struct {
		TagCounts []struct {
			TagID       int64 `json:"tag_id"`
			UnreadCount int   `json:"unread_count"`
		} `json:"tag_counts"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &statsResp); err != nil {
		t.Fatalf("decode stats: %v", err)
	}
	if statsResp.TagCounts == nil {
		t.Fatalf("expected non-nil tag_counts in /api/stats response: %s", w.Body.String())
	}

	w = doReq(t, h, "GET", "/api/server-info", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("server-info status=%d", w.Code)
	}

	w = doReq(t, h, "GET", "/api/translate/languages", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("translate languages status=%d", w.Code)
	}

	// Admin endpoints & registration toggle
	w = doReq(t, h, "GET", "/admin", "", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("admin page status=%d", w.Code)
	}
	w = doReq(t, h, "GET", "/api/admin/overview", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("admin overview status=%d body=%s", w.Code, w.Body.String())
	}
	w = doReq(t, h, "PUT", "/api/admin/settings", authResp.Token, map[string]bool{"allow_register": false})
	if w.Code != http.StatusOK {
		t.Fatalf("admin settings status=%d", w.Code)
	}
	w = doReq(t, h, "POST", "/api/auth/register", "", map[string]string{
		"username": "blocked_user",
		"email":    "blocked@qq.com",
		"password": "password123",
	})
	if w.Code != http.StatusForbidden {
		t.Fatalf("expected 403 when registration closed, got %d", w.Code)
	}
}

func TestDirtySQLiteTimestampMessagesNotDropped(t *testing.T) {
	conn, h := setupTestRouterWithDB(t)

	w := doReq(t, h, "POST", "/api/auth/register", "", map[string]string{
		"username": "tsuser",
		"email":    "tsuser@qq.com",
		"password": "password123",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("register status=%d body=%s", w.Code, w.Body.String())
	}
	var authResp struct {
		Token string `json:"token"`
		User  struct {
			ID int64 `json:"id"`
		} `json:"user"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &authResp)

	w = doReq(t, h, "POST", "/api/accounts", authResp.Token, map[string]interface{}{
		"label":         "Gmail",
		"email_address": "tsuser@gmail.com",
		"password":      "secret",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create account status=%d body=%s", w.Code, w.Body.String())
	}
	var acctResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &acctResp)

	w = doReq(t, h, "POST", "/api/tags", authResp.Token, map[string]string{
		"name":  "测试账单",
		"color": "#f59e0b",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create tag status=%d body=%s", w.Code, w.Body.String())
	}
	var tagResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &tagResp)

	var folderID int64
	if err := conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? LIMIT 1`, acctResp.ID).Scan(&folderID); err != nil {
		t.Fatalf("find folder: %v", err)
	}

	res, err := conn.Exec(`
		INSERT INTO messages (
			user_id, account_id, folder_id, subject, from_name, from_addr,
			to_addrs, snippet, is_read, sent_at, received_at
		) VALUES (?, ?, ?, 'Invoice #1001', 'Billing', 'billing@example.com', 'tsuser@gmail.com', 'Payment receipt', 0, ?, ?)`,
		authResp.User.ID, acctResp.ID, folderID,
		"2026-11-24 10:49:07 -0800 -0800",
		"2026-11-24 18:49:07 +0000 +0000",
	)
	if err != nil {
		t.Fatalf("insert dirty timestamp message: %v", err)
	}
	msgID, _ := res.LastInsertId()
	if _, err := conn.Exec(`INSERT INTO message_tags (message_id, tag_id) VALUES (?, ?)`, msgID, tagResp.ID); err != nil {
		t.Fatalf("tag message: %v", err)
	}

	w = doReq(t, h, "GET", fmt.Sprintf("/api/messages?view=tag&tag_id=%d", tagResp.ID), authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list tag messages status=%d body=%s", w.Code, w.Body.String())
	}
	var listResp struct {
		Total int `json:"total"`
		Items []struct {
			ID      int64  `json:"id"`
			Subject string `json:"subject"`
		} `json:"items"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &listResp)
	if listResp.Total != 1 || len(listResp.Items) != 1 || listResp.Items[0].ID != msgID {
		t.Fatalf("expected 1 message in tag view, got total=%d items=%+v", listResp.Total, listResp.Items)
	}

	w = doReq(t, h, "GET", fmt.Sprintf("/api/messages/%d", msgID), authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("get message status=%d body=%s", w.Code, w.Body.String())
	}
}

func TestSiblingCopiesSyncReadAndCleanupVirtualFolders(t *testing.T) {
	conn, h := setupTestRouterWithDB(t)

	w := doReq(t, h, "POST", "/api/auth/register", "", map[string]string{
		"username": "syncuser",
		"email":    "syncuser@qq.com",
		"password": "password123",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("register status=%d body=%s", w.Code, w.Body.String())
	}
	var authResp struct {
		Token string `json:"token"`
		User  struct {
			ID int64 `json:"id"`
		} `json:"user"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &authResp)

	w = doReq(t, h, "POST", "/api/accounts", authResp.Token, map[string]interface{}{
		"label":         "Gmail",
		"email_address": "syncuser@gmail.com",
		"password":      "secret",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create account status=%d body=%s", w.Code, w.Body.String())
	}
	var acctResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &acctResp)

	w = doReq(t, h, "POST", "/api/tags", authResp.Token, map[string]string{
		"name":  "同步测试标签",
		"color": "#10b981",
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create tag status=%d body=%s", w.Code, w.Body.String())
	}
	var tagResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &tagResp)

	var inboxID int64
	if err := conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? AND role = 'inbox' LIMIT 1`, acctResp.ID).Scan(&inboxID); err != nil {
		t.Fatalf("find inbox folder: %v", err)
	}
	resF, err := conn.Exec(`INSERT INTO folders (account_id, name, remote_name, role) VALUES (?, '所有邮件', '[Gmail]/所有邮件', 'custom')`, acctResp.ID)
	if err != nil {
		t.Fatalf("insert virtual folder: %v", err)
	}
	virtualFolderID, _ := resF.LastInsertId()

	// 在收件箱和虚拟文件夹各插入一条同 Message-ID 的未读副本，验证 PatchMessage 跨副本联动已读
	res1, err := conn.Exec(`
		INSERT INTO messages (user_id, account_id, folder_id, message_id_header, subject, from_addr, to_addrs, is_read, sent_at, received_at)
		VALUES (?, ?, ?, '<dup-1@gmail.com>', 'Dup Subject', 'a@b.com', 'syncuser@gmail.com', 0, '2026-11-26 01:00:00', '2026-11-26 01:00:00')`,
		authResp.User.ID, acctResp.ID, inboxID)
	if err != nil {
		t.Fatalf("insert inbox dup: %v", err)
	}
	inboxMsgID, _ := res1.LastInsertId()

	res2, err := conn.Exec(`
		INSERT INTO messages (user_id, account_id, folder_id, message_id_header, subject, from_addr, to_addrs, is_read, sent_at, received_at)
		VALUES (?, ?, ?, '<dup-1@gmail.com>', 'Dup Subject', 'a@b.com', 'syncuser@gmail.com', 0, '2026-11-26 01:00:00', '2026-11-26 01:00:00')`,
		authResp.User.ID, acctResp.ID, virtualFolderID)
	if err != nil {
		t.Fatalf("insert virtual dup: %v", err)
	}
	virtualMsgID, _ := res2.LastInsertId()
	_, _ = conn.Exec(`INSERT INTO message_tags (message_id, tag_id) VALUES (?, ?)`, virtualMsgID, tagResp.ID)

	// 插入一条仅存在于“[Gmail]/所有邮件”的归档唯一邮件，验证迁移时会保留进 archive 文件夹
	_, err = conn.Exec(`
		INSERT INTO messages (user_id, account_id, folder_id, message_id_header, subject, from_addr, to_addrs, is_read, sent_at, received_at)
		VALUES (?, ?, ?, '<unique-arch@gmail.com>', 'Archived Only', 'a@b.com', 'syncuser@gmail.com', 0, '2026-11-26 00:00:00', '2026-11-26 00:00:00')`,
		authResp.User.ID, acctResp.ID, virtualFolderID)
	if err != nil {
		t.Fatalf("insert unique archive msg: %v", err)
	}

	// 将收件箱副本标为已读 -> 虚拟副本也应同步已读且统计归零
	w = doReq(t, h, "PATCH", fmt.Sprintf("/api/messages/%d", inboxMsgID), authResp.Token, map[string]bool{"is_read": true})
	if w.Code != http.StatusOK {
		t.Fatalf("patch message status=%d", w.Code)
	}
	var virtualIsRead int
	_ = conn.QueryRow(`SELECT is_read FROM messages WHERE id = ?`, virtualMsgID).Scan(&virtualIsRead)
	if virtualIsRead != 1 {
		t.Fatalf("expected virtual copy is_read=1, got %d", virtualIsRead)
	}

	// 运行迁移清理虚拟聚合文件夹：合并标签到收件箱真身、删重并把唯一邮件迁入 archive
	if err := db.Migrate(conn); err != nil {
		t.Fatalf("db.Migrate failed: %v", err)
	}
	var vFolderCnt int
	_ = conn.QueryRow(`SELECT COUNT(*) FROM folders WHERE id = ?`, virtualFolderID).Scan(&vFolderCnt)
	if vFolderCnt != 0 {
		t.Fatalf("expected virtual folder deleted, still exists")
	}
	var tagOnReal int
	_ = conn.QueryRow(`SELECT COUNT(*) FROM message_tags WHERE message_id = ? AND tag_id = ?`, inboxMsgID, tagResp.ID).Scan(&tagOnReal)
	if tagOnReal != 1 {
		t.Fatalf("expected tag migrated to real inbox message")
	}
	var archRole string
	_ = conn.QueryRow(`SELECT f.role FROM messages m JOIN folders f ON f.id = m.folder_id WHERE m.message_id_header = '<unique-arch@gmail.com>'`).Scan(&archRole)
	if archRole != "archive" {
		t.Fatalf("expected unique archived message moved to archive role, got %q", archRole)
	}
}
