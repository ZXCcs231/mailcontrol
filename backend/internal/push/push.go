package push

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/db"
	"mailcontrol-backend/internal/models"
)

const defaultFeishuAPIBase = "https://open.feishu.cn"

var httpClient = &http.Client{Timeout: 10 * time.Second}

type mailPayloadItem struct {
	ID         int64
	Subject    string
	Sender     string
	Snippet    string
	Tags       []string
	ReceivedAt time.Time
}

// NotifyNewMessages 异步向用户已启用的外部推送通道发送新邮件卡片。
// 仅推送经过自动规则处理后仍位于收件箱且为未读状态的邮件。
func NotifyNewMessages(conn *sql.DB, encKey []byte, acct models.MailAccount, rawMsgs []models.Message) {
	if conn == nil || len(rawMsgs) == 0 {
		return
	}

	channels, err := loadEnabledChannels(conn, acct.UserID)
	if err != nil || len(channels) == 0 {
		return
	}

	items := filterFreshInboxMessages(conn, rawMsgs)
	if len(items) == 0 {
		return
	}

	accountName := strings.TrimSpace(acct.Label)
	if accountName == "" {
		accountName = acct.EmailAddress
	}

	for _, ch := range channels {
		secret := ""
		if ch.EncryptedSecret != "" {
			dec, decErr := crypto.Decrypt(ch.EncryptedSecret, encKey)
			if decErr != nil {
				log.Printf("push decrypt secret error channel=%d: %v", ch.ID, decErr)
				continue
			}
			secret = dec
		}
		if err := sendItemsToChannel(ch, secret, accountName, acct.EmailAddress, items, defaultFeishuAPIBase); err != nil {
			log.Printf("push send error channel=%d type=%s: %v", ch.ID, ch.ChannelType, err)
		}
	}
}

// SendTest 向指定通道发送一条测试通知，验证连通性与密钥配置。
func SendTest(ch models.PushChannel, plainSecret string) error {
	sample := []mailPayloadItem{
		{
			ID:         0,
			Subject:    "MailControl 推送通道连通测试",
			Sender:     "MailControl 系统通知",
			Snippet:    "如果你看到这条消息，说明你的飞书 / 推送通道配置已经生效，手机彻底退出 App 后也能即时收到新邮件提醒。",
			Tags:       []string{"测试通知"},
			ReceivedAt: time.Now(),
		},
	}
	return sendItemsToChannel(ch, plainSecret, "测试邮箱", "system@mailcontrol", sample, defaultFeishuAPIBase)
}

func loadEnabledChannels(conn *sql.DB, userID int64) ([]models.PushChannel, error) {
	rows, err := conn.Query(`
		SELECT id, user_id, name, channel_type, enabled, webhook_url, encrypted_secret, app_id, target_id, target_id_type
		FROM push_channels
		WHERE user_id = ? AND enabled = 1
		ORDER BY id ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()

	var list []models.PushChannel
	for rows.Next() {
		var ch models.PushChannel
		var enabled int
		if err := rows.Scan(
			&ch.ID, &ch.UserID, &ch.Name, &ch.ChannelType, &enabled,
			&ch.WebhookURL, &ch.EncryptedSecret, &ch.AppID, &ch.TargetID, &ch.TargetIDType,
		); err == nil {
			ch.Enabled = enabled == 1
			ch.HasSecret = ch.EncryptedSecret != ""
			list = append(list, ch)
		}
	}
	return list, nil
}

func filterFreshInboxMessages(conn *sql.DB, rawMsgs []models.Message) []mailPayloadItem {
	ids := make([]int64, 0, len(rawMsgs))
	placeholders := make([]string, 0, len(rawMsgs))
	args := make([]any, 0, len(rawMsgs))
	for _, m := range rawMsgs {
		if m.ID <= 0 {
			continue
		}
		ids = append(ids, m.ID)
		placeholders = append(placeholders, "?")
		args = append(args, m.ID)
	}
	if len(ids) == 0 {
		return nil
	}

	tagMap := make(map[int64][]string)
	tRows, err := conn.Query(`
		SELECT mt.message_id, t.name
		FROM message_tags mt
		JOIN tags t ON t.id = mt.tag_id
		WHERE mt.message_id IN (`+strings.Join(placeholders, ",")+`)`, args...)
	if err == nil {
		for tRows.Next() {
			var mid int64
			var tname string
			if tRows.Scan(&mid, &tname) == nil && strings.TrimSpace(tname) != "" {
				tagMap[mid] = append(tagMap[mid], tname)
			}
		}
		_ = tRows.Close()
	}

	rows, err := conn.Query(`
		SELECT m.id, m.subject, m.from_name, m.from_addr, m.snippet, m.received_at, m.is_read, f.role
		FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.id IN (`+strings.Join(placeholders, ",")+`)
		ORDER BY m.received_at DESC, m.id DESC`, args...)
	if err != nil {
		return nil
	}
	defer func() { _ = rows.Close() }()

	var items []mailPayloadItem
	for rows.Next() {
		var id int64
		var subj, fromName, fromAddr, snippet, role string
		var rawRecv any
		var isRead int
		if err := rows.Scan(&id, &subj, &fromName, &fromAddr, &snippet, &rawRecv, &isRead, &role); err != nil {
			continue
		}
		if isRead == 1 || role != "inbox" {
			continue
		}
		sender := strings.TrimSpace(fromName)
		if sender == "" {
			sender = strings.TrimSpace(fromAddr)
		}
		if sender == "" {
			sender = "未知发件人"
		}
		recv := db.ParseSQLiteTime(rawRecv)
		if recv.IsZero() {
			recv = time.Now()
		}
		items = append(items, mailPayloadItem{
			ID:         id,
			Subject:    defaultString(strings.TrimSpace(subj), "（无主题）"),
			Sender:     sender,
			Snippet:    truncateRunes(strings.TrimSpace(snippet), 160),
			Tags:       tagMap[id],
			ReceivedAt: recv.Local(),
		})
	}
	return items
}

func sendItemsToChannel(
	ch models.PushChannel,
	secret string,
	accountLabel string,
	accountEmail string,
	items []mailPayloadItem,
	feishuAPIBase string,
) error {
	if len(items) <= 3 {
		for _, item := range items {
			title, cardColor, mdBody := formatSingleMessage(accountLabel, accountEmail, item)
			if err := dispatchMessage(ch, secret, title, cardColor, mdBody, accountLabel, items[:1], feishuAPIBase); err != nil {
				return err
			}
		}
		return nil
	}

	title, cardColor, mdBody := formatBatchSummary(accountLabel, accountEmail, items)
	return dispatchMessage(ch, secret, title, cardColor, mdBody, accountLabel, items, feishuAPIBase)
}

func dispatchMessage(
	ch models.PushChannel,
	secret string,
	title string,
	cardColor string,
	mdBody string,
	accountLabel string,
	items []mailPayloadItem,
	feishuAPIBase string,
) error {
	switch ch.ChannelType {
	case "feishu":
		return sendFeishuWebhook(ch.WebhookURL, secret, title, cardColor, mdBody)
	case "feishu_app":
		return sendFeishuAppMessage(feishuAPIBase, ch.AppID, secret, ch.TargetIDType, ch.TargetID, title, cardColor, mdBody)
	case "wecom":
		return sendWecomWebhook(ch.WebhookURL, title, mdBody)
	case "dingtalk":
		return sendDingTalkWebhook(ch.WebhookURL, secret, title, mdBody)
	case "webhook":
		return sendGenericWebhook(ch.WebhookURL, secret, title, mdBody, accountLabel, items)
	default:
		return fmt.Errorf("不支持的推送类型: %s", ch.ChannelType)
	}
}

func formatSingleMessage(accountLabel, accountEmail string, item mailPayloadItem) (title, templateColor, mdBody string) {
	tagBadge := ""
	if len(item.Tags) > 0 {
		limit := len(item.Tags)
		if limit > 2 {
			limit = 2
		}
		tagBadge = "[" + strings.Join(item.Tags[:limit], " / ") + "] "
	}
	title = fmt.Sprintf("%s%s · %s", tagBadge, accountLabel, item.Subject)
	templateColor = pickFeishuCardColor(item.Tags)

	var b strings.Builder
	fmt.Fprintf(&b, "**发件人：** %s\n", item.Sender)
	fmt.Fprintf(&b, "**收件箱：** %s (%s)\n", accountLabel, accountEmail)
	if len(item.Tags) > 0 {
		fmt.Fprintf(&b, "**标签：** %s\n", strings.Join(item.Tags, " / "))
	}
	fmt.Fprintf(&b, "**时间：** %s\n", item.ReceivedAt.Format("2006-01-02 15:04:05"))
	if item.Snippet != "" {
		fmt.Fprintf(&b, "\n> %s", strings.ReplaceAll(item.Snippet, "\n", " "))
	}
	return title, templateColor, b.String()
}

func formatBatchSummary(accountLabel, accountEmail string, items []mailPayloadItem) (title, templateColor, mdBody string) {
	title = fmt.Sprintf("%s 收到 %d 封新邮件", accountLabel, len(items))
	templateColor = "blue"

	var b strings.Builder
	fmt.Fprintf(&b, "**收件箱：** %s (%s)\n\n", accountLabel, accountEmail)
	limit := len(items)
	if limit > 5 {
		limit = 5
	}
	for i := 0; i < limit; i++ {
		it := items[i]
		tagText := ""
		if len(it.Tags) > 0 {
			tagText = "[" + it.Tags[0] + "] "
		}
		fmt.Fprintf(&b, "%d. %s**%s** — %s\n", i+1, tagText, it.Sender, it.Subject)
	}
	if len(items) > limit {
		fmt.Fprintf(&b, "\n*另有 %d 封新邮件，请打开 MailControl 查看*", len(items)-limit)
	}
	return title, templateColor, b.String()
}

func pickFeishuCardColor(tags []string) string {
	for _, t := range tags {
		switch {
		case strings.Contains(t, "安全") || strings.Contains(t, "告警"):
			return "red"
		case strings.Contains(t, "验证码"):
			return "turquoise"
		case strings.Contains(t, "账单") || strings.Contains(t, "发票"):
			return "orange"
		case strings.Contains(t, "开发"):
			return "purple"
		case strings.Contains(t, "订单") || strings.Contains(t, "物流"):
			return "green"
		}
	}
	return "blue"
}

func buildFeishuCardObject(title, color, mdBody string) map[string]any {
	return map[string]any{
		"config": map[string]any{
			"wide_screen_mode": true,
		},
		"header": map[string]any{
			"template": color,
			"title": map[string]any{
				"tag":     "plain_text",
				"content": title,
			},
		},
		"elements": []map[string]any{
			{
				"tag":     "markdown",
				"content": mdBody,
			},
		},
	}
}

func sendFeishuWebhook(webhookURL, secret, title, color, mdBody string) error {
	if strings.TrimSpace(webhookURL) == "" {
		return fmt.Errorf("飞书 Webhook 地址不能为空")
	}
	payload := map[string]any{
		"msg_type": "interactive",
		"card":     buildFeishuCardObject(title, color, mdBody),
	}
	if strings.TrimSpace(secret) != "" {
		ts := time.Now().Unix()
		payload["timestamp"] = strconv.FormatInt(ts, 10)
		payload["sign"] = GenFeishuSign(ts, strings.TrimSpace(secret))
	}

	raw, err := postJSON(webhookURL, nil, payload)
	if err != nil {
		return err
	}
	var resp struct {
		Code       int    `json:"code"`
		StatusCode int    `json:"StatusCode"`
		Msg        string `json:"msg"`
		StatusMsg  string `json:"StatusMessage"`
	}
	if err := json.Unmarshal(raw, &resp); err == nil {
		if resp.Code != 0 {
			return fmt.Errorf("飞书返回错误(%d): %s", resp.Code, defaultString(resp.Msg, string(raw)))
		}
		if resp.StatusCode != 0 {
			return fmt.Errorf("飞书返回错误(%d): %s", resp.StatusCode, defaultString(resp.StatusMsg, string(raw)))
		}
	}
	return nil
}

// GenFeishuSign 生成飞书自定义机器人 HMAC-SHA256 签名。
func GenFeishuSign(timestamp int64, secret string) string {
	stringToSign := fmt.Sprintf("%d\n%s", timestamp, secret)
	h := hmac.New(sha256.New, []byte(stringToSign))
	_, _ = h.Write([]byte{})
	return base64.StdEncoding.EncodeToString(h.Sum(nil))
}

func sendFeishuAppMessage(apiBase, appID, appSecret, receiveIDType, receiveID, title, color, mdBody string) error {
	if strings.TrimSpace(appID) == "" || strings.TrimSpace(appSecret) == "" || strings.TrimSpace(receiveID) == "" {
		return fmt.Errorf("飞书应用 App ID、App Secret 与接收者 ID 不能为空")
	}
	if strings.TrimSpace(receiveIDType) == "" {
		receiveIDType = "open_id"
	}
	base := strings.TrimRight(defaultString(apiBase, defaultFeishuAPIBase), "/")

	tokenRaw, err := postJSON(base+"/open-apis/auth/v3/tenant_access_token/internal", nil, map[string]string{
		"app_id":     strings.TrimSpace(appID),
		"app_secret": strings.TrimSpace(appSecret),
	})
	if err != nil {
		return err
	}
	var tokenResp struct {
		Code              int    `json:"code"`
		Msg               string `json:"msg"`
		TenantAccessToken string `json:"tenant_access_token"`
	}
	if err := json.Unmarshal(tokenRaw, &tokenResp); err != nil {
		return fmt.Errorf("解析飞书 token 响应失败: %w", err)
	}
	if tokenResp.Code != 0 || tokenResp.TenantAccessToken == "" {
		return fmt.Errorf("获取飞书 tenant_access_token 失败(%d): %s", tokenResp.Code, tokenResp.Msg)
	}

	cardJSON, err := json.Marshal(buildFeishuCardObject(title, color, mdBody))
	if err != nil {
		return err
	}
	msgURL := fmt.Sprintf("%s/open-apis/im/v1/messages?receive_id_type=%s", base, url.QueryEscape(receiveIDType))
	headers := map[string]string{
		"Authorization": "Bearer " + tokenResp.TenantAccessToken,
	}
	msgRaw, err := postJSON(msgURL, headers, map[string]any{
		"receive_id": strings.TrimSpace(receiveID),
		"msg_type":   "interactive",
		"content":    string(cardJSON),
	})
	if err != nil {
		return err
	}
	var sendResp struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
	}
	if err := json.Unmarshal(msgRaw, &sendResp); err == nil && sendResp.Code != 0 {
		return fmt.Errorf("飞书发送消息失败(%d): %s", sendResp.Code, sendResp.Msg)
	}
	return nil
}

func sendWecomWebhook(webhookURL, title, mdBody string) error {
	if strings.TrimSpace(webhookURL) == "" {
		return fmt.Errorf("企业微信 Webhook 地址不能为空")
	}
	payload := map[string]any{
		"msgtype": "markdown",
		"markdown": map[string]string{
			"content": fmt.Sprintf("### %s\n%s", title, mdBody),
		},
	}
	raw, err := postJSON(webhookURL, nil, payload)
	if err != nil {
		return err
	}
	var resp struct {
		ErrCode int    `json:"errcode"`
		ErrMsg  string `json:"errmsg"`
	}
	if err := json.Unmarshal(raw, &resp); err == nil && resp.ErrCode != 0 {
		return fmt.Errorf("企业微信返回错误(%d): %s", resp.ErrCode, resp.ErrMsg)
	}
	return nil
}

func sendDingTalkWebhook(webhookURL, secret, title, mdBody string) error {
	targetURL := strings.TrimSpace(webhookURL)
	if targetURL == "" {
		return fmt.Errorf("钉钉 Webhook 地址不能为空")
	}
	if strings.TrimSpace(secret) != "" {
		ts := time.Now().UnixMilli()
		stringToSign := fmt.Sprintf("%d\n%s", ts, strings.TrimSpace(secret))
		h := hmac.New(sha256.New, []byte(strings.TrimSpace(secret)))
		_, _ = h.Write([]byte(stringToSign))
		sign := url.QueryEscape(base64.StdEncoding.EncodeToString(h.Sum(nil)))
		sep := "?"
		if strings.Contains(targetURL, "?") {
			sep = "&"
		}
		targetURL = fmt.Sprintf("%s%stimestamp=%d&sign=%s", targetURL, sep, ts, sign)
	}
	payload := map[string]any{
		"msgtype": "markdown",
		"markdown": map[string]string{
			"title": title,
			"text":  fmt.Sprintf("### %s\n\n%s", title, mdBody),
		},
	}
	raw, err := postJSON(targetURL, nil, payload)
	if err != nil {
		return err
	}
	var resp struct {
		ErrCode int    `json:"errcode"`
		ErrMsg  string `json:"errmsg"`
	}
	if err := json.Unmarshal(raw, &resp); err == nil && resp.ErrCode != 0 {
		return fmt.Errorf("钉钉返回错误(%d): %s", resp.ErrCode, resp.ErrMsg)
	}
	return nil
}

func sendGenericWebhook(webhookURL, secret, title, mdBody, accountLabel string, items []mailPayloadItem) error {
	if strings.TrimSpace(webhookURL) == "" {
		return fmt.Errorf("Webhook 地址不能为空")
	}
	msgList := make([]map[string]any, 0, len(items))
	for _, it := range items {
		msgList = append(msgList, map[string]any{
			"id":          it.ID,
			"subject":     it.Subject,
			"sender":      it.Sender,
			"snippet":     it.Snippet,
			"tags":        it.Tags,
			"received_at": it.ReceivedAt.Format(time.RFC3339),
		})
	}
	payload := map[string]any{
		"event":         "new_messages",
		"title":         title,
		"body":          mdBody,
		"account_label": accountLabel,
		"count":         len(items),
		"messages":      msgList,
	}
	var headers map[string]string
	if strings.TrimSpace(secret) != "" {
		headers = map[string]string{"X-Webhook-Secret": strings.TrimSpace(secret)}
	}
	_, err := postJSON(webhookURL, headers, payload)
	return err
}

func postJSON(targetURL string, headers map[string]string, body any) ([]byte, error) {
	b, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, targetURL, bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return raw, fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))
	}
	return raw, nil
}

func defaultString(val, fallback string) string {
	if strings.TrimSpace(val) == "" {
		return fallback
	}
	return val
}

func truncateRunes(s string, maxLen int) string {
	r := []rune(s)
	if len(r) <= maxLen {
		return s
	}
	return string(r[:maxLen]) + "..."
}
