// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/crypto"
	"amp/httputil"
	"amp/log"
	"amp/oauth"
	"amp/optparse"
	"amp/runtime"
	"amp/tlsconf"
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	debug             bool
	httpClient        = &http.Client{Transport: &http.Transport{TLSClientConfig: tlsconf.Config}}
	instanceDirectory string
	logPath           string
	tripleDash        = []byte("---\n")
)

var (
	CommitNotFound = errors.New("couldn't find the commit for the master branch")
	NotAuthorised  = errors.New("not authorised!")
	TreeNotFound   = errors.New("couldn't find the tree for the master branch")
)

type githubCallFunc func(string, interface{}) error

type Context struct {
	r      *http.Request
	w      http.ResponseWriter
	secret []byte
	secure bool
	token  *oauth.Token
}

func (ctx *Context) Call(path string, v interface{}, post interface{}, patch bool) error {
	var (
		err error
		req *http.Request
	)
	if post != nil {
		body := &bytes.Buffer{}
		enc := json.NewEncoder(body)
		err = enc.Encode(post)
		if err != nil {
			return err
		}
		if patch {
			req, err = http.NewRequest("PATCH", "https://api.github.com"+path, body)
		} else {
			req, err = http.NewRequest("POST", "https://api.github.com"+path, body)
		}
		req.Header.Add("Content-Type", "application/json")
	} else {
		req, err = http.NewRequest("GET", "https://api.github.com"+path, nil)
	}
	if err != nil {
		return err
	}
	if ctx.token == nil {
		token := ctx.GetCookie("token")
		if token == "" {
			return NotAuthorised
		}
		tok, err := hex.DecodeString(token)
		if err != nil {
			ctx.ExpireCookie("token")
			return err
		}
		ctx.token = &oauth.Token{}
		err = json.Unmarshal(tok, ctx.token)
		if err != nil {
			return err
		}
	}
	req.Header.Add("Authorization", "bearer "+ctx.token.AccessToken)
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if post != nil {
		if patch {
			if resp.StatusCode != 200 {
				return errors.New("github call failed: " + path)
			}
		} else if resp.StatusCode != 201 {
			return errors.New("github call failed: " + path)
		}
	}
	dec := json.NewDecoder(resp.Body)
	err = dec.Decode(v)
	return err
}

func (ctx *Context) CreateCallGithub() githubCallFunc {
	return func(path string, v interface{}) error {
		return ctx.Call(path, v, nil, false)
	}
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

func (ctx *Context) IsAuthorised(repo *Repo) bool {
	auth := ctx.GetCookie("auth")
	if auth == "0" {
		return false
	} else if auth == "1" {
		return true
	}
	user := ctx.GetCookie("user")
	if user == "" {
		ctx.SetCookie("auth", "0")
		return false
	}
	resp, err := httpClient.Get("https://api.github.com/repos/" + repo.Path + "/collaborators/" + user)
	if err != nil {
		log.Error("couldn't do authorisation check for %q: %s", user, err)
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != 204 {
		ctx.SetCookie("auth", "0")
		return false
	}
	ctx.SetCookie("auth", "1")
	return true
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

type GzipWriter struct {
	io.Writer
	http.ResponseWriter
}

func (w GzipWriter) Write(b []byte) (int, error) {
	return w.Writer.Write(b)
}

func callGithubAnon(path string, v interface{}) error {
	req, err := http.NewRequest("GET", "https://api.github.com"+path, nil)
	if err != nil {
		return err
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	dec := json.NewDecoder(resp.Body)
	err = dec.Decode(v)
	return err
}

func contains(xs []string, s string) bool {
	for _, e := range xs {
		if e == s {
			return true
		}
	}
	return false
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

func rsplit(s string, sep string) (string, string) {
	i := strings.LastIndex(s, sep)
	if i == -1 {
		return s, ""
	}
	return s[:i], s[i+1:]
}

type Planfile struct {
	Content  string   `json:"content"`
	Depends  []string `json:"depends"`
	Path     string   `json:"path"`
	Rendered string   `json:"rendered"`
	Status   string   `json:"status"`
	Tags     []string `json:"tags"`
	Title    string   `json:"title"`
}

func NewPlanfile(path string, content []byte, callGithub githubCallFunc) (p *Planfile, id string, summary bool, users []string, ok bool) {
	var metadata []byte
	if len(content) >= 4 && bytes.HasPrefix(content, tripleDash) {
		s := bytes.SplitN(content[4:], tripleDash, 2)
		if len(s) == 2 {
			metadata = s[0]
			content = bytes.TrimSpace(s[1])
		}
	}
	p = &Planfile{
		Content: string(content),
		Depends: []string{},
		Path:    path,
		Tags:    []string{},
	}
	if len(metadata) > 0 {
		for _, line := range bytes.Split(metadata, []byte{'\n'}) {
			kv := bytes.SplitN(line, []byte{':'}, 2)
			if len(kv) != 2 {
				continue
			}
			v := bytes.TrimSpace(kv[1])
			if len(v) == 0 {
				continue
			}
			switch string(bytes.TrimSpace(kv[0])) {
			case "id":
				id = string(v)
			case "tags":
				for _, f := range bytes.Split(v, []byte{' '}) {
					tag := strings.TrimRight(string(f), ",")
					if len(tag) < 2 {
						continue
					}
					if tag[0] == '@' {
						users = append(users, strings.ToLower(tag[1:]))
					}
					if tagUpper := strings.ToUpper(tag); tagUpper == tag {
						p.Status = tag
					} else {
						tag = strings.ToLower(tag)
					}
					if strings.HasPrefix(tag, "dep:") && len(tag) > 4 {
						tag = tag[4:]
						if !contains(p.Depends, tag) {
							p.Depends = append(p.Depends, tag)
						}
					} else {
						if !contains(p.Tags, tag) {
							p.Tags = append(p.Tags, tag)
						}
					}
				}
			case "title":
				p.Title = string(v)
			}
		}
		sort.StringSlice(p.Depends).Sort()
		sort.StringSlice(p.Tags).Sort()
	}
	rendered, err := renderMarkdown(content)
	if err != nil {
		log.Error("couldn't render %s: %s", path, err)
		return
	}
	if strings.HasPrefix(path, "summary.") {
		summary = true
		split := strings.Split(path, ".")
		id = strings.Join(split[1:len(split)-1], ".")
	} else if p.Status == "" {
		p.Status = "TODO"
		p.Tags = append(p.Tags, "TODO")
	}
	ok = true
	p.Rendered = string(rendered)
	return
}

type listing struct {
	id    string
	title string
}

type listings []listing

func (s listings) Len() int           { return len(s) }
func (s listings) Less(i, j int) bool { return s[i].title < s[j].title }
func (s listings) Swap(i, j int)      { s[i], s[j] = s[j], s[i] }

type Repo struct {
	Avatars      map[string]string    `json:"avatars"`
	Ordering     []string             `json:"ordering"`
	Planfiles    map[string]*Planfile `json:"planfiles"`
	Path         string               `json:"path"`
	TagMap       map[string][]string  `json:"tag_map"`
	TagSummaries map[string]*Planfile `json:"tag_summaries"`
	Tags         []string             `json:"tags"`
	Title        string               `json:"title"`
	Updated      time.Time            `json:"updated"`
	baseOrder    []string
	info         *RepoInfo
	path2id      map[string]string
	path2plan    map[string]bool
}

func (r *Repo) Exists(path string) bool {
	if path == "" || path == ".md" {
		return true
	}
	path = strings.ToLower(path)
	for _, file := range r.info.Files {
		if strings.ToLower(file) == path {
			return true
		}
	}
	return false
}

func (r *Repo) Load(callGithub githubCallFunc) error {
	log.Info("loading repo: %s", r.Path)
	url := "https://github.com/" + r.Path + "/tarball/master"
	resp, err := httpClient.Get(url)
	if err != nil {
		log.StandardError(err)
		return err
	}
	defer resp.Body.Close()
	zf, err := gzip.NewReader(resp.Body)
	if err != nil {
		log.Error("couldn't find a valid repo tarball at %s -- %s", url, err)
		return err
	}
	tr := tar.NewReader(zf)
	avatars := map[string]string{}
	planfiles := map[string]*Planfile{}
	order := []string{}
	summaries := map[string]*Planfile{}
	path2id := map[string]string{}
	path2plan := map[string]bool{}
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			log.Error("reading tarball: %s", err)
			return err
		}
		filename, ext := rsplit(hdr.Name, ".")
		_, filename = rsplit(filename, "/")
		// Check if the file ends with .md and is not a README file.
		if ext == "md" {
			log.Info("parsing: %s", filename)
			data, err := ioutil.ReadAll(tr)
			if err != nil {
				log.Error("reading tarball file %q: %s", hdr.Name, err)
				continue
			}
			pf, id, summary, userRefs, ok := NewPlanfile(filename+".md", data, callGithub)
			if !ok {
				continue
			}
			if strings.ToLower(filename) == "readme" {
				summaries["/"] = pf
			} else if summary {
				summaries[id] = pf
				path2id[filename+".md"] = id
				path2plan[filename+".md"] = false
			} else {
				if id == "" {
					log.Error("ID not found for: %s", filename)
					id = filename
				}
				planfiles[id] = pf
				path2id[filename+".md"] = id
				path2plan[filename+".md"] = true
			}
			for _, username := range userRefs {
				if _, ok := avatars[username]; !ok {
					user := &User{}
					err = callGithub("/users/"+username, user)
					if err == nil {
						avatars[username] = user.AvatarURL
					} else {
						log.Error("couldn't load github user info for %q: %s", username, err)
						avatars[username] = "https://assets.github.com/images/gravatars/gravatar-140.png"
					}
				}
			}
		} else if ext == "order" && filename == "" {
			log.Info("parsing: .order")
			data, err := ioutil.ReadAll(tr)
			if err != nil {
				log.Error("reading tarball file %q: %s", hdr.Name, err)
				continue
			}
			order = strings.Split(string(bytes.TrimSpace(data)), "\n")
		}
	}
	log.Info("post-processing repo: %s", r.Path)
	baseOrder := []string{}
	for _, id := range order {
		if _, ok := planfiles[id]; ok {
			baseOrder = append(baseOrder, id)
		}
	}
	r.baseOrder = baseOrder
	r.Avatars = avatars
	r.Planfiles = planfiles
	r.TagSummaries = summaries
	r.info = nil
	r.path2id = path2id
	r.path2plan = path2plan
	r.UpdateOrdering()
	r.UpdateTags()
	log.Info("successfully loaded repo: %s", r.Path)
	return nil
}

func (r *Repo) RefreshSingle(path string, content []byte, update bool, callGithub githubCallFunc) {
	pf, id, summary, _, ok := NewPlanfile(path, content, callGithub)
	if !ok {
		return
	}
	if update {
		if isPlan, ok := r.path2plan[path]; ok {
			if isPlan {
				delete(r.Planfiles, r.path2id[path])
			} else {
				delete(r.TagSummaries, r.path2id[path])
			}
			delete(r.path2id, path)
			delete(r.path2plan, path)
		}
	}
	if strings.ToLower(path) == "readme.md" {
		r.TagSummaries["/"] = pf
	} else if summary {
		r.TagSummaries[id] = pf
		r.path2id[path] = id
		r.path2plan[path] = false
	} else {
		r.Planfiles[id] = pf
		r.path2id[path] = id
		r.path2plan[path] = true
	}
	r.info = nil
	r.UpdateOrdering()
	r.UpdateTags()
}

func (r *Repo) Modify(ctx *Context, path, content, message string) error {
	tree := &CommitTree{}
	if err := ctx.Call("/repos/"+r.Path+"/git/trees", tree, &TreeUpdate{
		Base: r.info.Tree,
		Elems: []*TreeElem{{
			Content: content,
			Mode:    "100644",
			Path:    path,
			Type:    "blob",
		}},
	}, false); err != nil {
		return err
	}
	if tree.SHA == "" {
		return errors.New("couldn't save tree to github: " + path)
	}
	commit := &CommitTree{}
	if err := ctx.Call("/repos/"+r.Path+"/git/commits", commit, &CommitUpdate{
		Message: message,
		Parents: []string{r.info.Commit},
		Tree:    tree.SHA,
	}, false); err != nil {
		return err
	}
	if commit.SHA == "" {
		return errors.New("couldn't save commit to github: " + path)
	}
	ref := &Ref{}
	if err := ctx.Call("/repos/"+r.Path+"/git/refs/heads/master", ref, &RefUpdate{
		SHA: commit.SHA,
	}, true); err != nil {
		return err
	}
	if ref.Object.SHA == "" {
		return errors.New("couldn't update master on github: " + path)
	}
	return nil
}

func (r *Repo) UpdateInfo(callGithub githubCallFunc) error {
	if r.info != nil {
		return nil
	}
	master := &Ref{}
	if err := callGithub("/repos/"+r.Path+"/git/refs/heads/master", master); err != nil {
		return err
	}
	if master.Object == nil || master.Object.SHA == "" {
		return CommitNotFound
	}
	commit := &Commit{}
	if err := callGithub("/repos/"+r.Path+"/git/commits/"+master.Object.SHA, commit); err != nil {
		return err
	}
	if commit.Tree == nil || commit.Tree.SHA == "" {
		return TreeNotFound
	}
	tree := &Tree{}
	if err := callGithub("/repos/"+r.Path+"/git/trees/"+commit.Tree.SHA, tree); err != nil {
		return err
	}
	files := []string{}
	for _, elem := range tree.Elems {
		if elem.Path == "" {
			continue
		}
		files = append(files, strings.ToLower(elem.Path))
	}
	r.info = &RepoInfo{
		Commit: master.Object.SHA,
		Files:  files,
		Tree:   commit.Tree.SHA,
	}
	return nil
}

func (r *Repo) UpdateOrdering() {
	extra := listings{}
	for id, pf := range r.Planfiles {
		if !contains(r.baseOrder, id) {
			if pf.Title == "" {
				extra = append(extra, listing{id, id})
			} else {
				extra = append(extra, listing{id, strings.ToLower(pf.Title)})
			}
		}
	}
	sort.Sort(extra)
	r.Ordering = make([]string, 0, len(r.baseOrder)+len(extra))
	copy(r.Ordering, r.baseOrder)
	for _, elem := range extra {
		r.Ordering = append(r.Ordering, elem.id)
	}
}

func (r *Repo) UpdateTags() {
	tagMap := map[string][]string{}
	for id, f := range r.Planfiles {
		for _, tag := range f.Tags {
			tagMap[tag] = append(tagMap[tag], id)
		}
	}
	i := 0
	tags := make([]string, len(tagMap))
	for tag, tagList := range tagMap {
		sort.StringSlice(tagList).Sort()
		tags[i] = tag
		i += 1
	}
	sort.StringSlice(tags).Sort()
	r.TagMap = tagMap
	r.Tags = tags
}

type Commit struct {
	Tree *CommitTree `json:"tree"`
}

type CommitTree struct {
	SHA string `json:"sha"`
}

type CommitUpdate struct {
	Message string   `json:"message"`
	Parents []string `json:"parents"`
	Tree    string   `json:"tree"`
}

type RefInfo struct {
	SHA  string `json:"sha"`
	Type string `json:"type"`
}

type Ref struct {
	Object *RefInfo `json:"object"`
}

type RefUpdate struct {
	SHA string `json:"sha"`
}

type RepoInfo struct {
	Commit string
	Files  []string
	Tree   string
}

type Tree struct {
	Elems []*TreeElem `json:"tree"`
}

type TreeElem struct {
	Content string `json:"content"`
	Path    string `json:"path"`
	Mode    string `json:"mode"`
	Type    string `json:"type"`
}

type TreeUpdate struct {
	Base  string      `json:"base_tree"`
	Elems []*TreeElem `json:"tree"`
}

type User struct {
	AvatarURL string `json:"avatar_url"`
	Login     string `json:"login"`
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

	redirectURL := opts.StringConfig("redirect-url", "/.oauth",
		"the redirect url for handling oauth [/.oauth]")

	repository := opts.StringConfig("repository", "",
		"the username/repository on github", true)

	secureMode := opts.BoolConfig("secure-mode", false,
		"enable hsts and secure cookies [false]")

	title := opts.StringConfig("title", "Planfile",
		"the title for the web app [Planfile]")

	refreshOpt := opts.IntConfig("refresh-interval", 1,
		"the number of through-the-web edits before a full refresh [1]")

	debug, instanceDirectory, _, logPath = runtime.DefaultOpts("planfile", opts, os.Args)

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
	setupPygments()

	mutex := sync.RWMutex{}
	repo := &Repo{Path: *repository}

	err := repo.Load(callGithubAnon)
	if err != nil {
		runtime.Exit(1)
	}

	repo.Title = *title
	repo.Updated = time.Now().UTC()
	repoJSON, err := json.Marshal(repo)
	if err != nil {
		runtime.StandardError(err)
	}

	refreshCount := 0
	refreshInterval := *refreshOpt

	secret := readFile(*cookieKeyFile)
	newContext := func(w http.ResponseWriter, r *http.Request) *Context {
		return &Context{
			r:      r,
			w:      w,
			secret: secret,
			secure: *secureMode,
		}
	}

	register := func(path string, handler func(*Context), usegzip ...bool) {
		gzippable := len(usegzip) > 0 && usegzip[0]
		http.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			log.Info("serving %s", r.URL)
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			if gzippable && httputil.Parse(r, "Accept-Encoding").Accepts("gzip") {
				buf := &bytes.Buffer{}
				enc := gzip.NewWriter(buf)
				handler(newContext(GzipWriter{enc, w}, r))
				enc.Close()
				w.Header().Set("Content-Encoding", "gzip")
				w.Header().Set("Content-Length", strconv.Itoa(buf.Len()))
				buf.WriteTo(w)
			} else {
				handler(newContext(w, r))
			}
		})
	}

	anon := []byte(", null, null, '', false")
	authFalse := []byte("', false")
	authTrue := []byte("', true")

	header := []byte(`<!doctype html>
<meta charset=utf-8>
<title>` + html.EscapeString(*title) + `</title>
<link href="//fonts.googleapis.com/css?family=Abel|Coustard:400" rel=stylesheet>
<link href=/.static/` + assets["planfile.css"] + ` rel=stylesheet>
<body><script>DATA = ['` + *gaHost + `', '` + *gaID + `', `)

	footer := []byte(`];</script>
<script src=/.static/` + assets["planfile.js"] + `></script>
<noscript>Sorry, your browser needs <a href=http://enable-javascript.com>JavaScript enabled</a>.</noscript>
`)

	register("/", func(ctx *Context) {
		mutex.RLock()
		defer mutex.RUnlock()
		ctx.Write(header)
		ctx.Write(repoJSON)
		avatar := ctx.GetCookie("avatar")
		user := ctx.GetCookie("user")
		if avatar != "" && user != "" {
			ctx.Write([]byte(", '" + user + "', '" + avatar + "', '" + ctx.GetCookie("xsrf")))
			if ctx.IsAuthorised(repo) {
				ctx.Write(authTrue)
			} else {
				ctx.Write(authFalse)
			}
		} else {
			ctx.Write(anon)
		}
		ctx.Write(footer)
	}, true)

	register("/.api", func(ctx *Context) {
		mutex.RLock()
		defer mutex.RUnlock()
		if cb := ctx.FormValue("callback"); cb != "" {
			ctx.Write([]byte(cb))
			ctx.Write([]byte{'('})
			ctx.Write(repoJSON)
			ctx.Write([]byte{')', ';'})
		} else {
			ctx.Write(repoJSON)
		}
	}, true)

	register("/.login", func(ctx *Context) {
		b := make([]byte, 20)
		if n, err := rand.Read(b); err != nil || n != 20 {
			ctx.Error("Couldn't access cryptographic device", err)
			return
		}
		s := hex.EncodeToString(b)
		ctx.SetCookie("xsrf", s)
		ctx.Redirect(service.AuthCodeURL(s))
	})

	register("/.logout", func(ctx *Context) {
		ctx.ExpireCookie("auth")
		ctx.ExpireCookie("avatar")
		ctx.ExpireCookie("token")
		ctx.ExpireCookie("user")
		ctx.ExpireCookie("xsrf")
		ctx.Redirect("/")
	})

	notAuthorised := []byte("ERROR: Not Authorised!")

	savedHeader := []byte(`<!doctype html>
<meta charset=utf-8>
<title>` + html.EscapeString(*title) + `</title>
<body><script>SAVED="`)

	savedFooter := []byte(`"</script><script src=/.static/` + assets["planfile.js"] + `></script>`)

	exportRepo := func(ctx *Context) bool {
		repo.Updated = time.Now().UTC()
		repoJSON, err = json.Marshal(repo)
		if err != nil {
			ctx.Error("Couldn't encode repo data during refresh", err)
			return false
		}
		return true
	}

	refresh := func(ctx *Context) {
		err := repo.Load(ctx.CreateCallGithub())
		if err != nil {
			log.Error("couldn't rebuild planfile info: %s", err)
			ctx.Write([]byte("ERROR: " + err.Error()))
			return
		}
		exportRepo(ctx)
	}

	saveItem := func(ctx *Context, update bool) {
		mutex.Lock()
		defer mutex.Unlock()
		if !ctx.IsAuthorised(repo) {
			ctx.Write(notAuthorised)
			return
		}
		if !isEqual([]byte(ctx.FormValue("xsrf")), []byte(ctx.GetCookie("xsrf"))) {
			ctx.Write(notAuthorised)
			return
		}
		err := repo.UpdateInfo(ctx.CreateCallGithub())
		if err != nil {
			ctx.Error("Couldn't update repo info", err)
			return
		}
		var id, path, message string
		if update {
			id = ctx.FormValue("id")
			path = ctx.FormValue("path")
		} else {
			baseID := ctx.FormValue("id")
			id = baseID
			count := 0
			for repo.Exists(id + ".md") {
				count += 1
				id = fmt.Sprintf("%s%d", baseID, count)
			}
			path = id + ".md"
		}
		content := strings.Replace(ctx.FormValue("content"), "\r\n", "\n", -1)
		tags := ctx.FormValue("tags")
		title := ctx.FormValue("title")
		redir := "/"
		if ctx.FormValue("summary") == "yes" {
			if id != "/" {
				content = fmt.Sprintf(`---
title: %s
---

%s`, title, content)
				if strings.HasPrefix(id, "summary.") {
					redir = "/" + id[8:]
				} else {
					// Shouldn't ever happen. But just in case...
					redir = "/" + id
				}
			}
		} else {
			redir = "/.item." + id
			content = fmt.Sprintf(`---
id: %s
tags: %s
title: %s
---

%s`, id, tags, title, content)
		}
		if title == "" {
			title = id
		}
		if update {
			message = "Updated: " + title
		} else {
			message = "Added: " + title
		}
		log.Info("SAVE PATH: %q for ID %q", path, id)
		err = repo.Modify(ctx, path, content, message)
		if err != nil {
			if update {
				ctx.Error("<a href='/.refresh'>Try refreshing.</a> Couldn't update item", err)
			} else {
				ctx.Error("<a href='/.refresh'>Try refreshing.</a> Couldn't save new item", err)
			}
			return
		}
		refreshCount++
		if refreshCount%refreshInterval == 0 {
			refresh(ctx)
		} else {
			repo.RefreshSingle(path, []byte(content), update, ctx.CreateCallGithub())
			if !exportRepo(ctx) {
				return
			}
		}
		ctx.Write(savedHeader)
		ctx.Write([]byte(html.EscapeString(redir)))
		ctx.Write(savedFooter)
	}

	register("/.modify", func(ctx *Context) {
		saveItem(ctx, true)
	})

	register("/.new", func(ctx *Context) {
		saveItem(ctx, false)
	})

	register("/.oauth", func(ctx *Context) {
		s := ctx.FormValue("state")
		if s == "" {
			ctx.Redirect("/.login")
			return
		}
		if !isEqual([]byte(s), []byte(ctx.GetCookie("xsrf"))) {
			ctx.ExpireCookie("xsrf")
			ctx.Redirect("/.login")
			return
		}
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
		err = ctx.Call("/user", user, nil, false)
		if err != nil {
			ctx.Error("Couldn't load user info", err)
			return
		}
		ctx.SetCookie("avatar", user.AvatarURL)
		ctx.SetCookie("user", user.Login)
		ctx.Redirect("/")
	})

	register("/.preview", func(ctx *Context) {
		rendered, err := renderMarkdown([]byte(ctx.FormValue("content")))
		if err != nil {
			ctx.Error("Couldn't render Markdown", err)
			return
		}
		ctx.Write(rendered)
	}, true)

	register("/.refresh", func(ctx *Context) {
		if !ctx.IsAuthorised(repo) {
			ctx.Write(notAuthorised)
			return
		}
		mutex.Lock()
		defer mutex.Unlock()
		refresh(ctx)
		ctx.Redirect("/")
	})

	mimetypes := map[string]string{
		"css":  "text/css",
		"gif":  "image/gif",
		"ico":  "image/x-icon",
		"jpeg": "image/jpeg",
		"jpg":  "image/jpeg",
		"js":   "text/javascript",
		"png":  "image/png",
		"swf":  "application/x-shockwave-flash",
		"txt":  "text/plain",
	}

	registerStatic := func(filepath, urlpath string) {
		_, ext := rsplit(filepath, ".")
		ctype, ok := mimetypes[ext]
		if !ok {
			ctype = "application/octet-stream"
		}
		if debug {
			register(urlpath, func(ctx *Context) {
				ctx.SetHeader("Content-Type", ctype)
				ctx.Write(readFile(filepath))
			}, strings.HasPrefix(ctype, "text/"))
		} else {
			content := readFile(filepath)
			register(urlpath, func(ctx *Context) {
				ctx.SetHeader("Cache-Control", "public, max-age=86400")
				ctx.SetHeader("Content-Type", ctype)
				ctx.Write(content)
			}, strings.HasPrefix(ctype, "text/"))
		}
	}

	for _, path := range assets {
		registerStatic(filepath.Join(instanceDirectory, "static", path), "/.static/"+path)
	}

	wwwPath := filepath.Join(instanceDirectory, "www")
	if files, err := ioutil.ReadDir(wwwPath); err == nil {
		for _, file := range files {
			if !file.IsDir() {
				registerStatic(filepath.Join(wwwPath, file.Name()), "/"+file.Name())
			}
		}
	}

	log.Info("Listening on %s", *httpAddr)
	server := &http.Server{
		Addr:         *httpAddr,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}
	err = server.ListenAndServe()
	if err != nil {
		runtime.Error("couldn't bind to tcp socket: %s", err)
	}

}
