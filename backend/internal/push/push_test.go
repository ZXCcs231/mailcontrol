package push

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"mailcontrol-backend/internal/models"
)

func TestGenFeishuSignAndWebhook(t *testing.T) {
	var gotBody map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() { _ = r.Body.Close() }()
		if err := json.NewDecoder(r.Body).Decode(&gotBody); err != nil {
			t.Fatalf("decode failed: %v", err)
		}
		_, _ = w.Write([]byte(`{"code":0,"msg":"success"}`))
	}))
	defer srv.Close()

	ch := models.PushChannel{
		ID:          1,
		Name:        "飞书测试",
		ChannelType: "feishu",
		Enabled:     true,
		WebhookURL:  srv.URL,
	}
	items := []mailPayloadItem{
		{
			ID:         42,
			Subject:    "您的登录验证码是 884210",
			Sender:     "GitHub",
			Snippet:    "Verification code: 884210",
			Tags:       []string{"验证码"},
			ReceivedAt: time.Now(),
		},
	}

	if err := sendItemsToChannel(ch, "sec_demo", "QQ邮箱", "test@example.com", items, srv.URL); err != nil {
		t.Fatalf("sendItemsToChannel error: %v", err)
	}
	if gotBody["msg_type"] != "interactive" {
		t.Fatalf("expected interactive msg_type, got %v", gotBody["msg_type"])
	}
	if gotBody["timestamp"] == "" || gotBody["sign"] == "" {
		t.Fatalf("expected timestamp & sign in feishu webhook payload, got %+v", gotBody)
	}
}

func TestFeishuAppMessageFlow(t *testing.T) {
	var gotAuthHeader string
	var gotReceiveIDType string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/tenant_access_token/internal"):
			_, _ = w.Write([]byte(`{"code":0,"tenant_access_token":"t-demo-token"}`))
		case strings.HasSuffix(r.URL.Path, "/im/v1/messages"):
			gotAuthHeader = r.Header.Get("Authorization")
			gotReceiveIDType = r.URL.Query().Get("receive_id_type")
			_, _ = w.Write([]byte(`{"code":0,"msg":"ok"}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	ch := models.PushChannel{
		ID:           2,
		Name:         "飞书私聊",
		ChannelType:  "feishu_app",
		Enabled:      true,
		AppID:        "cli_demo",
		TargetID:     "ou_123456",
		TargetIDType: "open_id",
	}
	items := []mailPayloadItem{
		{
			ID:         1,
			Subject:    "服务器告警",
			Sender:     "Monitor",
			Tags:       []string{"安全告警"},
			ReceivedAt: time.Now(),
		},
	}

	if err := sendItemsToChannel(ch, "app_secret_demo", "工作邮箱", "work@example.com", items, srv.URL); err != nil {
		t.Fatalf("sendItemsToChannel feishu_app error: %v", err)
	}
	if gotAuthHeader != "Bearer t-demo-token" {
		t.Fatalf("expected bearer token, got %q", gotAuthHeader)
	}
	if gotReceiveIDType != "open_id" {
		t.Fatalf("expected receive_id_type=open_id, got %q", gotReceiveIDType)
	}
}

func TestWecomDingTalkAndWebhook(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		_, _ = w.Write([]byte(`{"errcode":0,"errmsg":"ok"}`))
	}))
	defer srv.Close()

	items := []mailPayloadItem{
		{ID: 1, Subject: "账单", Sender: "Billing", ReceivedAt: time.Now()},
	}
	for _, typ := range []string{"wecom", "dingtalk", "webhook"} {
		ch := models.PushChannel{ChannelType: typ, WebhookURL: srv.URL}
		if err := sendItemsToChannel(ch, "s", "主邮箱", "a@example.com", items, srv.URL); err != nil {
			t.Fatalf("%s failed: %v", typ, err)
		}
	}
	if calls != 3 {
		t.Fatalf("expected 3 webhook calls, got %d", calls)
	}
}
