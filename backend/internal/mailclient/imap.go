package mailclient

import (
	"bytes"
	"crypto/tls"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/emersion/go-imap"
	imapid "github.com/emersion/go-imap-id"
	"github.com/emersion/go-imap/client"
	gomessage "github.com/emersion/go-message"
	"github.com/emersion/go-message/mail"
	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/encoding/ianaindex"
	"golang.org/x/text/encoding/simplifiedchinese"
	"golang.org/x/text/encoding/traditionalchinese"
	"golang.org/x/text/transform"

	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/providers"
)

func init() {
	gomessage.CharsetReader = charsetReader
}

func charsetReader(charset string, input io.Reader) (io.Reader, error) {
	cs := strings.ToLower(strings.TrimSpace(charset))
	switch cs {
	case "", "utf-8", "utf8", "us-ascii", "ascii":
		return input, nil
	case "gb2312", "gbk", "gb18030", "cp936", "x-gbk":
		return transform.NewReader(input, simplifiedchinese.GB18030.NewDecoder()), nil
	case "big5", "cp950":
		return transform.NewReader(input, traditionalchinese.Big5.NewDecoder()), nil
	case "iso-8859-1", "latin1":
		return transform.NewReader(input, charmap.ISO8859_1.NewDecoder()), nil
	case "windows-1252", "cp1252":
		return transform.NewReader(input, charmap.Windows1252.NewDecoder()), nil
	}
	if enc, err := ianaindex.MIME.Encoding(cs); err == nil && enc != nil && enc != encoding.Nop {
		return transform.NewReader(input, enc.NewDecoder()), nil
	}
	// 未知字符集时尽量透传，避免整封邮件解析失败
	return input, nil
}

// ConnectionTestResult 表示邮箱服务器连通性测试结果。
type ConnectionTestResult struct {
	Success  bool   `json:"success"`
	IMAPOK   bool   `json:"imap_ok"`
	SMTPOK   bool   `json:"smtp_ok"`
	IMAPMsg  string `json:"imap_msg"`
	SMTPMsg  string `json:"smtp_msg"`
	Message  string `json:"message"`
}

// AccountConfig 用于传入连接测试或发信的账号参数。
type AccountConfig struct {
	ProviderID   string
	EmailAddress string
	IMAPHost     string
	IMAPPort     int
	IMAPTLS      string
	SMTPHost     string
	SMTPPort     int
	SMTPTLS      string
	Username     string
	Password     string
}

func dialIMAP(cfg AccountConfig) (*client.Client, error) {
	addr := net.JoinHostPort(cfg.IMAPHost, fmt.Sprintf("%d", cfg.IMAPPort))
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	tlsCfg := &tls.Config{ServerName: cfg.IMAPHost}

	var c *client.Client
	var err error
	switch strings.ToLower(cfg.IMAPTLS) {
	case "ssl", "tls":
		c, err = client.DialWithDialerTLS(dialer, addr, tlsCfg)
	case "starttls":
		c, err = client.DialWithDialer(dialer, addr)
		if err == nil {
			if err = c.StartTLS(tlsCfg); err != nil {
				_ = c.Logout()
				return nil, err
			}
		}
	default:
		c, err = client.DialWithDialer(dialer, addr)
	}
	if err != nil {
		return nil, err
	}

	user := cfg.Username
	if user == "" {
		user = cfg.EmailAddress
	}
	if err := c.Login(user, cfg.Password); err != nil {
		_ = c.Logout()
		return nil, err
	}

	// 网易 163/126 等邮箱必须发送 IMAP ID，否则 SELECT INBOX 会被拒绝（Unsafe Login）
	preset := providers.GetByID(cfg.ProviderID)
	if preset.NeedsIMAPID || strings.Contains(strings.ToLower(cfg.IMAPHost), "163.com") || strings.Contains(strings.ToLower(cfg.IMAPHost), "126.com") {
		idClient := imapid.NewClient(c)
		_, _ = idClient.ID(imapid.ID{
			imapid.FieldName:    "MailControl",
			imapid.FieldVersion: "1.0.0",
			imapid.FieldVendor:  "MailControl",
		})
	}
	return c, nil
}

// TestConnection 依次测试 IMAP 和 SMTP 登录连通性并返回中文诊断详情。
func TestConnection(cfg AccountConfig) ConnectionTestResult {
	res := ConnectionTestResult{}

	c, err := dialIMAP(cfg)
	if err != nil {
		res.IMAPMsg = fmt.Sprintf("IMAP 连接或登录失败: %v（请检查服务器地址、端口及是否使用授权码）", err)
	} else {
		// 尝试读取 INBOX 验证权限（可捕获网易 Unsafe Login）
		if _, selErr := c.Select("INBOX", true); selErr != nil {
			res.IMAPMsg = fmt.Sprintf("IMAP 登录成功但读取收件箱失败: %v", selErr)
		} else {
			res.IMAPOK = true
			res.IMAPMsg = "IMAP 连接与收件箱读取正常"
		}
		_ = c.Logout()
	}

	if err := TestSMTP(cfg); err != nil {
		res.SMTPMsg = fmt.Sprintf("SMTP 连接或认证失败: %v", err)
	} else {
		res.SMTPOK = true
		res.SMTPMsg = "SMTP 发信认证正常"
	}

	res.Success = res.IMAPOK && res.SMTPOK
	if res.Success {
		res.Message = "IMAP 与 SMTP 均测试通过，可以正常收发邮件！"
	} else if res.IMAPOK {
		res.Message = "IMAP 正常，但 SMTP 失败：" + res.SMTPMsg
	} else if res.SMTPOK {
		res.Message = "SMTP 正常，但 IMAP 失败：" + res.IMAPMsg
	} else {
		res.Message = res.IMAPMsg + "；" + res.SMTPMsg
	}
	return res
}

type parsedAttachment struct {
	Filename    string
	ContentType string
	ContentID   string
	IsInline    bool
	Data        []byte
}

// SyncAccount 对指定邮箱执行文件夹发现与按 UID 增量同步，返回新同步入库的邮件列表。
func SyncAccount(conn *sql.DB, acct models.MailAccount, password, dataDir string) ([]models.Message, error) {
	cfg := AccountConfig{
		ProviderID:   acct.ProviderID,
		EmailAddress: acct.EmailAddress,
		IMAPHost:     acct.IMAPHost,
		IMAPPort:     acct.IMAPPort,
		IMAPTLS:      acct.IMAPTLS,
		SMTPHost:     acct.SMTPHost,
		SMTPPort:     acct.SMTPPort,
		SMTPTLS:      acct.SMTPTLS,
		Username:     acct.Username,
		Password:     password,
	}

	c, err := dialIMAP(cfg)
	if err != nil {
		return nil, err
	}
	defer func() { _ = c.Logout() }()

	mailboxesCh := make(chan *imap.MailboxInfo, 32)
	done := make(chan error, 1)
	go func() {
		done <- c.List("", "*", mailboxesCh)
	}()

	var remoteFolders []*imap.MailboxInfo
	for m := range mailboxesCh {
		if m != nil && !hasAttr(m.Attributes, imap.NoSelectAttr) {
			remoteFolders = append(remoteFolders, m)
		}
	}
	if err := <-done; err != nil {
		return nil, fmt.Errorf("获取文件夹列表失败: %w", err)
	}

	var newMessages []models.Message
	for _, rf := range remoteFolders {
		role, displayName := classifyFolder(rf.Name, rf.Attributes)
		folder, err := upsertFolder(conn, acct.ID, displayName, rf.Name, role)
		if err != nil {
			continue
		}

		// 只同步标准文件夹与自定义收件文件夹，跳过垃圾与废纸篓的首次大批量拉取（仅同步标准角色）
		msgs, err := syncFolder(conn, c, acct, folder, dataDir)
		if err != nil {
			// 单个文件夹同步失败不中断其他文件夹
			continue
		}
		newMessages = append(newMessages, msgs...)
		_ = RefreshFolderCounts(conn, folder.ID)
	}

	return newMessages, nil
}

func syncFolder(conn *sql.DB, c *client.Client, acct models.MailAccount, folder models.Folder, dataDir string) ([]models.Message, error) {
	mbox, err := c.Select(folder.RemoteName, true)
	if err != nil {
		return nil, err
	}
	if mbox.Messages == 0 {
		return nil, nil
	}

	lastUID := folder.LastUID
	if folder.UIDValidity != 0 && mbox.UidValidity != folder.UIDValidity {
		lastUID = 0
	}

	seqSet := new(imap.SeqSet)
	useUIDFetch := false

	if lastUID == 0 {
		// 首次同步最多拉取最近 50 封，保证首屏速度
		const maxInitial = uint32(50)
		start := uint32(1)
		if mbox.Messages > maxInitial {
			start = mbox.Messages - maxInitial + 1
		}
		seqSet.AddRange(start, mbox.Messages)
	} else {
		if mbox.UidNext > 0 && lastUID+1 >= mbox.UidNext {
			// 没有新邮件
			return nil, nil
		}
		seqSet.AddRange(lastUID+1, 0)
		useUIDFetch = true
	}

	section := &imap.BodySectionName{Peek: true}
	items := []imap.FetchItem{
		imap.FetchEnvelope,
		imap.FetchFlags,
		imap.FetchUid,
		imap.FetchInternalDate,
		section.FetchItem(),
	}

	msgCh := make(chan *imap.Message, 20)
	errCh := make(chan error, 1)
	go func() {
		if useUIDFetch {
			errCh <- c.UidFetch(seqSet, items, msgCh)
		} else {
			errCh <- c.Fetch(seqSet, items, msgCh)
		}
	}()

	var added []models.Message
	maxUID := lastUID

	for imsg := range msgCh {
		if imsg == nil || imsg.Uid == 0 {
			continue
		}
		if imsg.Uid <= lastUID {
			continue
		}
		if imsg.Uid > maxUID {
			maxUID = imsg.Uid
		}

		// 检查是否已存在
		var existingID int64
		err := conn.QueryRow(
			`SELECT id FROM messages WHERE account_id = ? AND folder_id = ? AND remote_uid = ?`,
			acct.ID, folder.ID, imsg.Uid,
		).Scan(&existingID)
		if err == nil && existingID > 0 {
			continue
		}

		bodyReader := imsg.GetBody(section)
		saved, err := parseAndStoreMessage(conn, acct, folder, imsg, bodyReader, dataDir)
		if err == nil {
			added = append(added, saved)
		}
	}

	if err := <-errCh; err != nil {
		return added, err
	}

	if maxUID > lastUID || folder.UIDValidity != mbox.UidValidity {
		_, _ = conn.Exec(
			`UPDATE folders SET uid_validity = ?, last_uid = ? WHERE id = ?`,
			mbox.UidValidity, maxUID, folder.ID,
		)
	}
	return added, nil
}

func parseAndStoreMessage(
	conn *sql.DB,
	acct models.MailAccount,
	folder models.Folder,
	imsg *imap.Message,
	bodyReader io.Reader,
	dataDir string,
) (models.Message, error) {
	var msg models.Message
	msg.UserID = acct.UserID
	msg.AccountID = acct.ID
	msg.FolderID = folder.ID
	msg.FolderRole = folder.Role
	msg.FolderName = folder.Name
	msg.RemoteUID = imsg.Uid

	for _, f := range imsg.Flags {
		switch f {
		case imap.SeenFlag:
			msg.IsRead = true
		case imap.FlaggedFlag:
			msg.IsStarred = true
		case imap.DraftFlag:
			msg.IsDraft = true
		}
	}
	if folder.Role == "drafts" {
		msg.IsDraft = true
	}

	if imsg.Envelope != nil {
		msg.Subject = strings.TrimSpace(imsg.Envelope.Subject)
		msg.MessageIDHeader = imsg.Envelope.MessageId
		msg.InReplyTo = imsg.Envelope.InReplyTo
		if len(imsg.Envelope.From) > 0 {
			msg.FromName = imsg.Envelope.From[0].PersonalName
			msg.FromAddr = imsg.Envelope.From[0].Address()
		}
		msg.ToAddrs = formatAddresses(imsg.Envelope.To)
		msg.CcAddrs = formatAddresses(imsg.Envelope.Cc)
		msg.BccAddrs = formatAddresses(imsg.Envelope.Bcc)
		if !imsg.Envelope.Date.IsZero() {
			msg.SentAt = imsg.Envelope.Date
		}
	}
	if msg.SentAt.IsZero() {
		if !imsg.InternalDate.IsZero() {
			msg.SentAt = imsg.InternalDate
		} else {
			msg.SentAt = time.Now()
		}
	}
	if !imsg.InternalDate.IsZero() {
		msg.ReceivedAt = imsg.InternalDate
	} else {
		msg.ReceivedAt = msg.SentAt
	}
	if msg.Subject == "" {
		msg.Subject = "（无主题）"
	}

	var atts []parsedAttachment
	if bodyReader != nil {
		rawBytes, _ := io.ReadAll(io.LimitReader(bodyReader, 30<<20))
		if mr, err := mail.CreateReader(bytes.NewReader(rawBytes)); err == nil {
			for {
				p, err := mr.NextPart()
				if err == io.EOF {
					break
				}
				if err != nil {
					break
				}
				switch h := p.Header.(type) {
				case *mail.InlineHeader:
					ct, _, _ := h.ContentType()
					b, readErr := io.ReadAll(io.LimitReader(p.Body, 10<<20))
					if readErr != nil {
						continue
					}
					switch strings.ToLower(ct) {
					case "text/plain":
						if msg.BodyText == "" {
							msg.BodyText = string(b)
						} else {
							msg.BodyText += "\n" + string(b)
						}
					case "text/html":
						if msg.BodyHTML == "" {
							msg.BodyHTML = string(b)
						} else {
							msg.BodyHTML += "\n" + string(b)
						}
					default:
						// 内联图片等资源
						disp, params, _ := h.ContentDisposition()
						cid := strings.Trim(h.Get("Content-Id"), "<>")
						fname := params["filename"]
						if fname == "" && cid != "" {
							fname = cid
						}
						if disp != "" || cid != "" {
							atts = append(atts, parsedAttachment{
								Filename:    sanitizeFilename(fname, "inline.bin"),
								ContentType: ct,
								ContentID:   cid,
								IsInline:    true,
								Data:        b,
							})
						}
					}
				case *mail.AttachmentHeader:
					fname, _ := h.Filename()
					ct, _, _ := h.ContentType()
					b, readErr := io.ReadAll(io.LimitReader(p.Body, 25<<20))
					if readErr != nil {
						continue
					}
					atts = append(atts, parsedAttachment{
						Filename:    sanitizeFilename(fname, "attachment.bin"),
						ContentType: ct,
						IsInline:    false,
						Data:        b,
					})
				}
			}
		} else {
			msg.BodyText = string(rawBytes)
		}
	}

	if msg.BodyText == "" && msg.BodyHTML != "" {
		msg.BodyText = stripHTMLTags(msg.BodyHTML)
	}
	msg.Snippet = makeSnippet(msg.BodyText, msg.BodyHTML)
	for _, a := range atts {
		if !a.IsInline {
			msg.HasAttachments = true
			break
		}
	}

	res, err := conn.Exec(`
		INSERT INTO messages (
			user_id, account_id, folder_id, remote_uid, message_id_header, in_reply_to,
			subject, from_name, from_addr, to_addrs, cc_addrs, bcc_addrs,
			snippet, body_text, body_html, is_read, is_starred, is_draft, has_attachments,
			sent_at, received_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		msg.UserID, msg.AccountID, msg.FolderID, msg.RemoteUID, msg.MessageIDHeader, msg.InReplyTo,
		msg.Subject, msg.FromName, msg.FromAddr, msg.ToAddrs, msg.CcAddrs, msg.BccAddrs,
		msg.Snippet, msg.BodyText, msg.BodyHTML, boolToInt(msg.IsRead), boolToInt(msg.IsStarred),
		boolToInt(msg.IsDraft), boolToInt(msg.HasAttachments), msg.SentAt, msg.ReceivedAt,
	)
	if err != nil {
		return msg, err
	}
	msgID, err := res.LastInsertId()
	if err != nil {
		return msg, err
	}
	msg.ID = msgID

	if len(atts) > 0 {
		attDir := filepath.Join(dataDir, "attachments", fmt.Sprintf("%d", acct.ID), fmt.Sprintf("%d", msgID))
		if err := os.MkdirAll(attDir, 0755); err == nil {
			for idx, a := range atts {
				diskName := fmt.Sprintf("%d_%s", idx, a.Filename)
				diskPath := filepath.Join(attDir, diskName)
				if err := os.WriteFile(diskPath, a.Data, 0644); err != nil {
					continue
				}
				attRes, err := conn.Exec(`
					INSERT INTO attachments (message_id, filename, content_type, size, storage_path, content_id, is_inline)
					VALUES (?, ?, ?, ?, ?, ?, ?)`,
					msgID, a.Filename, a.ContentType, int64(len(a.Data)), diskPath, a.ContentID, boolToInt(a.IsInline),
				)
				if err == nil {
					attID, _ := attRes.LastInsertId()
					msg.Attachments = append(msg.Attachments, models.Attachment{
						ID:          attID,
						MessageID:   msgID,
						Filename:    a.Filename,
						ContentType: a.ContentType,
						Size:        int64(len(a.Data)),
						StoragePath: diskPath,
						ContentID:   a.ContentID,
						IsInline:    a.IsInline,
					})
				}
			}
		}
	}

	return msg, nil
}

// UpdateRemoteFlags 将已读/星标状态尽力同步到远端 IMAP 服务器。
func UpdateRemoteFlags(acct models.MailAccount, password, remoteFolder string, remoteUID uint32, isRead, isStarred *bool) error {
	if remoteUID == 0 || remoteFolder == "" {
		return nil
	}
	c, err := dialIMAP(AccountConfig{
		ProviderID:   acct.ProviderID,
		EmailAddress: acct.EmailAddress,
		IMAPHost:     acct.IMAPHost,
		IMAPPort:     acct.IMAPPort,
		IMAPTLS:      acct.IMAPTLS,
		Username:     acct.Username,
		Password:     password,
	})
	if err != nil {
		return err
	}
	defer func() { _ = c.Logout() }()

	if _, err := c.Select(remoteFolder, false); err != nil {
		return err
	}
	seq := new(imap.SeqSet)
	seq.AddNum(remoteUID)

	if isRead != nil {
		item := imap.FormatFlagsOp(imap.AddFlags, true)
		if !*isRead {
			item = imap.FormatFlagsOp(imap.RemoveFlags, true)
		}
		if err := c.UidStore(seq, item, []interface{}{imap.SeenFlag}, nil); err != nil {
			return err
		}
	}
	if isStarred != nil {
		item := imap.FormatFlagsOp(imap.AddFlags, true)
		if !*isStarred {
			item = imap.FormatFlagsOp(imap.RemoveFlags, true)
		}
		if err := c.UidStore(seq, item, []interface{}{imap.FlaggedFlag}, nil); err != nil {
			return err
		}
	}
	return nil
}

// DeleteRemoteMessage 从远端 IMAP 文件夹删除指定 UID 邮件。
func DeleteRemoteMessage(acct models.MailAccount, password, remoteFolder string, remoteUID uint32) error {
	if remoteUID == 0 || remoteFolder == "" {
		return nil
	}
	c, err := dialIMAP(AccountConfig{
		ProviderID:   acct.ProviderID,
		EmailAddress: acct.EmailAddress,
		IMAPHost:     acct.IMAPHost,
		IMAPPort:     acct.IMAPPort,
		IMAPTLS:      acct.IMAPTLS,
		Username:     acct.Username,
		Password:     password,
	})
	if err != nil {
		return err
	}
	defer func() { _ = c.Logout() }()

	if _, err := c.Select(remoteFolder, false); err != nil {
		return err
	}
	seq := new(imap.SeqSet)
	seq.AddNum(remoteUID)
	if err := c.UidStore(seq, imap.FormatFlagsOp(imap.AddFlags, true), []interface{}{imap.DeletedFlag}, nil); err != nil {
		return err
	}
	return c.Expunge(nil)
}

// EnsureStandardFolders 为新绑定账号初始化本地基础文件夹，避免未同步前无法保存草稿/已发送。
func EnsureStandardFolders(conn *sql.DB, accountID int64) error {
	defaults := []struct {
		name, remote, role string
	}{
		{"收件箱", "INBOX", "inbox"},
		{"已发送", "Sent", "sent"},
		{"草稿箱", "Drafts", "drafts"},
		{"归档", "Archive", "archive"},
		{"回收站", "Trash", "trash"},
		{"垃圾邮件", "Junk", "spam"},
	}
	for _, d := range defaults {
		_, err := conn.Exec(`
			INSERT OR IGNORE INTO folders (account_id, name, remote_name, role)
			VALUES (?, ?, ?, ?)`,
			accountID, d.name, d.remote, d.role,
		)
		if err != nil {
			return err
		}
	}
	return nil
}

// GetOrCreateFolderByRole 查找或创建指定角色的文件夹。
func GetOrCreateFolderByRole(conn *sql.DB, accountID int64, role string) (int64, error) {
	var id int64
	err := conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? AND role = ? ORDER BY id ASC LIMIT 1`, accountID, role).Scan(&id)
	if err == nil && id > 0 {
		return id, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return 0, err
	}
	if err := EnsureStandardFolders(conn, accountID); err != nil {
		return 0, err
	}
	err = conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? AND role = ? ORDER BY id ASC LIMIT 1`, accountID, role).Scan(&id)
	return id, err
}

// RefreshFolderCounts 重算本地文件夹未读数与总邮件数。
func RefreshFolderCounts(conn *sql.DB, folderID int64) error {
	_, err := conn.Exec(`
		UPDATE folders
		SET total_count = (SELECT COUNT(*) FROM messages WHERE folder_id = folders.id),
		    unread_count = (SELECT COUNT(*) FROM messages WHERE folder_id = folders.id AND is_read = 0)
		WHERE id = ?`, folderID)
	return err
}

func upsertFolder(conn *sql.DB, accountID int64, name, remoteName, role string) (models.Folder, error) {
	// 如果已存在相同 role 的预设占位且 remote_name 尚未匹配，优先按 remote_name 精确查找
	var f models.Folder
	err := conn.QueryRow(`
		SELECT id, account_id, name, remote_name, role, unread_count, total_count, uid_validity, last_uid
		FROM folders WHERE account_id = ? AND remote_name = ?`,
		accountID, remoteName,
	).Scan(&f.ID, &f.AccountID, &f.Name, &f.RemoteName, &f.Role, &f.UnreadCount, &f.TotalCount, &f.UIDValidity, &f.LastUID)
	if err == nil {
		return f, nil
	}

	_, err = conn.Exec(`
		INSERT INTO folders (account_id, name, remote_name, role)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(account_id, remote_name) DO UPDATE SET name = excluded.name, role = excluded.role`,
		accountID, name, remoteName, role,
	)
	if err != nil {
		return f, err
	}
	err = conn.QueryRow(`
		SELECT id, account_id, name, remote_name, role, unread_count, total_count, uid_validity, last_uid
		FROM folders WHERE account_id = ? AND remote_name = ?`,
		accountID, remoteName,
	).Scan(&f.ID, &f.AccountID, &f.Name, &f.RemoteName, &f.Role, &f.UnreadCount, &f.TotalCount, &f.UIDValidity, &f.LastUID)
	return f, err
}

func hasAttr(attrs []string, target string) bool {
	for _, a := range attrs {
		if strings.EqualFold(a, target) {
			return true
		}
	}
	return false
}

func classifyFolder(remoteName string, attrs []string) (role, display string) {
	upper := strings.ToUpper(remoteName)
	if upper == "INBOX" {
		return "inbox", "收件箱"
	}
	if hasAttr(attrs, imap.SentAttr) {
		return "sent", "已发送"
	}
	if hasAttr(attrs, imap.DraftsAttr) {
		return "drafts", "草稿箱"
	}
	if hasAttr(attrs, imap.TrashAttr) {
		return "trash", "回收站"
	}
	if hasAttr(attrs, imap.JunkAttr) {
		return "spam", "垃圾邮件"
	}
	if hasAttr(attrs, imap.ArchiveAttr) {
		return "archive", "归档"
	}

	lower := strings.ToLower(remoteName)
	switch {
	case strings.Contains(lower, "sent") || strings.Contains(remoteName, "已发送") || strings.Contains(remoteName, "发件箱"):
		return "sent", "已发送"
	case strings.Contains(lower, "draft") || strings.Contains(remoteName, "草稿"):
		return "drafts", "草稿箱"
	case strings.Contains(lower, "trash") || strings.Contains(lower, "deleted") || strings.Contains(remoteName, "已删除") || strings.Contains(remoteName, "废纸篓"):
		return "trash", "回收站"
	case strings.Contains(lower, "junk") || strings.Contains(lower, "spam") || strings.Contains(remoteName, "垃圾"):
		return "spam", "垃圾邮件"
	case strings.Contains(lower, "archive") || strings.Contains(remoteName, "归档"):
		return "archive", "归档"
	default:
		// 截取最后层级显示
		parts := strings.Split(remoteName, "/")
		return "custom", parts[len(parts)-1]
	}
}

func formatAddresses(addrs []*imap.Address) string {
	var list []string
	for _, a := range addrs {
		if a == nil {
			continue
		}
		email := a.Address()
		if a.PersonalName != "" {
			list = append(list, fmt.Sprintf("%s <%s>", a.PersonalName, email))
		} else if email != "" {
			list = append(list, email)
		}
	}
	return strings.Join(list, ", ")
}

var htmlTagRe = regexp.MustCompile(`(?s)<style.*?>.*?</style>|<script.*?>.*?</script>|<[^>]+>`)
var spaceRe = regexp.MustCompile(`\s+`)

func stripHTMLTags(htmlStr string) string {
	cleaned := htmlTagRe.ReplaceAllString(htmlStr, " ")
	cleaned = strings.NewReplacer("&nbsp;", " ", "&lt;", "<", "&gt;", ">", "&amp;", "&", "&quot;", `"`).Replace(cleaned)
	return strings.TrimSpace(spaceRe.ReplaceAllString(cleaned, " "))
}

func makeSnippet(text, htmlStr string) string {
	src := strings.TrimSpace(text)
	if src == "" {
		src = stripHTMLTags(htmlStr)
	} else {
		src = strings.TrimSpace(spaceRe.ReplaceAllString(src, " "))
	}
	runes := []rune(src)
	if len(runes) > 140 {
		return string(runes[:140]) + "..."
	}
	return src
}

func sanitizeFilename(name, fallback string) string {
	name = strings.TrimSpace(filepath.Base(name))
	if name == "" || name == "." || name == "/" || name == `\` {
		return fallback
	}
	replacer := strings.NewReplacer("<", "_", ">", "_", ":", "_", `"`, "_", "/", "_", `\`, "_", "|", "_", "?", "_", "*", "_")
	return replacer.Replace(name)
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
