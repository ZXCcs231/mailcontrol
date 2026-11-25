package models

import "time"

// User 表示 MailControl 系统账号，一个账号可绑定多个邮箱。
type User struct {
	ID           int64     `json:"id"`
	Username     string    `json:"username"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	IsAdmin      bool      `json:"is_admin"`
	IsDisabled   bool      `json:"is_disabled"`
	CreatedAt    time.Time `json:"created_at"`
}

// MailAccount 表示绑定的单个外部邮箱账号配置与同步状态。
type MailAccount struct {
	ID                int64      `json:"id"`
	UserID            int64      `json:"user_id"`
	Label             string     `json:"label"`
	EmailAddress      string     `json:"email_address"`
	ProviderID        string     `json:"provider_id"`
	IMAPHost          string     `json:"imap_host"`
	IMAPPort          int        `json:"imap_port"`
	IMAPTLS           string     `json:"imap_tls"` // ssl | starttls | none
	SMTPHost          string     `json:"smtp_host"`
	SMTPPort          int        `json:"smtp_port"`
	SMTPTLS           string     `json:"smtp_tls"` // ssl | starttls | none
	Username          string     `json:"username"`
	EncryptedPassword string     `json:"-"`
	Color             string     `json:"color"`
	IsDefault         bool       `json:"is_default"`
	SyncEnabled       bool       `json:"sync_enabled"`
	SyncIntervalSec   int        `json:"sync_interval_sec"`
	LastSyncAt        *time.Time `json:"last_sync_at"`
	LastSyncStatus    string     `json:"last_sync_status"` // idle | syncing | ok | error
	LastSyncError     string     `json:"last_sync_error"`
	UnreadCount       int        `json:"unread_count"`
	CreatedAt         time.Time  `json:"created_at"`
}

// Folder 表示邮箱内的文件夹（收件箱、已发送、草稿箱等）。
type Folder struct {
	ID          int64  `json:"id"`
	AccountID   int64  `json:"account_id"`
	Name        string `json:"name"`
	RemoteName  string `json:"remote_name"`
	Role        string `json:"role"` // inbox | sent | drafts | trash | spam | archive | custom
	UnreadCount int    `json:"unread_count"`
	TotalCount  int    `json:"total_count"`
	UIDValidity uint32 `json:"uid_validity"`
	LastUID     uint32 `json:"last_uid"`
}

// Attachment 表示邮件附件信息。
type Attachment struct {
	ID          int64  `json:"id"`
	MessageID   int64  `json:"message_id"`
	Filename    string `json:"filename"`
	ContentType string `json:"content_type"`
	Size        int64  `json:"size"`
	StoragePath string `json:"-"`
	ContentID   string `json:"content_id,omitempty"`
	IsInline    bool   `json:"is_inline"`
}

// Tag 表示用户自定义标签。
type Tag struct {
	ID     int64  `json:"id"`
	UserID int64  `json:"user_id"`
	Name   string `json:"name"`
	Color  string `json:"color"`
}

// Message 表示一封邮件记录。
type Message struct {
	ID              int64        `json:"id"`
	UserID          int64        `json:"user_id"`
	AccountID       int64        `json:"account_id"`
	AccountLabel    string       `json:"account_label,omitempty"`
	AccountEmail    string       `json:"account_email,omitempty"`
	AccountColor    string       `json:"account_color,omitempty"`
	FolderID        int64        `json:"folder_id"`
	FolderRole      string       `json:"folder_role,omitempty"`
	FolderName      string       `json:"folder_name,omitempty"`
	RemoteUID       uint32       `json:"remote_uid"`
	MessageIDHeader string       `json:"message_id_header"`
	InReplyTo       string       `json:"in_reply_to"`
	Subject         string       `json:"subject"`
	FromName        string       `json:"from_name"`
	FromAddr        string       `json:"from_addr"`
	ToAddrs         string       `json:"to_addrs"`
	CcAddrs         string       `json:"cc_addrs"`
	BccAddrs        string       `json:"bcc_addrs"`
	Snippet         string       `json:"snippet"`
	BodyText        string       `json:"body_text"`
	BodyHTML        string       `json:"body_html"`
	IsRead          bool         `json:"is_read"`
	IsStarred       bool         `json:"is_starred"`
	IsDraft         bool         `json:"is_draft"`
	HasAttachments  bool         `json:"has_attachments"`
	SentAt          time.Time    `json:"sent_at"`
	ReceivedAt      time.Time    `json:"received_at"`
	CreatedAt       time.Time    `json:"created_at"`
	Tags            []Tag        `json:"tags,omitempty"`
	Attachments     []Attachment `json:"attachments,omitempty"`
}

// RuleCondition 表示自动分类规则的一条匹配条件。
type RuleCondition struct {
	Field    string `json:"field"`    // from | to | subject | body
	Operator string `json:"operator"` // contains | not_contains | equals | starts_with | ends_with
	Value    string `json:"value"`
}

// RuleAction 表示命中规则后执行的动作。
type RuleAction struct {
	Type  string `json:"type"`            // mark_read | star | add_tag | move_folder | delete
	Value string `json:"value,omitempty"` // tag_id 或 folder_role (archive/trash/spam)
}

// Rule 表示用户配置的邮件自动处理规则。
type Rule struct {
	ID         int64           `json:"id"`
	UserID     int64           `json:"user_id"`
	AccountID  *int64          `json:"account_id"` // nil 表示对所有账号生效
	Name       string          `json:"name"`
	Enabled    bool            `json:"enabled"`
	Priority   int             `json:"priority"`
	MatchMode  string          `json:"match_mode"` // all | any
	Conditions []RuleCondition `json:"conditions"`
	Actions    []RuleAction    `json:"actions"`
	CreatedAt  time.Time       `json:"created_at"`
}

// Signature 表示发信签名模板。
type Signature struct {
	ID          int64     `json:"id"`
	UserID      int64     `json:"user_id"`
	AccountID   *int64    `json:"account_id"` // nil 表示通用签名
	Name        string    `json:"name"`
	ContentHTML string    `json:"content_html"`
	IsDefault   bool      `json:"is_default"`
	CreatedAt   time.Time `json:"created_at"`
}

// Stats 汇总统一视图、各账号及各标签未读数。
type Stats struct {
	InboxUnread   int           `json:"inbox_unread"`
	StarredCount  int           `json:"starred_count"`
	DraftsCount   int           `json:"drafts_count"`
	AccountCounts []AccountStat `json:"account_counts"`
	TagCounts     []TagStat     `json:"tag_counts"`
}

// AccountStat 表示单个邮箱账号的未读数统计。
type AccountStat struct {
	AccountID   int64 `json:"account_id"`
	UnreadCount int   `json:"unread_count"`
}

// TagStat 表示单个标签分类的未读邮件数统计。
type TagStat struct {
	TagID       int64 `json:"tag_id"`
	UnreadCount int   `json:"unread_count"`
}

// ProviderPreset 表示内置主流邮箱服务器配置预设。
type ProviderPreset struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Domains     []string `json:"domains"`
	IMAPHost    string   `json:"imap_host"`
	IMAPPort    int      `json:"imap_port"`
	IMAPTLS     string   `json:"imap_tls"`
	SMTPHost    string   `json:"smtp_host"`
	SMTPPort    int      `json:"smtp_port"`
	SMTPTLS     string   `json:"smtp_tls"`
	NeedsIMAPID bool     `json:"needs_imap_id"`
	AuthTip     string   `json:"auth_tip"`
}
