#!/usr/bin/python

import sys, re

def detokenize_nltk(text):
    text = re.sub(r'-LRB-', '(', text)
    text = re.sub(r'-RRB-', ')', text)
    #text = re.sub(r'\([^\)]+\s[^\)]+\)', ' ', text) # drop parenthesed content
    text = re.sub(r' +', ' ', text)
    text = re.sub(r'^ ', '', text)
    text = re.sub(r' $', '', text)
    text = re.sub(r' ?,( ?,)+ ?', ' ', text)
    #text = re.sub(r'^([^a-zA-Z\d]*)[,;.?!] *', r'\1', text)
    #text = re.sub(r"`` *''", ' ', text)
    #text = re.sub(r" ''", '"', text)
    #text = re.sub(r'`` ', '"', text)
    #text = re.sub(r' \'\'', '"', text)
    text = re.sub(r' n\'t', 'n\'t', text)
    text = re.sub(r' \'t', '\'t', text)
    text = re.sub(r'\$ ([0-9])', r'$\1', text)
    text = re.sub(r" '([sdm]|ll|re|ve)\b", r"'\1", text)
    text = re.sub(r'(\d) , (\d\d\d([^\d]|$))', r'\1,\2', text)
    text = re.sub(r' ([;:,.?!\)\]\}]["\'\)\]\}]?) ', r'\1 ', text)
    ##text = re.sub(r'([\)\]\}]+) ([;:,.?!]+) ', r'\1\2 ', text)
    text = re.sub(r's \' ', r"s' ", text)
    text = re.sub(r'( |^)(["\'\(\[\{]) ([a-zA-Z\d])', r' \2\3', text) # " a => "a
    text = re.sub(r' ([^a-zA-Z\d]+)$', r'\1', text) # " ." => "."
    #text = re.sub(r'"[^a-zA-Z\d]*"', '', text)
    #text = re.sub(r'\([^a-zA-Z\d]*\)', '', text) # (,)
    #text = re.sub(r'\[[^a-zA-Z\d]*\]', '', text)
    #text = re.sub(r'\{[^a-zA-Z\d]*\}', '', text)
    #text = re.sub(r'\'[^a-zA-Z\d]*\'', '', text)
    text = re.sub(' +', ' ', text)
    text = re.sub('^ ', '', text)
    text = re.sub(' $', '', text)
    text = re.sub(' +\.\.\.', '...', text)
    text = re.sub('! !( !)+', '!!!', text)
    text = re.sub(r'\s*[,;]+\s*([.!?]["\'\)\]\}]?|["\'\)\]\}][.!?])$', r'\1', text) # ,. => .

    while re.search(r'[A-Z]\. [A-Z]\.', text):
        text = re.sub(r'\b([A-Z]\.) ([A-Z].)', r'\1\2', text) # A. B. C.
    text = re.sub(r'([A-Z]) & ([A-Z])', r'\1&\2', text) # AT & T
    #text = re.sub(r'([A-Za-z0-9])', (lambda x: x.group(1).capitalize()), text, 1) # ^a => A
    #text = re.sub(r'([a-zA-Z0-9])(["\)\]\}])$', r'\1.\2', text) # a" => a."
    #text = re.sub(r'([a-zA-Z0-9])$', r'\1.', text) # a$ => a.
    #text = re.sub(r'^([^"]*)"([^"]*)$', r'\1\2', text) # lonely quotes
    return text

if __name__ == "__main__":
    for line in sys.stdin:
        print detokenize_nltk(line.strip())
