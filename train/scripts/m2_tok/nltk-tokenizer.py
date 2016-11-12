#!/usr/bin/python

import sys
import argparse
import nltk


parser = argparse.ArgumentParser()
parser.add_argument("-l", "--language", help="set language, default: english", default="english")
parser.add_argument("-i", "--line-by-line", help="assume one sentence per line", action="store_true")
parser.add_argument("--nltk-data", help="path to NLTK data", required=True)
args = parser.parse_args()

nltk.data.path.append(args.nltk_data)

segmentizer = nltk.data.load('tokenizers/punkt/%s.pickle' % args.language)

if args.line_by_line:
    for line in sys.stdin:
        print " ".join(nltk.word_tokenize(line.strip()))
else:
    for line in sys.stdin:
        for sentence in segmentizer.tokenize(line.lstrip()):
            print " ".join(nltk.word_tokenize(sentence))
