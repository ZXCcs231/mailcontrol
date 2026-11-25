package api

import (
	"database/sql"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/translator"
)

var htmlStripRe = regexp.MustCompile(`(?s)<style.*?>.*?</style>|<script.*?>.*?</script>|<[^>]+>`)

func (s *Server) getTranslator() *translator.Translator {
	if s.Translator != nil {
		return s.Translator
	}
	s.Translator = translator.New()
	return s.Translator
}

type translateMsgReq struct {
	TargetLang string `json:"target_lang"`
	Force      bool   `json:"force"`
}

type translateTextReq struct {
	Subject    string `json:"subject"`
	Text       string `json:"text"`
	TargetLang string `json:"target_lang"`
}

func (s *Server) GetTranslateLanguages(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"items": translator.SupportedLanguages})
}

func (s *Server) TranslateMessage(c *gin.Context) {
	uid := currentUserID(c)
	msgID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "无效的邮件 ID"})
		return
	}

	var req translateMsgReq
	_ = c.ShouldBindJSON(&req)
	targetLang := translator.NormalizeLang(req.TargetLang)

	var subject, bodyText, bodyHTML string
	err = s.DB.QueryRow(`
		SELECT subject, body_text, body_html
		FROM messages WHERE id = ? AND user_id = ?`, msgID, uid,
	).Scan(&subject, &bodyText, &bodyHTML)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "邮件不存在"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if !req.Force {
		var provider, tSub, tText string
		err := s.DB.QueryRow(`
			SELECT provider, translated_subject, translated_text
			FROM message_translations
			WHERE message_id = ? AND target_lang = ?`, msgID, targetLang,
		).Scan(&provider, &tSub, &tText)
		if err == nil && (tText != "" || tSub != "") {
			c.JSON(http.StatusOK, gin.H{
				"message_id":         msgID,
				"target_lang":        targetLang,
				"provider":           provider,
				"translated_subject": tSub,
				"translated_text":    tText,
				"cached":             true,
			})
			return
		}
	}

	plain := strings.TrimSpace(bodyText)
	if plain == "" && bodyHTML != "" {
		plain = cleanHTMLForTranslate(bodyHTML)
	}

	tr := s.getTranslator()
	var tSub, tText, usedProvider string

	if strings.TrimSpace(subject) != "" && subject != "（无主题）" {
		outSub, prov, err := tr.TranslateText(c.Request.Context(), subject, targetLang)
		if err == nil {
			tSub = outSub
			usedProvider = prov
		}
	}
	if plain != "" {
		outText, prov, err := tr.TranslateText(c.Request.Context(), plain, targetLang)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "翻译失败：" + err.Error()})
			return
		}
		tText = outText
		usedProvider = prov
	}
	if tSub == "" {
		tSub = subject
	}

	_, _ = s.DB.Exec(`
		INSERT INTO message_translations (message_id, target_lang, provider, translated_subject, translated_text)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT(message_id, target_lang) DO UPDATE SET
			provider = excluded.provider,
			translated_subject = excluded.translated_subject,
			translated_text = excluded.translated_text,
			created_at = CURRENT_TIMESTAMP`,
		msgID, targetLang, usedProvider, tSub, tText,
	)

	c.JSON(http.StatusOK, gin.H{
		"message_id":         msgID,
		"target_lang":        targetLang,
		"provider":           usedProvider,
		"translated_subject": tSub,
		"translated_text":    tText,
		"cached":             false,
	})
}

func (s *Server) TranslateText(c *gin.Context) {
	var req translateTextReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数格式错误"})
		return
	}
	if strings.TrimSpace(req.Text) == "" && strings.TrimSpace(req.Subject) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入需要翻译的内容"})
		return
	}

	targetLang := translator.NormalizeLang(req.TargetLang)
	tr := s.getTranslator()

	var tSub, tText, usedProvider string
	if strings.TrimSpace(req.Subject) != "" {
		outSub, prov, err := tr.TranslateText(c.Request.Context(), req.Subject, targetLang)
		if err == nil {
			tSub = outSub
			usedProvider = prov
		}
	}
	if strings.TrimSpace(req.Text) != "" {
		outText, prov, err := tr.TranslateText(c.Request.Context(), req.Text, targetLang)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "翻译失败：" + err.Error()})
			return
		}
		tText = outText
		usedProvider = prov
	}

	c.JSON(http.StatusOK, gin.H{
		"target_lang":        targetLang,
		"provider":           usedProvider,
		"translated_subject": tSub,
		"translated_text":    tText,
	})
}

func cleanHTMLForTranslate(raw string) string {
	s := strings.NewReplacer("<br>", "\n", "<br/>", "\n", "<br />", "\n", "</p>", "\n", "</div>", "\n", "</li>", "\n").Replace(raw)
	s = htmlStripRe.ReplaceAllString(s, " ")
	s = strings.NewReplacer("&nbsp;", " ", "&lt;", "<", "&gt;", ">", "&amp;", "&", "&quot;", `"`).Replace(s)
	lines := strings.Split(s, "\n")
	var out []string
	for _, l := range lines {
		t := strings.TrimSpace(l)
		if t != "" {
			out = append(out, t)
		}
	}
	return strings.Join(out, "\n")
}
