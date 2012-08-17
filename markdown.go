// Public Domain (-) 2012 The Planfile App Authors.
// See the Planfile App UNLICENSE file for details.

package main

import (
	"amp/runtime"
	"bytes"
	"encoding/binary"
	"github.com/russross/blackfriday"
	"html"
	"io"
	"os"
	"sync"
)

const (
	DefaultExtensions = blackfriday.EXTENSION_NO_INTRA_EMPHASIS | blackfriday.EXTENSION_TABLES | blackfriday.EXTENSION_FENCED_CODE | blackfriday.EXTENSION_AUTOLINK | blackfriday.EXTENSION_STRIKETHROUGH | blackfriday.EXTENSION_SPACE_HEADERS
	DefaultHtmlFlags  = blackfriday.HTML_USE_SMARTYPANTS | blackfriday.HTML_SMARTYPANTS_FRACTIONS
)

var hilite *Hilite

type Html struct {
	i blackfriday.Renderer
}

func (r *Html) BlockCode(out *bytes.Buffer, text []byte, lang string) {
	if out.Len() > 0 {
		out.WriteByte('\n')
	}
	if lang == "" {
		out.Write([]byte(`<div class="syntax"><pre>`))
		out.Write([]byte(html.EscapeString(string(text))))
		out.Write([]byte("</pre></div>"))
	} else {
		hilited, err := hilite.Render(lang, text)
		if err != nil {
			panic(err)
		}
		out.Write(hilited)
	}
}

func (r *Html) BlockQuote(out *bytes.Buffer, text []byte) {
	r.i.BlockQuote(out, text)
}

func (r *Html) BlockHtml(out *bytes.Buffer, text []byte) {
	r.i.BlockHtml(out, text)
}

func (r *Html) Header(out *bytes.Buffer, text func() bool, level int) {
	r.i.Header(out, text, level)
}

func (r *Html) HRule(out *bytes.Buffer) {
	r.i.HRule(out)
}

func (r *Html) List(out *bytes.Buffer, text func() bool, flags int) {
	r.i.List(out, text, flags)
}

func (r *Html) ListItem(out *bytes.Buffer, text []byte, flags int) {
	r.i.ListItem(out, text, flags)
}

func (r *Html) Paragraph(out *bytes.Buffer, text func() bool) {
	r.i.Paragraph(out, text)
}

func (r *Html) Table(out *bytes.Buffer, header []byte, body []byte, columnData []int) {
	r.i.Table(out, header, body, columnData)
}

func (r *Html) TableRow(out *bytes.Buffer, text []byte) {
	r.i.TableRow(out, text)
}

func (r *Html) TableCell(out *bytes.Buffer, text []byte, flags int) {
	r.i.TableCell(out, text, flags)
}

func (r *Html) AutoLink(out *bytes.Buffer, link []byte, kind int) {
	r.i.AutoLink(out, link, kind)
}

func (r *Html) CodeSpan(out *bytes.Buffer, text []byte) {
	r.i.CodeSpan(out, text)
}

func (r *Html) DoubleEmphasis(out *bytes.Buffer, text []byte) {
	r.i.DoubleEmphasis(out, text)
}

func (r *Html) Emphasis(out *bytes.Buffer, text []byte) {
	r.i.Emphasis(out, text)
}

func (r *Html) Image(out *bytes.Buffer, link []byte, title []byte, alt []byte) {
	r.i.Image(out, link, title, alt)
}

func (r *Html) LineBreak(out *bytes.Buffer) {
	r.i.LineBreak(out)
}

func (r *Html) Link(out *bytes.Buffer, link []byte, title []byte, content []byte) {
	r.i.Link(out, link, title, content)
}

func (r *Html) RawHtmlTag(out *bytes.Buffer, tag []byte) {
	r.i.RawHtmlTag(out, tag)
}

func (r *Html) TripleEmphasis(out *bytes.Buffer, text []byte) {
	r.i.TripleEmphasis(out, text)
}

func (r *Html) StrikeThrough(out *bytes.Buffer, text []byte) {
	r.i.StrikeThrough(out, text)
}

func (r *Html) Entity(out *bytes.Buffer, entity []byte) {
	r.i.Entity(out, entity)
}

func (r *Html) NormalText(out *bytes.Buffer, text []byte) {
	r.i.NormalText(out, text)
}

func (r *Html) DocumentHeader(out *bytes.Buffer) {
	r.i.DocumentHeader(out)
}

func (r *Html) DocumentFooter(out *bytes.Buffer) {
	r.i.DocumentFooter(out)
}

func renderMarkdown(input []byte) (out []byte, err error) {
	defer func() {
		if e := recover(); e != nil {
			if e, ok := e.(error); ok {
				err = e
			}
		}
	}()
	r := &Html{blackfriday.HtmlRenderer(DefaultHtmlFlags, "", "")}
	out = blackfriday.Markdown(input, r, DefaultExtensions)
	return
}

type Hilite struct {
	r *os.File
	m sync.Mutex
	p *os.Process
	w *os.File
}

func (h *Hilite) Close() {
	h.p.Kill()
}

func (h *Hilite) Render(lang string, text []byte) ([]byte, error) {
	h.m.Lock()
	defer h.m.Unlock()
	size := make([]byte, 4)
	binary.BigEndian.PutUint32(size, uint32(len(lang)))
	h.w.Write(size)
	h.w.Write([]byte(lang))
	binary.BigEndian.PutUint32(size, uint32(len(text)))
	h.w.Write(size)
	h.w.Write(text)
	_, err := io.ReadAtLeast(h.r, size, 4)
	if err != nil {
		return nil, err
	}
	length := binary.BigEndian.Uint32(size)
	if length == 0 {
		return nil, io.EOF
	}
	out := make([]byte, length)
	_, err = io.ReadAtLeast(h.r, out, int(length))
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (h *Hilite) Run() {
	stdin, w, _ := os.Pipe()
	r, stdout, _ := os.Pipe()
	h.r = r
	h.w = w
	proc, err := os.StartProcess("hilite.py", []string{runPath + "/hilite.py"}, &os.ProcAttr{
		Files: []*os.File{stdin, stdout, nil},
	})
	if err != nil {
		runtime.StandardError(err)
	}
	h.p = proc
	proc.Wait()
}

func setupPygments() {
	if hilite != nil {
		hilite.m.Lock()
		hilite.Close()
		hilite.m.Unlock()
	}
	hilite = &Hilite{}
	go hilite.Run()
}
