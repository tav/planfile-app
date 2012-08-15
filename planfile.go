// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/crypto"
	"amp/log"
	"amp/oauth"
	"amp/runtime"
	"amp/yaml"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"sync"
)

type Config struct {
	CookieKey           string
	GoogleAnalyticsHost string
	GoogleAnalyticsID   string
	OAuthClientID       string
	OAuthClientSecret   string
	Repository          string
	SecureMode          bool
	RedirectURL         string
}

type Context struct {
	r      *http.Request
	w      http.ResponseWriter
	secret []byte
	secure bool
	token  *oauth.Token
}

func (ctx *Context) Call(path string, v interface{}) error {
	client := &http.Client{}
	req, err := http.NewRequest("GET", "https://api.github.com"+path, nil)
	if err != nil {
		return err
	}
	if ctx.token == nil {
		tok, err := hex.DecodeString(ctx.GetCookie("token"))
		if err != nil {
			ctx.ExpireCookie("token")
			return err
		}
		err = json.Unmarshal(tok, ctx.token)
		if err != nil {
			ctx.ExpireCookie("token")
			return err
		}
	}
	req.Header.Add("Authorization", "bearer "+ctx.token.AccessToken)
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	dec := json.NewDecoder(resp.Body)
	err = dec.Decode(v)
	return err
}

func (ctx *Context) Error(s string, err error) {
	log.Error("%s: %s", s, err)
	if err == nil {
		fmt.Fprintf(ctx, "ERROR: %s", s)
	} else {
		fmt.Fprintf(ctx, "ERROR: %s: %s", s, err)
	}
}

func (ctx *Context) ExpireCookie(attr string) {
	http.SetCookie(ctx.w, &http.Cookie{Name: attr, MaxAge: -1, Secure: ctx.secure})
}

func (ctx *Context) FormValue(attr string) string {
	return ctx.r.FormValue(attr)
}

func (ctx *Context) GetCookie(attr string) string {
	cookie, err := ctx.r.Cookie(attr)
	if err != nil {
		return ""
	}
	val, ok := crypto.GetIronValue(attr, cookie.Value, ctx.secret, false)
	if ok {
		return val
	}
	return ""
}

func (ctx *Context) Redirect(path string) {
	http.Redirect(ctx.w, ctx.r, path, http.StatusFound)
}

func (ctx *Context) SetCookie(attr, val string) {
	http.SetCookie(ctx.w, &http.Cookie{
		Name:   attr,
		Value:  crypto.IronString(attr, val, ctx.secret, -1),
		MaxAge: 0,
		Secure: ctx.secure,
	})
}

func (ctx *Context) SetHeader(attr, val string) {
	ctx.w.Header().Set(attr, val)
}

func (ctx *Context) Write(data []byte) (int, error) {
	return ctx.w.Write(data)
}

func IsEqual(x, y []byte) bool {
	if len(x) != len(y) {
		return false
	}
	return subtle.ConstantTimeCompare(x, y) == 1
}

func ReadFile(path string) []byte {
	c, err := ioutil.ReadFile(path)
	if err != nil {
		runtime.StandardError(err)
	}
	return c
}

type User struct {
	Login     string `json:"login"`
	AvatarURL string `json:"avatar_url"`
}

func main() {

	log.AddConsoleLogger()
	data, err := yaml.ParseFile("config.yaml")
	if err != nil {
		runtime.StandardError(err)
	}

	config := &Config{}
	data.LoadStruct(config)

	service := &oauth.OAuthService{
		ClientID:     config.OAuthClientID,
		ClientSecret: config.OAuthClientSecret,
		Scope:        "public_repo",
		AuthURL:      "https://github.com/login/oauth/authorize",
		TokenURL:     "https://github.com/login/oauth/access_token",
		RedirectURL:  config.RedirectURL,
		AcceptHeader: "application/json",
	}

	assets := map[string]string{}
	json.Unmarshal(ReadFile("assets.json"), &assets)

	indexHead := ReadFile("templates/index.html")
	mutex := sync.RWMutex{}
	secret := []byte(config.CookieKey)

	register := func(path string, handler func(*Context)) {
		http.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			ctx := &Context{
				r:      r,
				w:      w,
				secret: secret,
				secure: config.SecureMode,
			}
			ctx.SetHeader("Content-Type", "text/html; charset=utf-8")
			handler(ctx)
		})
	}

	register("/", func(ctx *Context) {
		mutex.RLock()
		defer mutex.RUnlock()
		if ctx.r.URL.Path != "/" {
			http.NotFound(ctx.w, ctx.r)
			return
		}
		ctx.Write(indexHead)
		ctx.Write([]byte("<link href='/static/" + assets["planfile.css"] + "' rel='stylesheet' type='text/css'></head>" +
			"<body data-user='" + ctx.GetCookie("user") + "'>" +
			"<script src='/static/" + assets["planfile.js"] + "' type='text/javascript'></script></body>"))
		
	})

	register("/login", func(ctx *Context) {
		b := make([]byte, 20)
		if n, err := rand.Read(b); err != nil || n != 20 {
			ctx.Error("Couldn't access cryptographic device", err)
			return
		}
		s := hex.EncodeToString(b)
		ctx.SetCookie("state", s)
		ctx.Redirect(service.AuthCodeURL(s))
	})

	register("/logout", func(ctx *Context) {
		ctx.ExpireCookie("token")
		ctx.ExpireCookie("user")
		ctx.Redirect("/")
	})

	register("/oauth", func(ctx *Context) {
		s := ctx.FormValue("state")
		if s == "" {
			ctx.Redirect("/login")
			return
		}
		if !IsEqual([]byte(s), []byte(ctx.GetCookie("state"))) {
			ctx.ExpireCookie("state")
			ctx.Redirect("/login")
			return
		}
		ctx.ExpireCookie("state")
		t := &oauth.Transport{OAuthService: service}
		tok, err := t.ExchangeAuthorizationCode(ctx.FormValue("code"))
		if err != nil {
			ctx.Error("Auth Exchange Error", err)
			return
		}
		jtok, err := json.Marshal(tok)
		if err != nil {
			ctx.Error("Couldn't encode token", err)
			return
		}
		ctx.SetCookie("token", hex.EncodeToString(jtok))
		ctx.token = tok
		user := &User{}
		err = ctx.Call("/user", user)
		if err != nil {
			ctx.Error("Couldn't load user info", err)
			return
		}
		ctx.SetCookie("user", user.Login)
		ctx.Redirect("/")
	})

	register("/refresh", func(ctx *Context) {
		mutex.Lock()
		defer mutex.Unlock()
		ctx.Write([]byte("OK."))
	})

	mimetypes := map[string]string{
		"css":  "text/css",
		"gif":  "image/gif",
		"ico":  "image/x-icon",
		"jpeg": "image/jpeg",
		"jpg":  "image/jpeg",
		"js":   "text/javascript",
		"png":  "image/png",
		"txt":  "text/plain",
	}

	registerStatic := func(filepath, urlpath string) {
		content := ReadFile(filepath)
		split := strings.Split(filepath, ".")
		ctype, ok := mimetypes[split[len(split)-1]]
		if !ok {
			ctype = "application/octet-stream"
		}
		register(urlpath, func(ctx *Context) {
			ctx.SetHeader("Content-Type", ctype)
			ctx.Write(content)
		})
	}

	for _, path := range assets {
		registerStatic("static/"+path, "/static/"+path)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8888"
	}

	log.Info("Listening on port %s", port)
	err = http.ListenAndServe(":"+port, nil)
	if err != nil {
		runtime.Error("couldn't bind to tcp socket: %s", err)
	}

}
