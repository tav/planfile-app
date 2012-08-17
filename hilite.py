#! /usr/bin/env python

# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

from cgi import escape
from struct import pack, unpack
from sys import stdin, stdout
from traceback import print_exc

from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name, TextLexer

DEBUG = 0

if DEBUG:
    f = open('error.log', 'wb')

while 1:
    try:
        length = stdin.read(4)
        lang = stdin.read(unpack('!I', length)[0])
        length = stdin.read(4)
        text = unicode(stdin.read(unpack('!I', length)[0]), 'utf-8')
        try:
            lexer = get_lexer_by_name(lang)
        except ValueError:
            lang = 'txt'
            lexer = TextLexer()
        formatter = HtmlFormatter(cssclass='syntax %s' % lang, lineseparator='<br/>')
        text = highlight(text, lexer, formatter).decode('utf-8')
        stdout.write(pack('!I', len(text)))
        stdout.write(text)
        stdout.flush()
    except Exception, err:
        if DEBUG:
            print_exc(100, f)
            f.flush()
