package translator

import (
	"bytes"
	"context"
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/net/html"
)

var (
	urlOnlyRe   = regexp.MustCompile(`(?i)^https?://\S+$`)
	emailOnlyRe = regexp.MustCompile(`^[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}$`)
	lineBreakRe = regexp.MustCompile(`[\r\n\t]+`)
	multiSpaceRe = regexp.MustCompile(` {2,}`)
)

var skipHTMLTags = map[string]bool{
	"script":   true,
	"style":    true,
	"noscript": true,
	"title":    true,
	"textarea": true,
	"code":     true,
	"pre":      true,
	"svg":      true,
	"math":     true,
}

type htmlTextSlot struct {
	node  *html.Node
	lead  string
	core  string
	trail string
}

// TranslateHTML 保留原始 HTML DOM 排版结构，仅原地替换可视文本节点为目标语言译文。
func (t *Translator) TranslateHTML(ctx context.Context, rawHTML, targetLang string) (string, string, error) {
	if strings.TrimSpace(rawHTML) == "" {
		return rawHTML, "", nil
	}
	targetLang = NormalizeLang(targetLang)

	doc, err := html.Parse(strings.NewReader(rawHTML))
	if err != nil {
		return "", "", err
	}

	var slots []htmlTextSlot
	uniqueSet := make(map[string]struct{})
	var uniqueTexts []string

	var walk func(n *html.Node, skip bool)
	walk = func(n *html.Node, skip bool) {
		if n.Type == html.ElementNode && skipHTMLTags[strings.ToLower(n.Data)] {
			skip = true
		}
		if !skip && n.Type == html.TextNode {
			lead, core, trail := splitTextPadding(n.Data)
			if shouldTranslateCore(core) {
				slots = append(slots, htmlTextSlot{
					node:  n,
					lead:  lead,
					core:  core,
					trail: trail,
				})
				if _, ok := uniqueSet[core]; !ok {
					uniqueSet[core] = struct{}{}
					uniqueTexts = append(uniqueTexts, core)
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c, skip)
		}
	}
	walk(doc, false)

	if len(uniqueTexts) == 0 {
		return renderInnerHTML(doc, rawHTML), "", nil
	}

	translations := make(map[string]string, len(uniqueTexts))
	usedProvider := ""

	// 将去重后的单行文本按不超过 1100 rune 分批翻译
	const maxBatchRunes = 1100
	var batch []string
	batchRunes := 0

	flushBatch := func() error {
		if len(batch) == 0 {
			return nil
		}
		prov, err := t.translateAlignedBatch(ctx, batch, targetLang, translations)
		if err != nil {
			return err
		}
		if prov != "" {
			usedProvider = prov
		}
		batch = nil
		batchRunes = 0
		return nil
	}

	for _, item := range uniqueTexts {
		rLen := len([]rune(item))
		if len(batch) > 0 && batchRunes+1+rLen > maxBatchRunes {
			if err := flushBatch(); err != nil {
				return "", "", err
			}
		}
		batch = append(batch, item)
		batchRunes += rLen + 1
	}
	if err := flushBatch(); err != nil {
		return "", "", err
	}

	for _, s := range slots {
		if tr, ok := translations[s.core]; ok && strings.TrimSpace(tr) != "" {
			s.node.Data = s.lead + tr + s.trail
		}
	}

	return renderInnerHTML(doc, rawHTML), usedProvider, nil
}

func (t *Translator) translateAlignedBatch(
	ctx context.Context,
	items []string,
	targetLang string,
	outMap map[string]string,
) (string, error) {
	if len(items) == 0 {
		return "", nil
	}
	if len(items) == 1 {
		out, prov, err := t.TranslateText(ctx, items[0], targetLang)
		if err != nil {
			return "", err
		}
		outMap[items[0]] = collapseInlineWhitespace(out)
		return prov, nil
	}

	joined := strings.Join(items, "\n")
	out, prov, err := t.TranslateText(ctx, joined, targetLang)
	if err != nil {
		return "", err
	}

	lines := strings.Split(strings.ReplaceAll(out, "\r\n", "\n"), "\n")
	if len(lines) == len(items) {
		for i, src := range items {
			outMap[src] = strings.TrimSpace(lines[i])
		}
		return prov, nil
	}

	// 行数未对齐时自动二分拆解，确保译文不会串行错位
	mid := len(items) / 2
	prov1, err := t.translateAlignedBatch(ctx, items[:mid], targetLang, outMap)
	if err != nil {
		return "", err
	}
	prov2, err := t.translateAlignedBatch(ctx, items[mid:], targetLang, outMap)
	if err != nil {
		return "", err
	}
	if prov2 != "" {
		return prov2, nil
	}
	return prov1, nil
}

func splitTextPadding(raw string) (lead, core, trail string) {
	if raw == "" {
		return "", "", ""
	}
	start := 0
	for start < len(raw) {
		r := rune(raw[start])
		if r < 0x80 && unicode.IsSpace(r) {
			start++
			continue
		}
		break
	}
	// 使用索引遍历处理 Unicode 空白
	runes := []rune(raw)
	left := 0
	for left < len(runes) && unicode.IsSpace(runes[left]) {
		left++
	}
	right := len(runes)
	for right > left && unicode.IsSpace(runes[right-1]) {
		right--
	}
	lead = string(runes[:left])
	trail = string(runes[right:])
	core = collapseInlineWhitespace(string(runes[left:right]))
	return lead, core, trail
}

func collapseInlineWhitespace(s string) string {
	s = lineBreakRe.ReplaceAllString(s, " ")
	s = multiSpaceRe.ReplaceAllString(s, " ")
	return strings.TrimSpace(s)
}

func shouldTranslateCore(core string) bool {
	if core == "" {
		return false
	}
	if urlOnlyRe.MatchString(core) || emailOnlyRe.MatchString(core) {
		return false
	}
	for _, r := range core {
		if unicode.IsLetter(r) {
			return true
		}
	}
	return false
}

func renderInnerHTML(doc *html.Node, fallback string) string {
	body := findElementByTag(doc, "body")
	target := body
	if target == nil {
		target = doc
	}
	var buf bytes.Buffer
	for c := target.FirstChild; c != nil; c = c.NextSibling {
		if err := html.Render(&buf, c); err != nil {
			return fallback
		}
	}
	return buf.String()
}

func findElementByTag(n *html.Node, tag string) *html.Node {
	if n.Type == html.ElementNode && strings.EqualFold(n.Data, tag) {
		return n
	}
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		if found := findElementByTag(c, tag); found != nil {
			return found
		}
	}
	return nil
}
