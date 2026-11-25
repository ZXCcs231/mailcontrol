package rules

import (
	"testing"

	"mailcontrol-backend/internal/models"
)

func TestMatchesAllAndAny(t *testing.T) {
	msg := models.Message{
		AccountID: 1,
		FromName:  "GitHub",
		FromAddr:  "notifications@github.com",
		ToAddrs:   "dev@qq.com",
		Subject:   "[mailcontrol] Pull Request #12",
		BodyText:  "Please review the latest commit.",
	}

	allRule := models.Rule{
		MatchMode: "all",
		Conditions: []models.RuleCondition{
			{Field: "from", Operator: "contains", Value: "github.com"},
			{Field: "subject", Operator: "starts_with", Value: "[mailcontrol]"},
		},
	}
	if !Matches(allRule, msg) {
		t.Fatal("expected allRule to match")
	}

	allFail := models.Rule{
		MatchMode: "all",
		Conditions: []models.RuleCondition{
			{Field: "from", Operator: "contains", Value: "github.com"},
			{Field: "subject", Operator: "contains", Value: "invoice"},
		},
	}
	if Matches(allFail, msg) {
		t.Fatal("expected allFail not to match")
	}

	anyRule := models.Rule{
		MatchMode: "any",
		Conditions: []models.RuleCondition{
			{Field: "subject", Operator: "contains", Value: "invoice"},
			{Field: "body", Operator: "contains", Value: "review"},
		},
	}
	if !Matches(anyRule, msg) {
		t.Fatal("expected anyRule to match")
	}

	acctMismatch := int64(2)
	scopedRule := models.Rule{
		AccountID: &acctMismatch,
		MatchMode: "all",
		Conditions: []models.RuleCondition{
			{Field: "from", Operator: "contains", Value: "github.com"},
		},
	}
	if Matches(scopedRule, msg) {
		t.Fatal("expected scopedRule for account 2 not to match account 1 message")
	}
}
