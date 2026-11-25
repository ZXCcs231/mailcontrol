package rules

import (
	"database/sql"
	"encoding/json"
	"strconv"

	"mailcontrol-backend/internal/models"
)

// RulePreset 描述一条内置常用的自动分类规则模板。
type RulePreset struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Description string                 `json:"description"`
	TagName     string                 `json:"tag_name,omitempty"`
	TagColor    string                 `json:"tag_color,omitempty"`
	Enabled     bool                   `json:"enabled"`
	Priority    int                    `json:"priority"`
	MatchMode   string                 `json:"match_mode"`
	Conditions  []models.RuleCondition `json:"conditions"`
	Actions     []models.RuleAction    `json:"actions"`
}

var builtinPresets = []RulePreset{
	{
		ID:          "verification_code",
		Name:        "验证码自动标为已读",
		Description: "识别含验证码 / OTP / Verification Code 的邮件，自动打上「验证码」标签并标为已读，保持收件箱清爽。",
		TagName:     "验证码",
		TagColor:    "#0891b2",
		Enabled:     true,
		Priority:    10,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "验证码"},
			{Field: "subject", Operator: "contains", Value: "verification code"},
			{Field: "subject", Operator: "contains", Value: "security code"},
			{Field: "subject", Operator: "contains", Value: "OTP"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
			{Type: "mark_read"},
		},
	},
	{
		ID:          "invoice_bill",
		Name:        "账单与发票自动标星",
		Description: "识别含账单、电子发票、Invoice、Receipt 的邮件，自动加星标并归类到「账单发票」标签。",
		TagName:     "账单发票",
		TagColor:    "#d97706",
		Enabled:     true,
		Priority:    20,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "发票"},
			{Field: "subject", Operator: "contains", Value: "账单"},
			{Field: "subject", Operator: "contains", Value: "invoice"},
			{Field: "subject", Operator: "contains", Value: "receipt"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
			{Type: "star"},
		},
	},
	{
		ID:          "dev_notifications",
		Name:        "开发与代码通知归类",
		Description: "来自 GitHub、GitLab、Gitee 等代码托管平台的邮件自动打上「开发通知」标签。",
		TagName:     "开发通知",
		TagColor:    "#7c3aed",
		Enabled:     true,
		Priority:    30,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "from", Operator: "contains", Value: "github.com"},
			{Field: "from", Operator: "contains", Value: "gitlab.com"},
			{Field: "from", Operator: "contains", Value: "gitee.com"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
		},
	},
	{
		ID:          "order_logistics",
		Name:        "订单与物流提醒",
		Description: "识别含订单、发货、快递、物流、Shipped 的通知邮件，打上「订单物流」标签。",
		TagName:     "订单物流",
		TagColor:    "#16a34a",
		Enabled:     true,
		Priority:    40,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "订单"},
			{Field: "subject", Operator: "contains", Value: "发货"},
			{Field: "subject", Operator: "contains", Value: "快递"},
			{Field: "subject", Operator: "contains", Value: "物流"},
			{Field: "subject", Operator: "contains", Value: "shipped"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
		},
	},
	{
		ID:          "security_alert",
		Name:        "安全与登录告警标星",
		Description: "识别异地登录、安全告警、密码修改等高重要度通知，自动打标签并加星标提醒。",
		TagName:     "安全告警",
		TagColor:    "#dc2626",
		Enabled:     true,
		Priority:    5,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "安全告警"},
			{Field: "subject", Operator: "contains", Value: "异地登录"},
			{Field: "subject", Operator: "contains", Value: "security alert"},
			{Field: "subject", Operator: "contains", Value: "new sign-in"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
			{Type: "star"},
		},
	},
	{
		ID:          "newsletter_archive",
		Name:        "订阅与推广邮件自动归档",
		Description: "识别包含退订、优惠、促销、Newsletter、Unsubscribe 的推广邮件，自动移入归档（默认关闭，按需开启）。",
		TagName:     "订阅推广",
		TagColor:    "#64748b",
		Enabled:     false,
		Priority:    90,
		MatchMode:   "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "退订"},
			{Field: "subject", Operator: "contains", Value: "促销"},
			{Field: "subject", Operator: "contains", Value: "newsletter"},
			{Field: "body", Operator: "contains", Value: "unsubscribe"},
		},
		Actions: []models.RuleAction{
			{Type: "add_tag"},
			{Type: "move_folder", Value: "archive"},
		},
	},
}

// Presets 返回所有内置自动分类规则模板。
func Presets() []RulePreset {
	out := make([]RulePreset, len(builtinPresets))
	copy(out, builtinPresets)
	return out
}

// InstallPresetsForUser 为用户导入指定的预设规则（presetIDs 为空时导入全部），自动跳过同名规则并绑定对应彩色标签。
func InstallPresetsForUser(conn *sql.DB, userID int64, presetIDs []string) (int, error) {
	selected := make(map[string]bool)
	for _, id := range presetIDs {
		selected[id] = true
	}

	added := 0
	for _, p := range builtinPresets {
		if len(selected) > 0 && !selected[p.ID] {
			continue
		}

		var exists int
		if err := conn.QueryRow(`SELECT COUNT(*) FROM rules WHERE user_id = ? AND name = ?`, userID, p.Name).Scan(&exists); err == nil && exists > 0 {
			continue
		}

		var tagID int64
		if p.TagName != "" {
			_, _ = conn.Exec(`INSERT OR IGNORE INTO tags (user_id, name, color) VALUES (?, ?, ?)`, userID, p.TagName, p.TagColor)
			_ = conn.QueryRow(`SELECT id FROM tags WHERE user_id = ? AND name = ?`, userID, p.TagName).Scan(&tagID)
		}

		actions := make([]models.RuleAction, 0, len(p.Actions))
		for _, a := range p.Actions {
			if a.Type == "add_tag" {
				if tagID > 0 {
					actions = append(actions, models.RuleAction{Type: "add_tag", Value: strconv.FormatInt(tagID, 10)})
				}
			} else {
				actions = append(actions, a)
			}
		}

		condB, _ := json.Marshal(p.Conditions)
		actB, _ := json.Marshal(actions)
		enabledInt := 0
		if p.Enabled {
			enabledInt = 1
		}

		if _, err := conn.Exec(`
			INSERT INTO rules (user_id, account_id, name, enabled, priority, match_mode, conditions_json, actions_json)
			VALUES (?, NULL, ?, ?, ?, ?, ?, ?)`,
			userID, p.Name, enabledInt, p.Priority, p.MatchMode, string(condB), string(actB),
		); err != nil {
			return added, err
		}
		added++
	}
	return added, nil
}
