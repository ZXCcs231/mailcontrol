package mailclient

import (
	"bytes"
	"crypto/rand"
	"crypto/tls"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"mime"
	"net"
	"net/smtp"
	"strings"
	"time"
)

// SendAttachment 描述发信时附带的文件。
type SendAttachment struct {
	Filename    string
	ContentType string
	Data        []byte
}

// SendPayload 描述一封待发送邮件的完整内容。
type SendPayload struct {
	FromName    string
	FromAddr    string
	To          []string
	Cc          []string
	Bcc         []string
	Subject     string
	BodyText    string
	BodyHTML    string
	InReplyTo   string
	References  string
	Attachments []SendAttachment
}

// TestSMTP 验证 SMTP 握手与认证是否成功。
func TestSMTP(cfg AccountConfig) error {
	c, err := dialSMTP(cfg)
	if err != nil {
		return err
	}
	_ = c.Quit()
	return nil
}

func dialSMTP(cfg AccountConfig) (*smtp.Client, error) {
	addr := net.JoinHostPort(cfg.SMTPHost, fmt.Sprintf("%d", cfg.SMTPPort))
	dialer := &net.Dialer{Timeout: 15 * time.Second}
	tlsCfg := &tls.Config{ServerName: cfg.SMTPHost}

	var c *smtp.Client
	var err error
	switch strings.ToLower(cfg.SMTPTLS) {
	case "ssl", "tls":
		conn, dialErr := tls.DialWithDialer(dialer, "tcp", addr, tlsCfg)
		if dialErr != nil {
			return nil, dialErr
		}
		c, err = smtp.NewClient(conn, cfg.SMTPHost)
		if err != nil {
			_ = conn.Close()
			return nil, err
		}
	case "starttls":
		conn, dialErr := dialer.Dial("tcp", addr)
		if dialErr != nil {
			return nil, dialErr
		}
		c, err = smtp.NewClient(conn, cfg.SMTPHost)
		if err != nil {
			_ = conn.Close()
			return nil, err
		}
		if ok, _ := c.Extension("STARTTLS"); ok {
			if err = c.StartTLS(tlsCfg); err != nil {
				_ = c.Close()
				return nil, err
			}
		}
	default:
		conn, dialErr := dialer.Dial("tcp", addr)
		if dialErr != nil {
			return nil, dialErr
		}
		c, err = smtp.NewClient(conn, cfg.SMTPHost)
		if err != nil {
			_ = conn.Close()
			return nil, err
		}
	}

	user := cfg.Username
	if user == "" {
		user = cfg.EmailAddress
	}
	auth := smtp.PlainAuth("", user, cfg.Password, cfg.SMTPHost)
	if err := c.Auth(auth); err != nil {
		_ = c.Close()
		return nil, err
	}
	return c, nil
}

// SendMail 通过 SMTP 发送支持中文主题、HTML/纯文本正文与多附件的邮件，并返回 Message-ID。
func SendMail(cfg AccountConfig, p SendPayload) (string, error) {
	c, err := dialSMTP(cfg)
	if err != nil {
		return "", err
	}
	defer func() { _ = c.Quit() }()

	msgID := generateMessageID(p.FromAddr)
	raw := buildMIMEMessage(p, msgID)

	if err := c.Mail(p.FromAddr); err != nil {
		return "", err
	}
	recipients := make([]string, 0, len(p.To)+len(p.Cc)+len(p.Bcc))
	recipients = append(recipients, p.To...)
	recipients = append(recipients, p.Cc...)
	recipients = append(recipients, p.Bcc...)

	for _, rcpt := range recipients {
		addr := extractPureEmail(rcpt)
		if addr == "" {
			continue
		}
		if err := c.Rcpt(addr); err != nil {
			return "", fmt.Errorf("收件人 %s 被服务器拒绝: %w", addr, err)
		}
	}

	w, err := c.Data()
	if err != nil {
		return "", err
	}
	if _, err := w.Write(raw); err != nil {
		_ = w.Close()
		return "", err
	}
	if err := w.Close(); err != nil {
		return "", err
	}
	return msgID, nil
}

func buildMIMEMessage(p SendPayload, msgID string) []byte {
	var buf bytes.Buffer
	writeHeader := func(k, v string) {
		if v != "" {
			buf.WriteString(k + ": " + v + "\r\n")
		}
	}

	fromHeader := p.FromAddr
	if p.FromName != "" {
		fromHeader = fmt.Sprintf("%s <%s>", mime.BEncoding.Encode("utf-8", p.FromName), p.FromAddr)
	}
	writeHeader("From", fromHeader)
	writeHeader("To", strings.Join(p.To, ", "))
	if len(p.Cc) > 0 {
		writeHeader("Cc", strings.Join(p.Cc, ", "))
	}
	writeHeader("Subject", mime.BEncoding.Encode("utf-8", p.Subject))
	writeHeader("Date", time.Now().Format(time.RFC1123Z))
	writeHeader("Message-ID", msgID)
	if p.InReplyTo != "" {
		writeHeader("In-Reply-To", p.InReplyTo)
	}
	if p.References != "" {
		writeHeader("References", p.References)
	}
	writeHeader("MIME-Version", "1.0")

	mixedBoundary := randomBoundary("MIXED")
	altBoundary := randomBoundary("ALT")

	if len(p.Attachments) > 0 {
		writeHeader("Content-Type", fmt.Sprintf(`multipart/mixed; boundary="%s"`, mixedBoundary))
		buf.WriteString("\r\n--" + mixedBoundary + "\r\n")
	}

	buf.WriteString(fmt.Sprintf("Content-Type: multipart/alternative; boundary=\"%s\"\r\n\r\n", altBoundary))

	plain := p.BodyText
	if plain == "" && p.BodyHTML != "" {
		plain = stripHTMLTags(p.BodyHTML)
	}
	buf.WriteString("--" + altBoundary + "\r\n")
	buf.WriteString("Content-Type: text/plain; charset=UTF-8\r\n")
	buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
	writeBase64Lines(&buf, []byte(plain))

	if p.BodyHTML != "" {
		buf.WriteString("--" + altBoundary + "\r\n")
		buf.WriteString("Content-Type: text/html; charset=UTF-8\r\n")
		buf.WriteString("Content-Transfer-Encoding: base64\r\n\r\n")
		writeBase64Lines(&buf, []byte(p.BodyHTML))
	}
	buf.WriteString("--" + altBoundary + "--\r\n")

	for _, att := range p.Attachments {
		buf.WriteString("--" + mixedBoundary + "\r\n")
		ct := att.ContentType
		if ct == "" {
			ct = "application/octet-stream"
		}
		encName := mime.BEncoding.Encode("utf-8", att.Filename)
		buf.WriteString(fmt.Sprintf("Content-Type: %s; name=\"%s\"\r\n", ct, encName))
		buf.WriteString("Content-Transfer-Encoding: base64\r\n")
		buf.WriteString(fmt.Sprintf("Content-Disposition: attachment; filename=\"%s\"\r\n\r\n", encName))
		writeBase64Lines(&buf, att.Data)
	}

	if len(p.Attachments) > 0 {
		buf.WriteString("--" + mixedBoundary + "--\r\n")
	}
	return buf.Bytes()
}

func writeBase64Lines(buf *bytes.Buffer, data []byte) {
	encoded := base64.StdEncoding.EncodeToString(data)
	for i := 0; i < len(encoded); i += 76 {
		end := i + 76
		if end > len(encoded) {
			end = len(encoded)
		}
		buf.WriteString(encoded[i:end] + "\r\n")
	}
}

func randomBoundary(prefix string) string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return fmt.Sprintf("==MailControl_%s_%s==", prefix, hex.EncodeToString(b))
}

func generateMessageID(fromAddr string) string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	domain := "mailcontrol.local"
	if parts := strings.Split(fromAddr, "@"); len(parts) == 2 && parts[1] != "" {
		domain = parts[1]
	}
	return fmt.Sprintf("<%d.%s@%s>", time.Now().UnixNano(), hex.EncodeToString(b), domain)
}

func extractPureEmail(raw string) string {
	raw = strings.TrimSpace(raw)
	if start := strings.LastIndex(raw, "<"); start != -1 {
		if end := strings.LastIndex(raw, ">"); end > start {
			return strings.TrimSpace(raw[start+1 : end])
		}
	}
	return raw
}
