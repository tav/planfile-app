// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/yaml"
	"fmt"
	"log"
	"net/http"
	"os"
)

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
}

var config = &Config{}

func main() {

	cfg, err := yaml.ParseFile("config.yaml")
	if err != nil {
		log.Fatal("ERROR: couldn't parse the config file: ", err)
	}

	cfg.LoadStruct(config)
	if config.LocalDirectory != "" {
		config.UseLocal = true
	}

	http.HandleFunc("/", hello)

	err = http.ListenAndServe(":"+os.Getenv("PORT"), nil)
	if err != nil {
		log.Fatal("ERROR: couldn't bind to tcp socket: ", err)
	}

}

func hello(w http.ResponseWriter, req *http.Request) {
	fmt.Fprintln(w, "hello, world!\n")
	fmt.Fprintf(w, "%#v", config)
}
