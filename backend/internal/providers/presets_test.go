package providers

import "testing"

func TestPresetsCountAndMatch(t *testing.T) {
	all := All()
	if len(all) != 12 {
		t.Fatalf("expected 12 presets, got %d", len(all))
	}

	cases := map[string]string{
		"user@qq.com":       "qq",
		"foo@foxmail.com":   "qq",
		"bar@163.com":       "163",
		"baz@126.com":       "126",
		"test@gmail.com":    "gmail",
		"me@outlook.com":    "outlook",
		"apple@icloud.com":  "icloud",
		"other@example.org": "custom",
	}
	for email, wantID := range cases {
		got := MatchByEmail(email)
		if got.ID != wantID {
			t.Errorf("MatchByEmail(%q) = %q, want %q", email, got.ID, wantID)
		}
	}

	if !GetByID("163").NeedsIMAPID || !GetByID("126").NeedsIMAPID {
		t.Error("expected 163 and 126 presets to require IMAP ID")
	}
}
