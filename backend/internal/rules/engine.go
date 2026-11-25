package rules

import (
	"database/sql"
	"encoding/json"
	"strconv"
	"strings"

	"mailcontrol-backend/internal/mailclient"
	"mailcontrol-backend/internal/models"
)

// Matches 判断单封邮件是否满足指定规则的所有/任一条件。
func Matches(rule models.Rule, msg models.Message) bool {
	if rule.AccountID != nil && *rule.AccountID != msg.AccountID {
		return false
	}
	if len(rule.Conditions) == 0 {
		return false
	}

	matchAll := strings.ToLower(rule.MatchMode) != "any"
	for _, cond := range rule.Conditions {
		hit := evalCondition(cond, msg)
		if matchAll && !hit {
			return false
		}
		if !matchAll && hit {
			return true
		}
	}
	return matchAll
}

func evalCondition(cond models.RuleCondition, msg models.Message) bool {
	var target string
	switch strings.ToLower(cond.Field) {
	case "from":
		target = strings.TrimSpace(msg.FromName + " " + msg.FromAddr)
	case "to":
		target = msg.ToAddrs
	case "subject":
		target = msg.Subject
	case "body":
		target = msg.BodyText + " " + msg.Snippet
	default:
		return false
	}

	target = strings.ToLower(target)
	val := strings.ToLower(strings.TrimSpace(cond.Value))
	if val == "" {
		return false
	}

	switch strings.ToLower(cond.Operator) {
	case "contains":
		return strings.Contains(target, val)
	case "not_contains":
		return !strings.Contains(target, val)
	case "equals":
		return target == val || strings.EqualFold(strings.TrimSpace(msg.FromAddr), val)
	case "starts_with":
		return strings.HasPrefix(target, val)
	case "ends_with":
		return strings.HasSuffix(target, val)
	default:
		return false
	}
}

// LoadUserRules 加载用户所有已启用的规则，按优先级升序排列。
func LoadUserRules(conn *sql.DB, userID int64) ([]models.Rule, error) {
	rows, err := conn.Query(`
		SELECT id, user_id, account_id, name, enabled, priority, match_mode, conditions_json, actions_json, created_at
		FROM rules
		WHERE user_id = ? AND enabled = 1
		ORDER BY priority ASC, id ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()

	var out []models.Rule
	for rows.Next() {
		r, err := scanRule(rows)
		if err == nil {
			out = append(out, r)
		}
	}
	return out, nil
}

// ApplyToMessage 对单封新入库邮件依次匹配并执行启用的规则。
func ApplyToMessage(conn *sql.DB, userID int64, msg models.Message) error {
	userRules, err := LoadUserRules(conn, userID)
	if err != nil || len(userRules) == 0 {
		return err
	}
	for _, r := range userRules {
		if Matches(r, msg) {
			if err := ExecuteActions(conn, r.Actions, msg); err != nil {
				return err
			}
		}
	}
	return nil
}

// RunRuleOnExisting 对用户已有邮件批量运行某条规则，返回命中数量。
func RunRuleOnExisting(conn *sql.DB, rule models.Rule) (int, error) {
	query := `
		SELECT id, user_id, account_id, folder_id, subject, from_name, from_addr, to_addrs, snippet, body_text
		FROM messages
		WHERE user_id = ?`
	args := []interface{}{rule.UserID}
	if rule.AccountID != nil {
		query += ` AND account_id = ?`
		args = append(args, *rule.AccountID)
	}

	rows, err := conn.Query(query, args...)
	if err != nil {
		return 0, err
	}
	var candidates []models.Message
	for rows.Next() {
		var m models.Message
		if err := rows.Scan(&m.ID, &m.UserID, &m.AccountID, &m.FolderID, &m.Subject, &m.FromName, &m.FromAddr, &m.ToAddrs, &m.Snippet, &m.BodyText); err == nil {
			candidates = append(candidates, m)
		}
	}
	_ = rows.Close()

	matched := 0
	for _, m := range candidates {
		if Matches(rule, m) {
			matched++
			_ = ExecuteActions(conn, rule.Actions, m)
		}
	}
	return matched, nil
}

// ExecuteActions 执行单组规则动作。
func ExecuteActions(conn *sql.DB, actions []models.RuleAction, msg models.Message) error {
	for _, act := range actions {
		switch strings.ToLower(act.Type) {
		case "mark_read":
			_, _ = conn.Exec(`UPDATE messages SET is_read = 1 WHERE id = ?`, msg.ID)
			_ = mailclient.RefreshFolderCounts(conn, msg.FolderID)
		case "star":
			_, _ = conn.Exec(`UPDATE messages SET is_starred = 1 WHERE id = ?`, msg.ID)
		case "add_tag":
			if tagID, err := strconv.ParseInt(act.Value, 10, 64); err == nil && tagID > 0 {
				_, _ = conn.Exec(`INSERT OR IGNORE INTO message_tags (message_id, tag_id) VALUES (?, ?)`, msg.ID, tagID)
			}
		case "move_folder":
			role := strings.ToLower(strings.TrimSpace(act.Value))
			if role == "" {
				role = "archive"
			}
			targetFolderID, err := mailclient.GetOrCreateFolderByRole(conn, msg.AccountID, role)
			if err == nil && targetFolderID > 0 && targetFolderID != msg.FolderID {
				_, _ = conn.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, targetFolderID, msg.ID)
				_ = mailclient.RefreshFolderCounts(conn, msg.FolderID)
				_ = mailclient.RefreshFolderCounts(conn, targetFolderID)
				msg.FolderID = targetFolderID
			}
		case "delete":
			targetFolderID, err := mailclient.GetOrCreateFolderByRole(conn, msg.AccountID, "trash")
			if err == nil && targetFolderID > 0 && targetFolderID != msg.FolderID {
				_, _ = conn.Exec(`UPDATE messages SET folder_id = ? WHERE id = ?`, targetFolderID, msg.ID)
				_ = mailclient.RefreshFolderCounts(conn, msg.FolderID)
				_ = mailclient.RefreshFolderCounts(conn, targetFolderID)
				msg.FolderID = targetFolderID
			}
		}
	}
	return nil
}

type rowScanner interface {
	Scan(dest ...interface{}) error
}

func scanRule(s rowScanner) (models.Rule, error) {
	var r models.Rule
	var enabledInt int
	var condJSON, actJSON string
	err := s.Scan(&r.ID, &r.UserID, &r.AccountID, &r.Name, &enabledInt, &r.Priority, &r.MatchMode, &condJSON, &actJSON, &r.CreatedAt)
	if err != nil {
		return r, err
	}
	r.Enabled = enabledInt == 1
	_ = json.Unmarshal([]byte(condJSON), &r.Conditions)
	_ = json.Unmarshal([]byte(actJSON), &r.Actions)
	return r, nil
}
