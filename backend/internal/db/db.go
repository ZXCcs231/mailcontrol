package db

import (
	"database/sql"
	"fmt"
	"path/filepath"

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

CREATE INDEX IF NOT EXISTS idx_accounts_user ON mail_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_folders_account ON folders(account_id, role);
CREATE INDEX IF NOT EXISTS idx_messages_user_recv ON messages(user_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_account_folder_uid ON messages(account_id, folder_id, remote_uid);
CREATE INDEX IF NOT EXISTS idx_attachments_msg ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_rules_user ON rules(user_id, enabled, priority);
`
	_, err := conn.Exec(schema)
	return err
}
