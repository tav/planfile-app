#! /usr/bin/env python

# Public Domain (-) 2012 The Planfile App Authors.
# See the Planfile App UNLICENSE file for details.

from cgi import escape
from datetime import datetime
from os.path import join
from struct import pack, unpack
from sys import argv, stdin, stdout
from traceback import print_exc

from pygments import highlight
from pygments.formatters import HtmlFormatter
from pygments.lexers import get_lexer_by_name, TextLexer

DEBUG = argv[2] == "true"
if DEBUG:
    f = open(join(argv[1], 'hilite.log'), 'a+b')

while 1:
    try:
        lang = stdin.read(unpack('!I', stdin.read(4))[0])
        text = unicode(stdin.read(unpack('!I', stdin.read(4))[0]), 'utf-8')
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
            f.write("---------------------------------\n")
            f.write("ERROR: %s\n" % datetime.utcnow())
            f.write("---------------------------------\n")
            print_exc(100, f)
            f.close()
        break
