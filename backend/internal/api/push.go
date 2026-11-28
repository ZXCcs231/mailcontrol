package api

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/push"
)

type pushChannelReq struct {
	Name         string `json:"name" binding:"required"`
	ChannelType  string `json:"channel_type"`
	Enabled      *bool  `json:"enabled"`
	WebhookURL   string `json:"webhook_url"`
	Secret       string `json:"secret"`
	AppID        string `json:"app_id"`
	TargetID     string `json:"target_id"`
	TargetIDType string `json:"target_id_type"`
}

func normalizePushType(t string) string {
	switch strings.ToLower(strings.TrimSpace(t)) {
	case "feishu", "feishu_app", "wecom", "dingtalk", "webhook":
		return strings.ToLower(strings.TrimSpace(t))
	default:
		return ""
	}
}

func normalizeTargetIDType(t string) string {
	switch strings.ToLower(strings.TrimSpace(t)) {
	case "open_id", "chat_id", "user_id", "email":
		return strings.ToLower(strings.TrimSpace(t))
	default:
		return "open_id"
	}
}

func validatePushReq(req pushChannelReq, isCreate bool, hasExistingSecret bool) (string, bool) {
	typ := normalizePushType(req.ChannelType)
	if typ == "" {
		return "不支持的推送通道类型", false
	}
	if typ == "feishu_app" {
		if strings.TrimSpace(req.AppID) == "" || strings.TrimSpace(req.TargetID) == "" {
			return "飞书自建应用需要填写 App ID 和接收者 ID", false
		}
		if isCreate && strings.TrimSpace(req.Secret) == "" {
			return "请输入飞书应用的 App Secret", false
		}
		if !isCreate && !hasExistingSecret && strings.TrimSpace(req.Secret) == "" {
			return "请输入飞书应用的 App Secret", false
		}
		return "", true
	}

	u := strings.TrimSpace(req.WebhookURL)
	if u == "" || (!strings.HasPrefix(u, "http://") && !strings.HasPrefix(u, "https://")) {
		return "请填写有效的 http:// 或 https:// Webhook 地址", false
	}
	return "", true
}

func (s *Server) ListPushChannels(c *gin.Context) {
	uid := currentUserID(c)
	rows, err := s.DB.Query(`
		SELECT id, user_id, name, channel_type, enabled, webhook_url, encrypted_secret, app_id, target_id, target_id_type, created_at
		FROM push_channels
		WHERE user_id = ?
		ORDER BY id ASC`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.PushChannel, 0)
	for rows.Next() {
		ch, err := scanPushChannel(rows)
		if err == nil {
			items = append(items, ch)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) CreatePushChannel(c *gin.Context) {
	uid := currentUserID(c)
	var req pushChannelReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "推送通道名称不能为空"})
		return
	}
	if req.ChannelType == "" {
		req.ChannelType = "feishu"
	}
	if msg, ok := validatePushReq(req, true, false); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	encSecret := ""
	if strings.TrimSpace(req.Secret) != "" {
		enc, err := crypto.Encrypt(strings.TrimSpace(req.Secret), s.Cfg.EncKey)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "加密密钥失败"})
			return
		}
		encSecret = enc
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}

	res, err := s.DB.Exec(`
		INSERT INTO push_channels (user_id, name, channel_type, enabled, webhook_url, encrypted_secret, app_id, target_id, target_id_type)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		uid,
		strings.TrimSpace(req.Name),
		normalizePushType(req.ChannelType),
		boolInt(enabled),
		strings.TrimSpace(req.WebhookURL),
		encSecret,
		strings.TrimSpace(req.AppID),
		strings.TrimSpace(req.TargetID),
		normalizeTargetIDType(req.TargetIDType),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	id, _ := res.LastInsertId()
	ch, _ := s.getPushChannelByID(uid, id)
	c.JSON(http.StatusCreated, ch)
}

func (s *Server) UpdatePushChannel(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的通道 ID"})
		return
	}
	existing, err := s.getPushChannelByID(uid, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "推送通道不存在"})
		return
	}

	var req pushChannelReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "推送通道名称不能为空"})
		return
	}
	if req.ChannelType == "" {
		req.ChannelType = existing.ChannelType
	}
	if msg, ok := validatePushReq(req, false, existing.HasSecret); !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	enabled := existing.Enabled
	if req.Enabled != nil {
		enabled = *req.Enabled
	}

	encSecret := existing.EncryptedSecret
	if strings.TrimSpace(req.Secret) != "" {
		enc, err := crypto.Encrypt(strings.TrimSpace(req.Secret), s.Cfg.EncKey)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "加密密钥失败"})
			return
		}
		encSecret = enc
	}

	_, err = s.DB.Exec(`
		UPDATE push_channels
		SET name=?, channel_type=?, enabled=?, webhook_url=?, encrypted_secret=?, app_id=?, target_id=?, target_id_type=?
		WHERE id=? AND user_id=?`,
		strings.TrimSpace(req.Name),
		normalizePushType(req.ChannelType),
		boolInt(enabled),
		strings.TrimSpace(req.WebhookURL),
		encSecret,
		strings.TrimSpace(req.AppID),
		strings.TrimSpace(req.TargetID),
		normalizeTargetIDType(req.TargetIDType),
		id, uid,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	updated, _ := s.getPushChannelByID(uid, id)
	c.JSON(http.StatusOK, updated)
}

func (s *Server) DeletePushChannel(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的通道 ID"})
		return
	}
	res, err := s.DB.Exec(`DELETE FROM push_channels WHERE id = ? AND user_id = ?`, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "推送通道不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

func (s *Server) TestPushChannel(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的通道 ID"})
		return
	}
	ch, err := s.getPushChannelByID(uid, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "推送通道不存在"})
		return
	}

	plainSecret := ""
	if ch.EncryptedSecret != "" {
		dec, err := crypto.Decrypt(ch.EncryptedSecret, s.Cfg.EncKey)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "解密密钥失败"})
			return
		}
		plainSecret = dec
	}

	if err := push.SendTest(ch, plainSecret); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "测试推送失败: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "测试消息已发送，请查收飞书/对应客户端"})
}

func (s *Server) getPushChannelByID(userID, id int64) (models.PushChannel, error) {
	row := s.DB.QueryRow(`
		SELECT id, user_id, name, channel_type, enabled, webhook_url, encrypted_secret, app_id, target_id, target_id_type, created_at
		FROM push_channels
		WHERE id = ? AND user_id = ?`, id, userID)
	return scanPushChannel(row)
}

type pushScanner interface {
	Scan(dest ...any) error
}

func scanPushChannel(sc pushScanner) (models.PushChannel, error) {
	var ch models.PushChannel
	var enabled int
	var createdAt sql.NullTime
	err := sc.Scan(
		&ch.ID, &ch.UserID, &ch.Name, &ch.ChannelType, &enabled,
		&ch.WebhookURL, &ch.EncryptedSecret, &ch.AppID, &ch.TargetID, &ch.TargetIDType, &createdAt,
	)
	if err != nil {
		return ch, err
	}
	ch.Enabled = enabled == 1
	ch.HasSecret = ch.EncryptedSecret != ""
	if createdAt.Valid {
		ch.CreatedAt = createdAt.Time
	}
	return ch, nil
}
