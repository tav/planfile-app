// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/crypto"
	"amp/log"
	"amp/oauth"
	"amp/optparse"
	"amp/runtime"
	"amp/tlsconf"
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"strings"
	"sync"
)

var (
	httpClient = &http.Client{Transport: &http.Transport{TLSClientConfig: tlsconf.Config}}
	runPath    string
)

type Context struct {
	r      *http.Request
	w      http.ResponseWriter
	secret []byte
	secure bool
	token  *oauth.Token
}

func (ctx *Context) Call(path string, v interface{}) error {
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
	resp, err := httpClient.Do(req)
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
		Name:     attr,
		Value:    crypto.IronString(attr, val, ctx.secret, -1),
		HttpOnly: true,
		MaxAge:   0,
		Secure:   ctx.secure,
	})
}

func (ctx *Context) SetHeader(attr, val string) {
	ctx.w.Header().Set(attr, val)
}

func (ctx *Context) Write(data []byte) (int, error) {
	return ctx.w.Write(data)
}

func isEqual(x, y []byte) bool {
	if len(x) != len(y) {
		return false
	}
	return subtle.ConstantTimeCompare(x, y) == 1
}

func readFile(path string) []byte {
	c, err := ioutil.ReadFile(path)
	if err != nil {
		runtime.StandardError(err)
	}
	return c
}

type file struct {
	name    string
	content []string
}

func LoadRepository(path string) []file {
	resp, err := httpClient.Get(path)
	if err != nil {
		runtime.StandardError(err)
	}
	defer resp.Body.Close()
	zf, err := gzip.NewReader(resp.Body)
	if err != nil {
		runtime.Error("couldn't find a valid repo tarball at %s -- %s", path, err)
	}
	tr := tar.NewReader(zf)
	repo := []file{}
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			runtime.StandardError(err)
		}
		splitDot := strings.Split(hdr.Name, ".")
		splitSlash := strings.Split(hdr.Name, "/")
		// Check if the file ends with .md
		ending := splitDot[len(splitDot)-1:]
		if ending[0] == "md" {
			var lines []string
			var part []byte
			var prefix bool
			filename := splitSlash[len(splitSlash)-1:]
			reader := bufio.NewReader(tr)
			buffer := &bytes.Buffer{}
			for {
				if part, prefix, err = reader.ReadLine(); err != nil {
					break
				}
				buffer.Write(part)
				if !prefix {
					lines = append(lines, buffer.String())
					buffer.Reset()
				}
			}
			repo = append(repo, file{filename[0], lines})
		}
	}
	return repo
}

type User struct {
	Login     string `json:"login"`
	AvatarURL string `json:"avatar_url"`
}

func main() {

	// Define the options for the command line and config file options parser.
	opts := optparse.Parser(
		"Usage: planfile <config.yaml> [options]\n",
		"planfile 0.0.1")

	cookieKeyFile := opts.StringConfig("cookie-key-file", "cookie.key",
		"the file containing the key to sign cookie values [cookie.key]")

	gaHost := opts.StringConfig("ga-host", "",
		"the google analytics hostname to use")

	gaID := opts.StringConfig("ga-id", "",
		"the google analytics id to use")

	httpAddr := opts.StringConfig("http-addr", ":8888",
		"the address to bind the http server [:8888]")

	oauthID := opts.StringConfig("oauth-id", "",
		"the oauth client id for github", true)

	oauthSecret := opts.StringConfig("oauth-secret", "",
		"the oauth client secret for github", true)

	redirectURL := opts.StringConfig("redirect-url", "/oauth",
		"the redirect url for handling oauth [/oauth]")

	repository := opts.StringConfig("repository", "",
		"the username/repository on github", true)

	secureMode := opts.BoolConfig("secure-mode", false,
		"enable hsts and secure cookies [false]")

	_ = gaHost
	_ = gaID

	debug, instanceDirectory, _ := runtime.DefaultOpts("planfile", opts, os.Args)

	runPath = instanceDirectory
	setupPygments()

	service := &oauth.OAuthService{
		ClientID:     *oauthID,
		ClientSecret: *oauthSecret,
		Scope:        "public_repo",
		AuthURL:      "https://github.com/login/oauth/authorize",
		TokenURL:     "https://github.com/login/oauth/access_token",
		RedirectURL:  *redirectURL,
		AcceptHeader: "application/json",
	}

	assets := map[string]string{}
	json.Unmarshal(readFile("assets.json"), &assets)

	indexHead := readFile("templates/index.html")
	mutex := sync.RWMutex{}
	tarURL := "https://github.com/" + *repository + "/tarball/master"

	// Store repository in map 	
	repos := map[string][]file{}
	repos[*repository] = LoadRepository(tarURL)

	parseTags := func(lines []string) (tags map[string]string, content []string) {
		tags = make(map[string]string)
		for i, l := range lines {
			if strings.Trim(l, " ") == "---" {
				j := i + 1
				for strings.Trim(lines[j], "") != "---" && j < len(lines)-1 {
					tl := strings.Split(lines[j], ":")
					tags[tl[0]] = tl[1]
					j++
				}
				content = lines[j+1:]
				break
			}
		}
		return
	}

	generateTags := func(t string) (tags string) {
		t = strings.Trim(t, "  ")
		ts := strings.Split(t, " ")
		for _, c := range ts {
			tags += "<span data-tag-link='" + c + "'>" + c + "</span>"
		}
		return
	}

	generateTagClasses := func(t string) string {
		t = strings.Trim(t, "  ")
		t = strings.Replace(t, "@", "tag-user-", -1)
		t = strings.Replace(t, "#", "tag-label-", -1)
		return t
	}

	// Build a planfile from a list of files
	buildPlanfile := func(repo []file) (pf string) {
		var rf, e, a string
		var tagList string
		for _, f := range repo {
			tags, content := parseTags(f.content)
			ts := generateTags(tags["tags"])
			tsc := generateTagClasses(tags["tags"])
			tsl := strings.Split(tsc, " ")
			for _, t := range tsl {
				if !strings.Contains(tagList, t) {
					tagList += " " + t
				}
			}
			a = "<div class='tags'><a class='edit' href='#'>Edit</a>" + ts + "</div>"
			original := strings.Join(f.content, "\n")
			entry := strings.Join(content, "\n")
			form := "<form action='.' method='post' style='display:none;'><textarea name='content'>" + original +
				"</textarea><input type='hidden' value='" + f.name + "'/></form>"
			rendered, err := renderMarkdown([]byte(entry))
			if err != nil {
				log.StandardError(err)
				continue
			}
			e = string(rendered)
			if strings.ToLower(f.name) == "readme.md" {
				rf = "<section class='entry readme " + tsc + "'>" + e + a + form + "</section>"
			} else {
				pf += "<section class='entry " + tsc + "'>" + e + a + form + "</section>"
			}
		}
		pf = "<input type='hidden' value='" + tagList + "'/>" + rf + pf
		return
	}

	pf := buildPlanfile(repos[*repository])

	secret := readFile(*cookieKeyFile)
	register := func(path string, handler func(*Context)) {
		http.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			ctx := &Context{
				r:      r,
				w:      w,
				secret: secret,
				secure: *secureMode,
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
		var bc string
		var header string
		username := ctx.GetCookie("user")
		avatarURL := ctx.GetCookie("avatar-url")
		if username != "" {
			bc = "loggedin"
			header = "<div class='container header'><div class='logo'><a id='logo'>planfile</a></div>" +
				"<div class='user_controls'><a id='user'><img src='" + avatarURL + "'><span>" + username +
				"</span></a><div><a href='/logout' id='logout'>Log out</a></div></div></div>"
		} else {
			header = "<div class='container header'><a href='/login' class='button login'>Log in with GitHub</a></div>"
		}
		ctx.Write([]byte("<link href='/static/" + assets["planfile.css"] + "' rel='stylesheet' type='text/css'></head>" +
			"<body data-user='" + username + "' class='" + bc + "'>" + "<div id='body'><div id='home'>" + header +
			"<article class='container planfiles'>" + pf + "</article></div><script src='/static/" + assets["planfile.js"] +
			"' type='text/javascript'></script></body>"))

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
		if !isEqual([]byte(s), []byte(ctx.GetCookie("state"))) {
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
		ctx.SetCookie("avatar-url", user.AvatarURL)
		ctx.Redirect("/")
	})

	register("/refresh", func(ctx *Context) {
		mutex.Lock()
		defer mutex.Unlock()
		repos[*repository] = LoadRepository(tarURL)
		pf = buildPlanfile(repos[*repository])
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
		split := strings.Split(filepath, ".")
		ctype, ok := mimetypes[split[len(split)-1]]
		if !ok {
			ctype = "application/octet-stream"
		}
		if debug {
			register(urlpath, func(ctx *Context) {
				ctx.SetHeader("Content-Type", ctype)
				ctx.Write(readFile(filepath))
			})
		} else {
			content := readFile(filepath)
			register(urlpath, func(ctx *Context) {
				ctx.SetHeader("Content-Type", ctype)
				ctx.Write(content)
			})
		}
	}

	for _, path := range assets {
		registerStatic("static/"+path, "/static/"+path)
	}

	log.Info("Listening on %s", *httpAddr)
	err := http.ListenAndServe(*httpAddr, nil)
	if err != nil {
		runtime.Error("couldn't bind to tcp socket: %s", err)
	}

}
