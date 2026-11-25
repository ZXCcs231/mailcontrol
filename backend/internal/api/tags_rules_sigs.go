package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/rules"
)

type tagReq struct {
	Name  string `json:"name" binding:"required"`
	Color string `json:"color"`
}

func (s *Server) ListTags(c *gin.Context) {
	uid := currentUserID(c)
	rows, err := s.DB.Query(`SELECT id, user_id, name, color FROM tags WHERE user_id = ? ORDER BY id ASC`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.Tag, 0)
	for rows.Next() {
		var t models.Tag
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.Color); err == nil {
			items = append(items, t)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) CreateTag(c *gin.Context) {
	uid := currentUserID(c)
	var req tagReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "标签名称不能为空"})
		return
	}
	if strings.TrimSpace(req.Color) == "" {
		req.Color = "#3b82f6"
	}
	res, err := s.DB.Exec(`INSERT INTO tags (user_id, name, color) VALUES (?, ?, ?)`, uid, strings.TrimSpace(req.Name), req.Color)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "已存在同名标签"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	id, _ := res.LastInsertId()
	c.JSON(http.StatusCreated, models.Tag{ID: id, UserID: uid, Name: strings.TrimSpace(req.Name), Color: req.Color})
}

func (s *Server) UpdateTag(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效标签 ID"})
		return
	}
	var req tagReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "标签名称不能为空"})
		return
	}
	if strings.TrimSpace(req.Color) == "" {
		req.Color = "#3b82f6"
	}
	res, err := s.DB.Exec(`UPDATE tags SET name=?, color=? WHERE id=? AND user_id=?`, strings.TrimSpace(req.Name), req.Color, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "标签不存在"})
		return
	}
	c.JSON(http.StatusOK, models.Tag{ID: id, UserID: uid, Name: strings.TrimSpace(req.Name), Color: req.Color})
}

func (s *Server) DeleteTag(c *gin.Context) {
	uid := currentUserID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	res, err := s.DB.Exec(`DELETE FROM tags WHERE id=? AND user_id=?`, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "标签不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

type ruleReq struct {
	AccountID  *int64                 `json:"account_id"`
	Name       string                 `json:"name" binding:"required"`
	Enabled    *bool                  `json:"enabled"`
	Priority   int                    `json:"priority"`
	MatchMode  string                 `json:"match_mode"`
	Conditions []models.RuleCondition `json:"conditions"`
	Actions    []models.RuleAction    `json:"actions"`
}

func (s *Server) ListRules(c *gin.Context) {
	uid := currentUserID(c)
	rows, err := s.DB.Query(`
		SELECT id, user_id, account_id, name, enabled, priority, match_mode, conditions_json, actions_json, created_at
		FROM rules WHERE user_id = ? ORDER BY priority ASC, id ASC`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.Rule, 0)
	for rows.Next() {
		var r models.Rule
		var enabledInt int
		var condJSON, actJSON string
		if err := rows.Scan(&r.ID, &r.UserID, &r.AccountID, &r.Name, &enabledInt, &r.Priority, &r.MatchMode, &condJSON, &actJSON, &r.CreatedAt); err == nil {
			r.Enabled = enabledInt == 1
			_ = json.Unmarshal([]byte(condJSON), &r.Conditions)
			_ = json.Unmarshal([]byte(actJSON), &r.Actions)
			items = append(items, r)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) CreateRule(c *gin.Context) {
	uid := currentUserID(c)
	var req ruleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "规则名称不能为空"})
		return
	}
	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	if req.Priority == 0 {
		req.Priority = 100
	}
	if req.MatchMode != "any" {
		req.MatchMode = "all"
	}
	condB, _ := json.Marshal(req.Conditions)
	actB, _ := json.Marshal(req.Actions)

	res, err := s.DB.Exec(`
		INSERT INTO rules (user_id, account_id, name, enabled, priority, match_mode, conditions_json, actions_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		uid, req.AccountID, strings.TrimSpace(req.Name), boolInt(enabled), req.Priority, req.MatchMode, string(condB), string(actB),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	id, _ := res.LastInsertId()
	r, _ := s.getRuleByID(uid, id)
	c.JSON(http.StatusCreated, r)
}

func (s *Server) UpdateRule(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效规则 ID"})
		return
	}
	existing, err := s.getRuleByID(uid, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "规则不存在"})
		return
	}

	var req ruleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	enabled := existing.Enabled
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	if req.Priority == 0 {
		req.Priority = existing.Priority
	}
	if req.MatchMode != "any" && req.MatchMode != "all" {
		req.MatchMode = existing.MatchMode
	}
	condB, _ := json.Marshal(req.Conditions)
	actB, _ := json.Marshal(req.Actions)

	_, err = s.DB.Exec(`
		UPDATE rules
		SET account_id=?, name=?, enabled=?, priority=?, match_mode=?, conditions_json=?, actions_json=?
		WHERE id=? AND user_id=?`,
		req.AccountID, strings.TrimSpace(req.Name), boolInt(enabled), req.Priority, req.MatchMode, string(condB), string(actB), id, uid,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	updated, _ := s.getRuleByID(uid, id)
	c.JSON(http.StatusOK, updated)
}

func (s *Server) DeleteRule(c *gin.Context) {
	uid := currentUserID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	res, err := s.DB.Exec(`DELETE FROM rules WHERE id=? AND user_id=?`, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "规则不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

func (s *Server) RunRule(c *gin.Context) {
	uid := currentUserID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	r, err := s.getRuleByID(uid, id)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "规则不存在"})
		return
	}
	matched, err := rules.RunRuleOnExisting(s.DB, r)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"matched": matched})
}

func (s *Server) getRuleByID(uid, id int64) (models.Rule, error) {
	var r models.Rule
	var enabledInt int
	var condJSON, actJSON string
	err := s.DB.QueryRow(`
		SELECT id, user_id, account_id, name, enabled, priority, match_mode, conditions_json, actions_json, created_at
		FROM rules WHERE id=? AND user_id=?`, id, uid,
	).Scan(&r.ID, &r.UserID, &r.AccountID, &r.Name, &enabledInt, &r.Priority, &r.MatchMode, &condJSON, &actJSON, &r.CreatedAt)
	if err != nil {
		return r, err
	}
	r.Enabled = enabledInt == 1
	_ = json.Unmarshal([]byte(condJSON), &r.Conditions)
	_ = json.Unmarshal([]byte(actJSON), &r.Actions)
	return r, nil
}

type signatureReq struct {
	AccountID   *int64 `json:"account_id"`
	Name        string `json:"name" binding:"required"`
	ContentHTML string `json:"content_html"`
	IsDefault   bool   `json:"is_default"`
}

func (s *Server) ListSignatures(c *gin.Context) {
	uid := currentUserID(c)
	rows, err := s.DB.Query(`
		SELECT id, user_id, account_id, name, content_html, is_default, created_at
		FROM signatures WHERE user_id=? ORDER BY is_default DESC, id ASC`, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.Signature, 0)
	for rows.Next() {
		var sig models.Signature
		var defInt int
		if err := rows.Scan(&sig.ID, &sig.UserID, &sig.AccountID, &sig.Name, &sig.ContentHTML, &defInt, &sig.CreatedAt); err == nil {
			sig.IsDefault = defInt == 1
			items = append(items, sig)
		}
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (s *Server) CreateSignature(c *gin.Context) {
	uid := currentUserID(c)
	var req signatureReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "签名名称不能为空"})
		return
	}
	if req.IsDefault {
		if req.AccountID != nil {
			_, _ = s.DB.Exec(`UPDATE signatures SET is_default=0 WHERE user_id=? AND account_id=?`, uid, *req.AccountID)
		} else {
			_, _ = s.DB.Exec(`UPDATE signatures SET is_default=0 WHERE user_id=? AND account_id IS NULL`, uid)
		}
	}

	res, err := s.DB.Exec(`
		INSERT INTO signatures (user_id, account_id, name, content_html, is_default)
		VALUES (?, ?, ?, ?, ?)`,
		uid, req.AccountID, strings.TrimSpace(req.Name), req.ContentHTML, boolInt(req.IsDefault),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	id, _ := res.LastInsertId()
	var sig models.Signature
	var defInt int
	_ = s.DB.QueryRow(`SELECT id, user_id, account_id, name, content_html, is_default, created_at FROM signatures WHERE id=?`, id).
		Scan(&sig.ID, &sig.UserID, &sig.AccountID, &sig.Name, &sig.ContentHTML, &defInt, &sig.CreatedAt)
	sig.IsDefault = defInt == 1
	c.JSON(http.StatusCreated, sig)
}

func (s *Server) UpdateSignature(c *gin.Context) {
	uid := currentUserID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	var req signatureReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "签名名称不能为空"})
		return
	}
	if req.IsDefault {
		if req.AccountID != nil {
			_, _ = s.DB.Exec(`UPDATE signatures SET is_default=0 WHERE user_id=? AND account_id=?`, uid, *req.AccountID)
		} else {
			_, _ = s.DB.Exec(`UPDATE signatures SET is_default=0 WHERE user_id=? AND account_id IS NULL`, uid)
		}
	}

	res, err := s.DB.Exec(`
		UPDATE signatures SET account_id=?, name=?, content_html=?, is_default=?
		WHERE id=? AND user_id=?`,
		req.AccountID, strings.TrimSpace(req.Name), req.ContentHTML, boolInt(req.IsDefault), id, uid,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "签名不存在"})
		return
	}
	var sig models.Signature
	var defInt int
	_ = s.DB.QueryRow(`SELECT id, user_id, account_id, name, content_html, is_default, created_at FROM signatures WHERE id=?`, id).
		Scan(&sig.ID, &sig.UserID, &sig.AccountID, &sig.Name, &sig.ContentHTML, &defInt, &sig.CreatedAt)
	sig.IsDefault = defInt == 1
	c.JSON(http.StatusOK, sig)
}

func (s *Server) DeleteSignature(c *gin.Context) {
	uid := currentUserID(c)
	id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
	res, err := s.DB.Exec(`DELETE FROM signatures WHERE id=? AND user_id=?`, id, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "签名不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}
