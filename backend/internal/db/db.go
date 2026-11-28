package db

import (
	"database/sql"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// Open 打开 SQLite 数据库并自动执行结构迁移。
func Open(dbPath string) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"file:%s?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(ON)",
		filepath.ToSlash(dbPath),
	)
	conn, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	// 单写连接池避免后台同步与 HTTP 并发写入出现 SQLITE_BUSY
	conn.SetMaxOpenConns(1)
	if err := conn.Ping(); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := Migrate(conn); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return conn, nil
}

// Migrate 初始化全部数据表与索引。
func Migrate(conn *sql.DB) error {
	schema := `
CREATE TABLE IF NOT EXISTS users (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	username TEXT NOT NULL UNIQUE,
	email TEXT NOT NULL UNIQUE,
	password_hash TEXT NOT NULL,
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mail_accounts (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	label TEXT NOT NULL,
	email_address TEXT NOT NULL,
	provider_id TEXT NOT NULL DEFAULT 'custom',
	imap_host TEXT NOT NULL,
	imap_port INTEGER NOT NULL DEFAULT 993,
	imap_tls TEXT NOT NULL DEFAULT 'ssl',
	smtp_host TEXT NOT NULL,
	smtp_port INTEGER NOT NULL DEFAULT 465,
	smtp_tls TEXT NOT NULL DEFAULT 'ssl',
	username TEXT NOT NULL,
	encrypted_password TEXT NOT NULL,
	color TEXT NOT NULL DEFAULT '#2563eb',
	is_default INTEGER NOT NULL DEFAULT 0,
	sync_enabled INTEGER NOT NULL DEFAULT 1,
	sync_interval_sec INTEGER NOT NULL DEFAULT 180,
	last_sync_at DATETIME,
	last_sync_status TEXT NOT NULL DEFAULT 'idle',
	last_sync_error TEXT NOT NULL DEFAULT '',
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS folders (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	account_id INTEGER NOT NULL,
	name TEXT NOT NULL,
	remote_name TEXT NOT NULL,
	role TEXT NOT NULL DEFAULT 'custom',
	unread_count INTEGER NOT NULL DEFAULT 0,
	total_count INTEGER NOT NULL DEFAULT 0,
	uid_validity INTEGER NOT NULL DEFAULT 0,
	last_uid INTEGER NOT NULL DEFAULT 0,
	UNIQUE(account_id, remote_name),
	FOREIGN KEY(account_id) REFERENCES mail_accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	account_id INTEGER NOT NULL,
	folder_id INTEGER NOT NULL,
	remote_uid INTEGER NOT NULL DEFAULT 0,
	message_id_header TEXT NOT NULL DEFAULT '',
	in_reply_to TEXT NOT NULL DEFAULT '',
	subject TEXT NOT NULL DEFAULT '',
	from_name TEXT NOT NULL DEFAULT '',
	from_addr TEXT NOT NULL DEFAULT '',
	to_addrs TEXT NOT NULL DEFAULT '',
	cc_addrs TEXT NOT NULL DEFAULT '',
	bcc_addrs TEXT NOT NULL DEFAULT '',
	snippet TEXT NOT NULL DEFAULT '',
	body_text TEXT NOT NULL DEFAULT '',
	body_html TEXT NOT NULL DEFAULT '',
	is_read INTEGER NOT NULL DEFAULT 0,
	is_starred INTEGER NOT NULL DEFAULT 0,
	is_draft INTEGER NOT NULL DEFAULT 0,
	has_attachments INTEGER NOT NULL DEFAULT 0,
	sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
	FOREIGN KEY(account_id) REFERENCES mail_accounts(id) ON DELETE CASCADE,
	FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attachments (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	message_id INTEGER NOT NULL,
	filename TEXT NOT NULL,
	content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
	size INTEGER NOT NULL DEFAULT 0,
	storage_path TEXT NOT NULL,
	content_id TEXT NOT NULL DEFAULT '',
	is_inline INTEGER NOT NULL DEFAULT 0,
	FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tags (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	name TEXT NOT NULL,
	color TEXT NOT NULL DEFAULT '#3b82f6',
	UNIQUE(user_id, name),
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS message_tags (
	message_id INTEGER NOT NULL,
	tag_id INTEGER NOT NULL,
	PRIMARY KEY(message_id, tag_id),
	FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE,
	FOREIGN KEY(tag_id) REFERENCES tags(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rules (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	account_id INTEGER,
	name TEXT NOT NULL,
	enabled INTEGER NOT NULL DEFAULT 1,
	priority INTEGER NOT NULL DEFAULT 100,
	match_mode TEXT NOT NULL DEFAULT 'all',
	conditions_json TEXT NOT NULL DEFAULT '[]',
	actions_json TEXT NOT NULL DEFAULT '[]',
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
	FOREIGN KEY(account_id) REFERENCES mail_accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS signatures (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	account_id INTEGER,
	name TEXT NOT NULL,
	content_html TEXT NOT NULL DEFAULT '',
	is_default INTEGER NOT NULL DEFAULT 0,
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
	FOREIGN KEY(account_id) REFERENCES mail_accounts(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS message_translations (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	message_id INTEGER NOT NULL,
	target_lang TEXT NOT NULL,
	provider TEXT NOT NULL DEFAULT '',
	translated_subject TEXT NOT NULL DEFAULT '',
	translated_text TEXT NOT NULL DEFAULT '',
	translated_html TEXT NOT NULL DEFAULT '',
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	UNIQUE(message_id, target_lang),
	FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS system_settings (
	key TEXT PRIMARY KEY,
	value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS push_channels (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	user_id INTEGER NOT NULL,
	name TEXT NOT NULL,
	channel_type TEXT NOT NULL DEFAULT 'feishu',
	enabled INTEGER NOT NULL DEFAULT 1,
	webhook_url TEXT NOT NULL DEFAULT '',
	encrypted_secret TEXT NOT NULL DEFAULT '',
	app_id TEXT NOT NULL DEFAULT '',
	target_id TEXT NOT NULL DEFAULT '',
	target_id_type TEXT NOT NULL DEFAULT 'open_id',
	created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO system_settings (key, value) VALUES ('allow_register', 'true');

CREATE INDEX IF NOT EXISTS idx_accounts_user ON mail_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_folders_account ON folders(account_id, role);
CREATE INDEX IF NOT EXISTS idx_messages_user_recv ON messages(user_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_account_folder_uid ON messages(account_id, folder_id, remote_uid);
CREATE INDEX IF NOT EXISTS idx_attachments_msg ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_rules_user ON rules(user_id, enabled, priority);
CREATE INDEX IF NOT EXISTS idx_push_channels_user ON push_channels(user_id, enabled);
`
	if _, err := conn.Exec(schema); err != nil {
		return err
	}

	// 平滑迁移已有数据库表列
	_, _ = conn.Exec(`ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0`)
	_, _ = conn.Exec(`ALTER TABLE users ADD COLUMN is_disabled INTEGER NOT NULL DEFAULT 0`)
	_, _ = conn.Exec(`ALTER TABLE message_translations ADD COLUMN translated_html TEXT NOT NULL DEFAULT ''`)
	_, _ = conn.Exec(`
		UPDATE users SET is_admin = 1
		WHERE id = (SELECT MIN(id) FROM users)
		  AND NOT EXISTS (SELECT 1 FROM users WHERE is_admin = 1)`)

	fixDirtyMessageTimestamps(conn)
	cleanupVirtualAggregateFolders(conn)
	return nil
}

var (
	monotonicSuffixRe   = regexp.MustCompile(`\s+m=[+-]\d+(?:\.\d+)?$`)
	repeatedOffsetTailRe = regexp.MustCompile(`(\s+[+-]\d{4})\s+[+-]\d{4}$`)
)

// ParseSQLiteTime 容错解析 SQLite 读取出的时间字段（兼容双数字时区偏移如 "-0800 -0800"）。
func ParseSQLiteTime(v any) time.Time {
	switch val := v.(type) {
	case nil:
		return time.Time{}
	case time.Time:
		return val.UTC()
	case []byte:
		return ParseSQLiteTime(string(val))
	case string:
		s := strings.TrimSpace(val)
		if s == "" {
			return time.Time{}
		}
		s = monotonicSuffixRe.ReplaceAllString(s, "")
		for _, layout := range []string{
			time.RFC3339Nano,
			time.RFC3339,
			"2006-01-02 15:04:05.999999999 -0700 MST",
			"2006-01-02 15:04:05 -0700 MST",
			"2006-01-02 15:04:05.999999999 -0700",
			"2006-01-02 15:04:05 -0700",
			"2006-01-02 15:04:05.999999999",
			"2006-01-02 15:04:05",
			"2006-01-02T15:04:05",
		} {
			if t, err := time.Parse(layout, s); err == nil {
				return t.UTC()
			}
		}
		// 去除诸如 "2026-11-24 10:49:07 -0800 -0800" 的重复数字偏移尾缀
		cleaned := repeatedOffsetTailRe.ReplaceAllString(s, "$1")
		if cleaned != s {
			for _, layout := range []string{
				"2006-01-02 15:04:05.999999999 -0700",
				"2006-01-02 15:04:05 -0700",
			} {
				if t, err := time.Parse(layout, cleaned); err == nil {
					return t.UTC()
				}
			}
		}
		return time.Time{}
	default:
		return time.Time{}
	}
}

func fixDirtyMessageTimestamps(conn *sql.DB) {
	rows, err := conn.Query(`
		SELECT id, sent_at, received_at
		FROM messages
		WHERE CAST(sent_at AS TEXT) LIKE '% -%'
		   OR CAST(sent_at AS TEXT) LIKE '% +%'
		   OR CAST(received_at AS TEXT) LIKE '% -%'
		   OR CAST(received_at AS TEXT) LIKE '% +%'`)
	if err != nil {
		return
	}
	type tsFix struct {
		id       int64
		sentAt   string
		recvAt   string
	}
	var fixes []tsFix
	for rows.Next() {
		var id int64
		var rawSent, rawRecv any
		if err := rows.Scan(&id, &rawSent, &rawRecv); err == nil {
			s := ParseSQLiteTime(rawSent)
			r := ParseSQLiteTime(rawRecv)
			if s.IsZero() {
				s = time.Now().UTC()
			}
			if r.IsZero() {
				r = s
			}
			fixes = append(fixes, tsFix{
				id:     id,
				sentAt: s.UTC().Format("2006-01-02 15:04:05"),
				recvAt: r.UTC().Format("2006-01-02 15:04:05"),
			})
		}
	}
	_ = rows.Close()

	for _, f := range fixes {
		_, _ = conn.Exec(`UPDATE messages SET sent_at = ?, received_at = ? WHERE id = ?`, f.sentAt, f.recvAt, f.id)
	}
}

func cleanupVirtualAggregateFolders(conn *sql.DB) {
	rows, err := conn.Query(`
		SELECT id, account_id
		FROM folders
		WHERE LOWER(TRIM(remote_name)) IN (
			'[gmail]/all mail', '[gmail]/所有邮件',
			'[gmail]/important', '[gmail]/重要',
			'[gmail]/starred', '[gmail]/已加星标'
		)`)
	if err != nil {
		return
	}
	type vFolder struct {
		id        int64
		accountID int64
	}
	var vFolders []vFolder
	for rows.Next() {
		var vf vFolder
		if rows.Scan(&vf.id, &vf.accountID) == nil {
			vFolders = append(vFolders, vf)
		}
	}
	_ = rows.Close()
	if len(vFolders) == 0 {
		return
	}

	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(vFolders)), ",")
	vIDArgs := make([]any, len(vFolders))
	for i, vf := range vFolders {
		vIDArgs[i] = vf.id
	}

	type vMsg struct {
		id          int64
		accountID   int64
		folderID    int64
		msgIDHeader string
		isRead      int
		isStarred   int
	}
	msgRows, err := conn.Query(
		`SELECT id, account_id, folder_id, message_id_header, is_read, is_starred FROM messages WHERE folder_id IN (`+placeholders+`)`,
		vIDArgs...,
	)
	if err != nil {
		return
	}
	var vMsgs []vMsg
	for msgRows.Next() {
		var vm vMsg
		if msgRows.Scan(&vm.id, &vm.accountID, &vm.folderID, &vm.msgIDHeader, &vm.isRead, &vm.isStarred) == nil {
			vMsgs = append(vMsgs, vm)
		}
	}
	_ = msgRows.Close()

	for _, vm := range vMsgs {
		var realID int64
		if vm.msgIDHeader != "" {
			queryArgs := append([]any{vm.accountID, vm.msgIDHeader}, vIDArgs...)
			_ = conn.QueryRow(
				`SELECT id FROM messages WHERE account_id = ? AND message_id_header = ? AND folder_id NOT IN (`+placeholders+`) ORDER BY id ASC LIMIT 1`,
				queryArgs...,
			).Scan(&realID)
		}

		if realID > 0 {
			if vm.isRead == 1 || vm.isStarred == 1 {
				_, _ = conn.Exec(`
					UPDATE messages
					SET is_read = CASE WHEN ? = 1 THEN 1 ELSE is_read END,
					    is_starred = CASE WHEN ? = 1 THEN 1 ELSE is_starred END
					WHERE id = ?`, vm.isRead, vm.isStarred, realID)
			}
			_, _ = conn.Exec(`INSERT OR IGNORE INTO message_tags (message_id, tag_id) SELECT ?, tag_id FROM message_tags WHERE message_id = ?`, realID, vm.id)
			_, _ = conn.Exec(`DELETE FROM messages WHERE id = ?`, vm.id)
		} else {
			// 将仅存在于“所有邮件”等聚合目录中的唯一邮件平滑归入归档文件夹，避免丢邮件
			var archiveID int64
			_ = conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? AND role = 'archive' ORDER BY id ASC LIMIT 1`, vm.accountID).Scan(&archiveID)
			if archiveID == 0 {
				_, _ = conn.Exec(`INSERT OR IGNORE INTO folders (account_id, name, remote_name, role) VALUES (?, '归档', 'Archive', 'archive')`, vm.accountID)
				_ = conn.QueryRow(`SELECT id FROM folders WHERE account_id = ? AND role = 'archive' ORDER BY id ASC LIMIT 1`, vm.accountID).Scan(&archiveID)
			}
			if archiveID > 0 {
				_, _ = conn.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, archiveID, vm.id)
			}
		}
	}

	_, _ = conn.Exec(`DELETE FROM folders WHERE id IN (`+placeholders+`)`, vIDArgs...)
	_, _ = conn.Exec(`
		UPDATE folders
		SET total_count = (SELECT COUNT(*) FROM messages WHERE folder_id = folders.id),
		    unread_count = (SELECT COUNT(*) FROM messages WHERE folder_id = folders.id AND is_read = 0)`)
}
