package crypto

import (
	"crypto/rand"
	"testing"
)

func TestPasswordHashAndCheck(t *testing.T) {
	hash, err := HashPassword("my-secret-pass")
	if err != nil {
		t.Fatalf("HashPassword failed: %v", err)
	}
	if !CheckPassword(hash, "my-secret-pass") {
		t.Fatal("expected password to match")
	}
	if CheckPassword(hash, "wrong-pass") {
		t.Fatal("expected wrong password not to match")
	}
}

func TestEncryptDecrypt(t *testing.T) {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		t.Fatal(err)
	}
	plain := "auth-code-123456-中文"
	enc, err := Encrypt(plain, key)
	if err != nil {
		t.Fatalf("Encrypt failed: %v", err)
	}
	if enc == plain {
		t.Fatal("ciphertext should not equal plaintext")
	}
	dec, err := Decrypt(enc, key)
	if err != nil {
		t.Fatalf("Decrypt failed: %v", err)
	}
	if dec != plain {
		t.Fatalf("got %q want %q", dec, plain)
	}
}

func TestJWT(t *testing.T) {
	secret := "test-jwt-secret-key"
	token, err := GenerateToken(42, "alice", secret)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}
	claims, err := ParseToken(token, secret)
	if err != nil {
		t.Fatalf("ParseToken failed: %v", err)
	}
	if claims.UserID != 42 || claims.Username != "alice" {
		t.Fatalf("unexpected claims: %+v", claims)
	}
}
