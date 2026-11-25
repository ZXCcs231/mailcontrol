package api

import (
	"database/sql"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/db"
	"mailcontrol-backend/internal/mailclient"
	"mailcontrol-backend/internal/models"
)

func (s *Server) ListMessages(c *gin.Context) {
	uid := currentUserID(c)
	view := strings.ToLower(c.DefaultQuery("view", "inbox"))
	accountIDStr := c.Query("account_id")
	folderIDStr := c.Query("folder_id")
	tagIDStr := c.Query("tag_id")
	unreadOnly := c.Query("unread_only") == "1" || c.Query("unread_only") == "true"
	hasAtt := c.Query("has_attachments") == "1" || c.Query("has_attachments") == "true"
	q := strings.TrimSpace(c.Query("q"))

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "30"))
	if pageSize < 1 || pageSize > 100 {
		pageSize = 30
	}
	offset := (page - 1) * pageSize

	where := []string{"m.user_id = ?"}
	args := []interface{}{uid}

	if accountIDStr != "" {
		where = append(where, "m.account_id = ?")
		args = append(args, accountIDStr)
	}
	if folderIDStr != "" {
		where = append(where, "m.folder_id = ?")
		args = append(args, folderIDStr)
	} else if tagIDStr != "" {
		where = append(where, "EXISTS (SELECT 1 FROM message_tags mt WHERE mt.message_id = m.id AND mt.tag_id = ?)")
		args = append(args, tagIDStr)
		where = append(where, "f.role NOT IN ('trash', 'spam')")
	} else {
		switch view {
		case "inbox":
			where = append(where, "f.role = 'inbox'")
		case "starred":
			where = append(where, "m.is_starred = 1 AND f.role NOT IN ('trash', 'spam')")
		case "sent":
			where = append(where, "f.role = 'sent'")
		case "drafts":
			where = append(where, "(m.is_draft = 1 OR f.role = 'drafts')")
		case "archive":
			where = append(where, "f.role = 'archive'")
		case "trash":
			where = append(where, "f.role = 'trash'")
		case "spam":
			where = append(where, "f.role = 'spam'")
		default:
			where = append(where, "f.role NOT IN ('trash', 'spam')")
		}
	}

	if unreadOnly {
		where = append(where, "m.is_read = 0")
	}
	if hasAtt {
		where = append(where, "m.has_attachments = 1")
	}
	if q != "" {
		like := "%" + q + "%"
		where = append(where, "(m.subject LIKE ? OR m.from_name LIKE ? OR m.from_addr LIKE ? OR m.to_addrs LIKE ? OR m.body_text LIKE ?)")
		args = append(args, like, like, like, like, like)
	}

	whereSQL := strings.Join(where, " AND ")

	var total int
	countSQL := `SELECT COUNT(*) FROM messages m JOIN mail_accounts a ON a.id = m.account_id JOIN folders f ON f.id = m.folder_id WHERE ` + whereSQL
	if err := s.DB.QueryRow(countSQL, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	listSQL := `
		SELECT m.id, m.user_id, m.account_id, a.label, a.email_address, a.color,
		       m.folder_id, f.role, f.name, m.remote_uid, m.message_id_header, m.in_reply_to,
		       m.subject, m.from_name, m.from_addr, m.to_addrs, m.cc_addrs, m.bcc_addrs,
		       m.snippet, m.is_read, m.is_starred, m.is_draft, m.has_attachments,
		       m.sent_at, m.received_at, m.created_at
		FROM messages m
		JOIN mail_accounts a ON a.id = m.account_id
		JOIN folders f ON f.id = m.folder_id
		WHERE ` + whereSQL + `
		ORDER BY m.received_at DESC, m.id DESC
		LIMIT ? OFFSET ?`

	queryArgs := append(append([]interface{}{}, args...), pageSize, offset)
	rows, err := s.DB.Query(listSQL, queryArgs...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer func() { _ = rows.Close() }()

	items := make([]models.Message, 0)
	for rows.Next() {
		var m models.Message
		var isRead, isStarred, isDraft, hasAtt int
		var rawSent, rawRecv, rawCreated any
		if err := rows.Scan(
			&m.ID, &m.UserID, &m.AccountID, &m.AccountLabel, &m.AccountEmail, &m.AccountColor,
			&m.FolderID, &m.FolderRole, &m.FolderName, &m.RemoteUID, &m.MessageIDHeader, &m.InReplyTo,
			&m.Subject, &m.FromName, &m.FromAddr, &m.ToAddrs, &m.CcAddrs, &m.BccAddrs,
			&m.Snippet, &isRead, &isStarred, &isDraft, &hasAtt,
			&rawSent, &rawRecv, &rawCreated,
		); err != nil {
			log.Printf("list messages scan error: %v", err)
			continue
		}
		m.IsRead = isRead == 1
		m.IsStarred = isStarred == 1
		m.IsDraft = isDraft == 1
		m.HasAttachments = hasAtt == 1
		m.SentAt = db.ParseSQLiteTime(rawSent)
		m.ReceivedAt = db.ParseSQLiteTime(rawRecv)
		m.CreatedAt = db.ParseSQLiteTime(rawCreated)
		items = append(items, m)
	}

	for i := range items {
		items[i].Tags = s.loadMessageTags(items[i].ID)
	}

	c.JSON(http.StatusOK, gin.H{
		"items":     items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (s *Server) GetMessage(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的邮件 ID"})
		return
	}

	var m models.Message
	var isRead, isStarred, isDraft, hasAtt int
	var rawSent, rawRecv, rawCreated any
	err = s.DB.QueryRow(`
		SELECT m.id, m.user_id, m.account_id, a.label, a.email_address, a.color,
		       m.folder_id, f.role, f.name, m.remote_uid, m.message_id_header, m.in_reply_to,
		       m.subject, m.from_name, m.from_addr, m.to_addrs, m.cc_addrs, m.bcc_addrs,
		       m.snippet, m.body_text, m.body_html, m.is_read, m.is_starred, m.is_draft, m.has_attachments,
		       m.sent_at, m.received_at, m.created_at
		FROM messages m
		JOIN mail_accounts a ON a.id = m.account_id
		JOIN folders f ON f.id = m.folder_id
		WHERE m.id = ? AND m.user_id = ?`, id, uid,
	).Scan(
		&m.ID, &m.UserID, &m.AccountID, &m.AccountLabel, &m.AccountEmail, &m.AccountColor,
		&m.FolderID, &m.FolderRole, &m.FolderName, &m.RemoteUID, &m.MessageIDHeader, &m.InReplyTo,
		&m.Subject, &m.FromName, &m.FromAddr, &m.ToAddrs, &m.CcAddrs, &m.BccAddrs,
		&m.Snippet, &m.BodyText, &m.BodyHTML, &isRead, &isStarred, &isDraft, &hasAtt,
		&rawSent, &rawRecv, &rawCreated,
	)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮件不存在"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	m.IsRead = isRead == 1
	m.IsStarred = isStarred == 1
	m.IsDraft = isDraft == 1
	m.HasAttachments = hasAtt == 1
	m.SentAt = db.ParseSQLiteTime(rawSent)
	m.ReceivedAt = db.ParseSQLiteTime(rawRecv)
	m.CreatedAt = db.ParseSQLiteTime(rawCreated)
	m.Tags = s.loadMessageTags(m.ID)
	m.Attachments = s.loadMessageAttachments(m.ID)

	c.JSON(http.StatusOK, m)
}

type patchMessageReq struct {
	IsRead      *bool   `json:"is_read"`
	IsStarred   *bool   `json:"is_starred"`
	MoveRole    *string `json:"move_role"`
	FolderID    *int64  `json:"folder_id"`
	AddTagID    *int64  `json:"add_tag_id"`
	RemoveTagID *int64  `json:"remove_tag_id"`
}

func (s *Server) PatchMessage(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的邮件 ID"})
		return
	}

	var accountID, folderID int64
	var remoteUID uint32
	var remoteFolder, msgIDHeader string
	err = s.DB.QueryRow(`
		SELECT m.account_id, m.folder_id, m.remote_uid, f.remote_name, m.message_id_header
		FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.id = ? AND m.user_id = ?`, id, uid,
	).Scan(&accountID, &folderID, &remoteUID, &remoteFolder, &msgIDHeader)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮件不存在"})
		return
	}

	var req patchMessageReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	affectedFolders := map[int64]struct{}{folderID: {}}
	collectSiblings := func() {
		if msgIDHeader == "" {
			return
		}
		fRows, err := s.DB.Query(`SELECT DISTINCT folder_id FROM messages WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
		if err != nil {
			return
		}
		defer func() { _ = fRows.Close() }()
		for fRows.Next() {
			var fid int64
			if fRows.Scan(&fid) == nil {
				affectedFolders[fid] = struct{}{}
			}
		}
	}

	if req.IsRead != nil {
		collectSiblings()
		if msgIDHeader != "" {
			_, _ = s.DB.Exec(`UPDATE messages SET is_read = ? WHERE account_id = ? AND message_id_header = ?`, boolInt(*req.IsRead), accountID, msgIDHeader)
		} else {
			_, _ = s.DB.Exec(`UPDATE messages SET is_read = ? WHERE id = ?`, boolInt(*req.IsRead), id)
		}
	}
	if req.IsStarred != nil {
		if msgIDHeader != "" {
			_, _ = s.DB.Exec(`UPDATE messages SET is_starred = ? WHERE account_id = ? AND message_id_header = ?`, boolInt(*req.IsStarred), accountID, msgIDHeader)
		} else {
			_, _ = s.DB.Exec(`UPDATE messages SET is_starred = ? WHERE id = ?`, boolInt(*req.IsStarred), id)
		}
	}
	if req.MoveRole != nil && *req.MoveRole != "" {
		targetID, err := mailclient.GetOrCreateFolderByRole(s.DB, accountID, strings.ToLower(*req.MoveRole))
		if err == nil && targetID > 0 && targetID != folderID {
			_, _ = s.DB.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, targetID, id)
			affectedFolders[targetID] = struct{}{}
		}
	} else if req.FolderID != nil && *req.FolderID > 0 {
		_, _ = s.DB.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, *req.FolderID, id)
		affectedFolders[*req.FolderID] = struct{}{}
	}
	for fid := range affectedFolders {
		_ = mailclient.RefreshFolderCounts(s.DB, fid)
	}
	if req.AddTagID != nil && *req.AddTagID > 0 {
		_, _ = s.DB.Exec(`INSERT OR IGNORE INTO message_tags (message_id, tag_id) VALUES (?, ?)`, id, *req.AddTagID)
	}
	if req.RemoveTagID != nil && *req.RemoveTagID > 0 {
		_, _ = s.DB.Exec(`DELETE FROM message_tags WHERE message_id = ? AND tag_id = ?`, id, *req.RemoveTagID)
	}

	if (req.IsRead != nil || req.IsStarred != nil) && remoteUID > 0 {
		go s.syncRemoteFlags(accountID, remoteFolder, remoteUID, req.IsRead, req.IsStarred)
	}

	c.JSON(http.StatusOK, gin.H{"updated": true})
}

func (s *Server) DeleteMessage(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的邮件 ID"})
		return
	}
	permanent := c.Query("permanent") == "1" || c.Query("permanent") == "true"

	var accountID, folderID int64
	var folderRole, remoteFolder string
	var remoteUID uint32
	err = s.DB.QueryRow(`
		SELECT m.account_id, m.folder_id, f.role, f.remote_name, m.remote_uid
		FROM messages m
		JOIN folders f ON f.id = m.folder_id
		WHERE m.id = ? AND m.user_id = ?`, id, uid,
	).Scan(&accountID, &folderID, &folderRole, &remoteFolder, &remoteUID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮件不存在"})
		return
	}

	if permanent || folderRole == "trash" {
		atts := s.loadMessageAttachments(id)
		_, _ = s.DB.Exec(`DELETE FROM messages WHERE id = ? AND user_id = ?`, id, uid)
		_ = mailclient.RefreshFolderCounts(s.DB, folderID)
		for _, a := range atts {
			_ = os.Remove(a.StoragePath)
		}
		if remoteUID > 0 {
			go s.deleteRemote(accountID, remoteFolder, remoteUID)
		}
		c.JSON(http.StatusOK, gin.H{"deleted": true, "permanent": true})
		return
	}

	trashID, err := mailclient.GetOrCreateFolderByRole(s.DB, accountID, "trash")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	_, _ = s.DB.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, trashID, id)
	_ = mailclient.RefreshFolderCounts(s.DB, folderID)
	_ = mailclient.RefreshFolderCounts(s.DB, trashID)
	c.JSON(http.StatusOK, gin.H{"deleted": true, "permanent": false})
}

type batchMessageReq struct {
	IDs    []int64 `json:"ids" binding:"required"`
	Action string  `json:"action" binding:"required"` // mark_read | mark_unread | star | unstar | archive | delete | add_tag
	TagID  int64   `json:"tag_id"`
}

func (s *Server) BatchMessages(c *gin.Context) {
	uid := currentUserID(c)
	var req batchMessageReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	affectedFolders := make(map[int64]struct{})
	for _, id := range req.IDs {
		var accountID, folderID int64
		var folderRole, msgIDHeader string
		err := s.DB.QueryRow(`
			SELECT m.account_id, m.folder_id, f.role, m.message_id_header
			FROM messages m JOIN folders f ON f.id = m.folder_id
			WHERE m.id = ? AND m.user_id = ?`, id, uid).Scan(&accountID, &folderID, &folderRole, &msgIDHeader)
		if err != nil {
			continue
		}
		affectedFolders[folderID] = struct{}{}

		collectBatchSiblings := func() {
			if msgIDHeader == "" {
				return
			}
			fRows, err := s.DB.Query(`SELECT DISTINCT folder_id FROM messages WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
			if err != nil {
				return
			}
			defer func() { _ = fRows.Close() }()
			for fRows.Next() {
				var fid int64
				if fRows.Scan(&fid) == nil {
					affectedFolders[fid] = struct{}{}
				}
			}
		}

		switch req.Action {
		case "mark_read":
			collectBatchSiblings()
			if msgIDHeader != "" {
				_, _ = s.DB.Exec(`UPDATE messages SET is_read = 1 WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
			} else {
				_, _ = s.DB.Exec(`UPDATE messages SET is_read = 1 WHERE id = ?`, id)
			}
		case "mark_unread":
			collectBatchSiblings()
			if msgIDHeader != "" {
				_, _ = s.DB.Exec(`UPDATE messages SET is_read = 0 WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
			} else {
				_, _ = s.DB.Exec(`UPDATE messages SET is_read = 0 WHERE id = ?`, id)
			}
		case "star":
			if msgIDHeader != "" {
				_, _ = s.DB.Exec(`UPDATE messages SET is_starred = 1 WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
			} else {
				_, _ = s.DB.Exec(`UPDATE messages SET is_starred = 1 WHERE id = ?`, id)
			}
		case "unstar":
			if msgIDHeader != "" {
				_, _ = s.DB.Exec(`UPDATE messages SET is_starred = 0 WHERE account_id = ? AND message_id_header = ?`, accountID, msgIDHeader)
			} else {
				_, _ = s.DB.Exec(`UPDATE messages SET is_starred = 0 WHERE id = ?`, id)
			}
		case "archive":
			if targetID, err := mailclient.GetOrCreateFolderByRole(s.DB, accountID, "archive"); err == nil {
				_, _ = s.DB.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, targetID, id)
				affectedFolders[targetID] = struct{}{}
			}
		case "delete":
			if folderRole == "trash" {
				_, _ = s.DB.Exec(`DELETE FROM messages WHERE id = ?`, id)
			} else if targetID, err := mailclient.GetOrCreateFolderByRole(s.DB, accountID, "trash"); err == nil {
				_, _ = s.DB.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, targetID, id)
				affectedFolders[targetID] = struct{}{}
			}
		case "add_tag":
			if req.TagID > 0 {
				_, _ = s.DB.Exec(`INSERT OR IGNORE INTO message_tags (message_id, tag_id) VALUES (?, ?)`, id, req.TagID)
			}
		}
	}

	for fid := range affectedFolders {
		_ = mailclient.RefreshFolderCounts(s.DB, fid)
	}
	c.JSON(http.StatusOK, gin.H{"processed": len(req.IDs)})
}

type sendJSONReq struct {
	AccountID  int64  `json:"account_id"`
	To         string `json:"to"`
	Cc         string `json:"cc"`
	Bcc        string `json:"bcc"`
	Subject    string `json:"subject"`
	BodyText   string `json:"body_text"`
	BodyHTML   string `json:"body_html"`
	InReplyTo  string `json:"in_reply_to"`
	References string `json:"references"`
	DraftID    int64  `json:"draft_id"`
}

func (s *Server) SendMessage(c *gin.Context) {
	uid := currentUserID(c)
	var req sendJSONReq
	var atts []mailclient.SendAttachment

	ct := c.GetHeader("Content-Type")
	if strings.Contains(strings.ToLower(ct), "multipart/form-data") {
		if err := c.Request.ParseMultipartForm(32 << 20); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "解析附件表单失败"})
			return
		}
		req.AccountID, _ = strconv.ParseInt(c.PostForm("account_id"), 10, 64)
		req.DraftID, _ = strconv.ParseInt(c.PostForm("draft_id"), 10, 64)
		req.To = c.PostForm("to")
		req.Cc = c.PostForm("cc")
		req.Bcc = c.PostForm("bcc")
		req.Subject = c.PostForm("subject")
		req.BodyText = c.PostForm("body_text")
		req.BodyHTML = c.PostForm("body_html")
		req.InReplyTo = c.PostForm("in_reply_to")
		req.References = c.PostForm("references")

		if form := c.Request.MultipartForm; form != nil {
			for _, fh := range form.File["attachments"] {
				f, err := fh.Open()
				if err != nil {
					continue
				}
				data, readErr := io.ReadAll(io.LimitReader(f, 25<<20))
				_ = f.Close()
				if readErr == nil {
					atts = append(atts, mailclient.SendAttachment{
						Filename:    fh.Filename,
						ContentType: fh.Header.Get("Content-Type"),
						Data:        data,
					})
				}
			}
		}
	} else {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "请求参数错误"})
			return
		}
	}

	toList := splitAddrs(req.To)
	if len(toList) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写至少一个收件人邮箱"})
		return
	}
	if req.AccountID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请选择发件邮箱账号"})
		return
	}

	var acct models.MailAccount
	var encPass string
	err := s.DB.QueryRow(`
		SELECT id, user_id, label, email_address, provider_id,
		       imap_host, imap_port, imap_tls, smtp_host, smtp_port, smtp_tls, username, encrypted_password
		FROM mail_accounts WHERE id = ? AND user_id = ?`, req.AccountID, uid,
	).Scan(
		&acct.ID, &acct.UserID, &acct.Label, &acct.EmailAddress, &acct.ProviderID,
		&acct.IMAPHost, &acct.IMAPPort, &acct.IMAPTLS,
		&acct.SMTPHost, &acct.SMTPPort, &acct.SMTPTLS, &acct.Username, &encPass,
	)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "发件邮箱账号不存在"})
		return
	}

	password, err := crypto.Decrypt(encPass, s.Cfg.EncKey)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "解密邮箱凭证失败"})
		return
	}

	ccList := splitAddrs(req.Cc)
	bccList := splitAddrs(req.Bcc)

	payload := mailclient.SendPayload{
		FromName:    acct.Label,
		FromAddr:    acct.EmailAddress,
		To:          toList,
		Cc:          ccList,
		Bcc:         bccList,
		Subject:     req.Subject,
		BodyText:    req.BodyText,
		BodyHTML:    req.BodyHTML,
		InReplyTo:   req.InReplyTo,
		References:  req.References,
		Attachments: atts,
	}

	msgIDHeader, err := mailclient.SendMail(mailclient.AccountConfig{
		ProviderID:   acct.ProviderID,
		EmailAddress: acct.EmailAddress,
		SMTPHost:     acct.SMTPHost,
		SMTPPort:     acct.SMTPPort,
		SMTPTLS:      acct.SMTPTLS,
		Username:     acct.Username,
		Password:     password,
	}, payload)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "发送失败: " + err.Error()})
		return
	}

	sentFolderID, _ := mailclient.GetOrCreateFolderByRole(s.DB, acct.ID, "sent")
	now := time.Now().UTC().Format("2006-01-02 15:04:05")
	snippet := req.BodyText
	if len([]rune(snippet)) > 140 {
		snippet = string([]rune(snippet)[:140]) + "..."
	}

	res, err := s.DB.Exec(`
		INSERT INTO messages (
			user_id, account_id, folder_id, remote_uid, message_id_header, in_reply_to,
			subject, from_name, from_addr, to_addrs, cc_addrs, bcc_addrs,
			snippet, body_text, body_html, is_read, is_starred, is_draft, has_attachments,
			sent_at, received_at
		) VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 0, ?, ?, ?)`,
		uid, acct.ID, sentFolderID, msgIDHeader, req.InReplyTo,
		req.Subject, acct.Label, acct.EmailAddress, strings.Join(toList, ", "), strings.Join(ccList, ", "), strings.Join(bccList, ", "),
		snippet, req.BodyText, req.BodyHTML, boolInt(len(atts) > 0), now, now,
	)
	if err == nil {
		savedID, _ := res.LastInsertId()
		if len(atts) > 0 {
			attDir := filepath.Join(s.Cfg.DataDir, "attachments", fmt.Sprintf("%d", acct.ID), fmt.Sprintf("%d", savedID))
			_ = os.MkdirAll(attDir, 0755)
			for idx, a := range atts {
				diskPath := filepath.Join(attDir, fmt.Sprintf("%d_%s", idx, filepath.Base(a.Filename)))
				if os.WriteFile(diskPath, a.Data, 0644) == nil {
					_, _ = s.DB.Exec(`
						INSERT INTO attachments (message_id, filename, content_type, size, storage_path, is_inline)
						VALUES (?, ?, ?, ?, ?, 0)`,
						savedID, a.Filename, a.ContentType, int64(len(a.Data)), diskPath,
					)
				}
			}
		}
	}
	_ = mailclient.RefreshFolderCounts(s.DB, sentFolderID)

	if req.DraftID > 0 {
		_, _ = s.DB.Exec(`DELETE FROM messages WHERE id = ? AND user_id = ? AND is_draft = 1`, req.DraftID, uid)
	}

	c.JSON(http.StatusOK, gin.H{"sent": true, "message_id": msgIDHeader})
}

func (s *Server) SaveDraft(c *gin.Context) {
	uid := currentUserID(c)
	var req sendJSONReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.AccountID == 0 {
		_ = s.DB.QueryRow(`SELECT id FROM mail_accounts WHERE user_id = ? ORDER BY is_default DESC, id ASC LIMIT 1`, uid).Scan(&req.AccountID)
	}
	if req.AccountID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请先绑定邮箱账号后再保存草稿"})
		return
	}

	var fromAddr, label string
	if err := s.DB.QueryRow(`SELECT email_address, label FROM mail_accounts WHERE id = ? AND user_id = ?`, req.AccountID, uid).Scan(&fromAddr, &label); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮箱账号不存在"})
		return
	}

	draftFolderID, err := mailclient.GetOrCreateFolderByRole(s.DB, req.AccountID, "drafts")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	now := time.Now().UTC().Format("2006-01-02 15:04:05")
	snippet := req.BodyText
	if len([]rune(snippet)) > 140 {
		snippet = string([]rune(snippet)[:140]) + "..."
	}

	draftIDParam := c.Param("id")
	if draftIDParam != "" {
		draftID, _ := strconv.ParseInt(draftIDParam, 10, 64)
		res, err := s.DB.Exec(`
			UPDATE messages
			SET account_id=?, folder_id=?, subject=?, to_addrs=?, cc_addrs=?, bcc_addrs=?,
			    snippet=?, body_text=?, body_html=?, received_at=?, sent_at=?
			WHERE id=? AND user_id=? AND is_draft=1`,
			req.AccountID, draftFolderID, req.Subject, req.To, req.Cc, req.Bcc,
			snippet, req.BodyText, req.BodyHTML, now, now, draftID, uid,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		if n, _ := res.RowsAffected(); n > 0 {
			_ = mailclient.RefreshFolderCounts(s.DB, draftFolderID)
			c.JSON(http.StatusOK, gin.H{"id": draftID, "saved": true})
			return
		}
	}

	res, err := s.DB.Exec(`
		INSERT INTO messages (
			user_id, account_id, folder_id, subject, from_name, from_addr,
			to_addrs, cc_addrs, bcc_addrs, snippet, body_text, body_html,
			is_read, is_starred, is_draft, has_attachments, sent_at, received_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, 1, 0, ?, ?)`,
		uid, req.AccountID, draftFolderID, req.Subject, label, fromAddr,
		req.To, req.Cc, req.Bcc, snippet, req.BodyText, req.BodyHTML, now, now,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	id, _ := res.LastInsertId()
	_ = mailclient.RefreshFolderCounts(s.DB, draftFolderID)
	c.JSON(http.StatusCreated, gin.H{"id": id, "saved": true})
}

func (s *Server) DownloadAttachment(c *gin.Context) {
	uid := currentUserID(c)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的附件 ID"})
		return
	}

	var filename, storagePath string
	err = s.DB.QueryRow(`
		SELECT a.filename, a.storage_path
		FROM attachments a
		JOIN messages m ON m.id = a.message_id
		WHERE a.id = ? AND m.user_id = ?`, id, uid,
	).Scan(&filename, &storagePath)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "附件不存在"})
		return
	}
	if _, err := os.Stat(storagePath); err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "附件文件已丢失"})
		return
	}
	c.FileAttachment(storagePath, filename)
}

func (s *Server) loadMessageTags(msgID int64) []models.Tag {
	rows, err := s.DB.Query(`
		SELECT t.id, t.user_id, t.name, t.color
		FROM tags t
		JOIN message_tags mt ON mt.tag_id = t.id
		WHERE mt.message_id = ?
		ORDER BY t.id ASC`, msgID)
	if err != nil {
		return nil
	}
	defer func() { _ = rows.Close() }()
	var tags []models.Tag
	for rows.Next() {
		var t models.Tag
		if err := rows.Scan(&t.ID, &t.UserID, &t.Name, &t.Color); err == nil {
			tags = append(tags, t)
		}
	}
	return tags
}

func (s *Server) loadMessageAttachments(msgID int64) []models.Attachment {
	rows, err := s.DB.Query(`
		SELECT id, message_id, filename, content_type, size, storage_path, content_id, is_inline
		FROM attachments WHERE message_id = ? ORDER BY id ASC`, msgID)
	if err != nil {
		return nil
	}
	defer func() { _ = rows.Close() }()
	var atts []models.Attachment
	for rows.Next() {
		var a models.Attachment
		var inlineInt int
		if err := rows.Scan(&a.ID, &a.MessageID, &a.Filename, &a.ContentType, &a.Size, &a.StoragePath, &a.ContentID, &inlineInt); err == nil {
			a.IsInline = inlineInt == 1
			atts = append(atts, a)
		}
	}
	return atts
}

func (s *Server) syncRemoteFlags(accountID int64, remoteFolder string, remoteUID uint32, isRead, isStarred *bool) {
	var acct models.MailAccount
	var encPass string
	err := s.DB.QueryRow(`
		SELECT id, email_address, provider_id, imap_host, imap_port, imap_tls, username, encrypted_password
		FROM mail_accounts WHERE id = ?`, accountID,
	).Scan(&acct.ID, &acct.EmailAddress, &acct.ProviderID, &acct.IMAPHost, &acct.IMAPPort, &acct.IMAPTLS, &acct.Username, &encPass)
	if err != nil {
		return
	}
	pass, err := crypto.Decrypt(encPass, s.Cfg.EncKey)
	if err != nil {
		return
	}
	_ = mailclient.UpdateRemoteFlags(acct, pass, remoteFolder, remoteUID, isRead, isStarred)
}

func (s *Server) deleteRemote(accountID int64, remoteFolder string, remoteUID uint32) {
	var acct models.MailAccount
	var encPass string
	err := s.DB.QueryRow(`
		SELECT id, email_address, provider_id, imap_host, imap_port, imap_tls, username, encrypted_password
		FROM mail_accounts WHERE id = ?`, accountID,
	).Scan(&acct.ID, &acct.EmailAddress, &acct.ProviderID, &acct.IMAPHost, &acct.IMAPPort, &acct.IMAPTLS, &acct.Username, &encPass)
	if err != nil {
		return
	}
	pass, err := crypto.Decrypt(encPass, s.Cfg.EncKey)
	if err != nil {
		return
	}
	_ = mailclient.DeleteRemoteMessage(acct, pass, remoteFolder, remoteUID)
}

func splitAddrs(raw string) []string {
	raw = strings.ReplaceAll(raw, ";", ",")
	parts := strings.Split(raw, ",")
	var out []string
	for _, p := range parts {
		trimmed := strings.TrimSpace(p)
		if trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
