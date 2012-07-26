// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/oauth"
	"amp/yaml"
	"bufio"
	"bytes"
	"crypto/rand"
	"crypto/sha1"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"io/ioutil"
	"log"
	"math/big"
	"net/http"
	"os"
	"strconv"
)

const (
	STATIC_DIR     = "../static"
	ASSETS_JSON    = "../assets.json"
	GITHUB_URL     = "https://api.github.com/"
	SESSION_COOKIE = "planfile_session_id"
	TEMPLATES_DIR  = "../templates"
)

var userSessions = map[string]bool{}
var usersLoggedIn = map[string]*User{}
var userTokens = map[string]*oauth.Token{}

// Returns a securely generated random string.
func getRandomString(l int) string {
	allowedChars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var buffer bytes.Buffer
	for i := 0; i < l; i++ {
		j, _ := rand.Int(rand.Reader, big.NewInt(int64(len(allowedChars))))
		buffer.WriteString(string(allowedChars[j.Int64()]))
	}
	return buffer.String()
}

// -----------------------------------------------------------------------------
// Asset loader
// -----------------------------------------------------------------------------

type Assets struct {
	CSS string `json:"planfile.css"`
	JS  string `json:"planfile.js"`
}

var assets = Assets{}

func loadAssets(path string) Assets {
	file, err := os.Open(path)
	if err != nil {
		log.Fatal(err)
	}
	reader := bufio.NewReader(file)
	b, err := ioutil.ReadAll(reader)
	if err != nil {
		log.Fatal(err)
	}
	assets := Assets{}
	json.Unmarshal(b, &assets)
	return assets
}

// -----------------------------------------------------------------------------
// Templates
// -----------------------------------------------------------------------------

var templates = template.Must(template.ParseFiles(TEMPLATES_DIR+"/index.html", TEMPLATES_DIR+"/plan.html"))

func renderTemplate(w http.ResponseWriter, tmpl string, c interface{}) {
	err := templates.ExecuteTemplate(w, tmpl+".html", c)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

// -----------------------------------------------------------------------------
// Core web app
// -----------------------------------------------------------------------------

type Config struct {
	Debug               bool
	GoogleAnalyticsHost string
	GoogleAnalyticsID   string
	LocalDirectory      string
	OAuthClientID       string
	OAuthClientSecret   string
	Repository          string
	UseLocal            bool
	TypekitID           string
	RedirectURL         string
}

var config = &Config{}

var service = &oauth.OAuthService{}

// Set session cookie if it doesn't exist
func setSessionIDCookie(w http.ResponseWriter, r *http.Request) (string, error) {
	id, err := r.Cookie(SESSION_COOKIE)
	if err != nil {
		randID := getRandomString(16)
		c := &http.Cookie{Name: SESSION_COOKIE, Value: randID}
		http.SetCookie(w, c)
		userSessions[randID] = true
		userTokens[randID] = &oauth.Token{}
		return randID, nil
	}
	return id.Value, nil
}

// Index
func index(w http.ResponseWriter, r *http.Request) {
	sessionID, _ := setSessionIDCookie(w, r)
	_, ok := usersLoggedIn[sessionID]
	if userSessions[sessionID] && ok {
		//		csrfToken := r.FormValue("crsf_token")
		//		title := r.FormValue("title")
		entry := r.FormValue("entry")
		//		planfileID := r.FormValue("planfile")
		//fmt.Println(csrfToken, title, getGitSHA(entry), planfileID)
		userToken := userTokens[sessionID]
		user := fetchUser(userToken)
		sha := githubBlobsCreate(userToken, user.Login, "planfile", entry)
		fmt.Println("sha: ", sha)
		page := struct {
			CSS   string
			JS    string
			CSRF  string
			Title string
			User  *User
		}{
			assets.CSS,
			assets.JS,
			"",
			"Hi",
			user,
		}
		renderTemplate(w, "index", page)
	} else {
		page := struct {
			CSS   string
			JS    string
			CSRF  string
			Title string
			User  *User
		}{
			assets.CSS,
			assets.JS,
			"",
			"Welcome to Planfile",
			nil,
		}
		renderTemplate(w, "index", page)
	}
}

// Load session identifier and redirect to OAuth backend
func login(w http.ResponseWriter, r *http.Request) {
	id, err := r.Cookie(SESSION_COOKIE)
	if err == nil {
		http.Redirect(w, r, service.AuthCodeURL(id.Value), http.StatusFound)
	}
}

// OAuth redirect URL.
func authenticate(w http.ResponseWriter, r *http.Request) {
	t := &oauth.Transport{OAuthService: service}
	id, err := r.Cookie(SESSION_COOKIE)
	if err == nil && r.FormValue("state") == id.Value {
		tok, err := t.ExchangeAuthorizationCode(r.FormValue("code"))
		if err != nil {
			log.Fatal("ERROR: ", err)
		}
		userSessions[id.Value] = true
		userTokens[id.Value] = tok
		user := fetchUser(userTokens[id.Value])
		usersLoggedIn[id.Value] = user
	}
	http.Redirect(w, r, "/", http.StatusFound)
}

// Log out user
func logout(w http.ResponseWriter, r *http.Request) {
	id, err := r.Cookie(SESSION_COOKIE)
	if err == nil {
		delete(userSessions, id.Value)
		delete(userTokens, id.Value)
		delete(usersLoggedIn, id.Value)
	}
	http.Redirect(w, r, "/", http.StatusFound)
}

// Planfile loading URL
func plan(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "Plan")
}

// -----------------------------------------------------------------------------
// URL Routes
// -----------------------------------------------------------------------------

func main() {

	cfg, err := yaml.ParseFile("config.yaml")
	if err != nil {
		log.Fatal("ERROR: couldn't parse the config file: ", err)
	}
	cfg.LoadStruct(config)
	if config.LocalDirectory != "" {
		config.UseLocal = true
	}

	service = &oauth.OAuthService{
		ClientID:     config.OAuthClientID,
		ClientSecret: config.OAuthClientSecret,
		Scope:        "public_repo",
		AuthURL:      "https://github.com/login/oauth/authorize",
		TokenURL:     "https://github.com/login/oauth/access_token",
		RedirectURL:  config.RedirectURL,
		AcceptHeader: "application/json",
	}

	assets = loadAssets(ASSETS_JSON)
	http.HandleFunc("/", index)
	http.HandleFunc("/login", login)
	http.HandleFunc("/logout", logout)
	http.HandleFunc("/oauth", authenticate)
	http.HandleFunc("/plan", plan)
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir("../static/"))))
	fmt.Println("LISTENING...")

	err = http.ListenAndServe(":"+os.Getenv("PORT"), nil)
	if err != nil {
		log.Fatal("ERROR: couldn't bind to tcp socket: ", err)
	}

}

// -----------------------------------------------------------------------------
// GitHub API functions
// -----------------------------------------------------------------------------

func makeGitHubCall(t *oauth.Token, req *http.Request) *bytes.Buffer {
	client := &http.Client{}
	req.Header.Add("Authorization", "bearer "+t.AccessToken)
	resp, err := client.Do(req)
	if err != nil {
		log.Fatal("Error: ", err)
	}
	defer resp.Body.Close()
	buf := &bytes.Buffer{}
	io.Copy(buf, resp.Body)
	return buf
}

type User struct {
	Id        int    `json:"id"`
	Login     string `json:"login"`
	AvatarURL string `json:"avatar_url"`
	Name      string `json:"name"`
}

func fetchUser(t *oauth.Token) *User {
	u := &User{}
	req, _ := http.NewRequest("GET", GITHUB_URL+"user", nil)
	buf := makeGitHubCall(t, req)
	json.Unmarshal(buf.Bytes(), &u)
	return u
}

func githubBlobsCreate(t *oauth.Token, user, repo, content string) string {
	blob := struct {
		Content  string `json:"content"`
		Encoding string `json:"encoding"`
	}{
		content,
		"utf-8",
	}
	buf := &bytes.Buffer{}
	resp := struct {
		Sha string
	}{}
	b, _ := json.Marshal(blob)
	io.Copy(buf, bytes.NewBuffer(b))
	URL := GITHUB_URL + "repos/" + user + "/" + repo + "/git/blobs"
	fmt.Println("URL: ", URL)
	req, _ := http.NewRequest("POST", URL, buf)
	fmt.Println("buf: ", buf.String())
	req.Header.Set("Content-Type", "application/json")
	buf2 := makeGitHubCall(t, req)
	fmt.Println("buf2: ", buf2.String())
	json.Unmarshal(buf2.Bytes(), &resp)
	return resp.Sha
}

// -----------------------------------------------------------------------------
// Git functions
// -----------------------------------------------------------------------------

func getGitSHA(data string) string {
	h := sha1.New()
	io.WriteString(h, "blob "+strconv.Itoa(len(data)+1)+"\x00"+data+"\n")
	return fmt.Sprintf("% x", h.Sum(nil))
}
