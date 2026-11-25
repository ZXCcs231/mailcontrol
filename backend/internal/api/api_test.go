package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/db"
	"mailcontrol-backend/internal/syncer"
)

func setupTestRouter(t *testing.T) http.Handler {
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
	return NewRouter(conn, cfg, hub, sched)
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
			{"type": "add_tag", "value": "1"},
		},
	})
	if w.Code != http.StatusCreated {
		t.Fatalf("create rule status=%d body=%s", w.Code, w.Body.String())
	}
	var ruleResp struct {
		ID int64 `json:"id"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &ruleResp)

	w = doReq(t, h, "POST", "/api/rules/1/run", authResp.Token, nil)
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

	w = doReq(t, h, "GET", "/api/stats", authResp.Token, nil)
	if w.Code != http.StatusOK {
		t.Fatalf("stats status=%d", w.Code)
	}
}
