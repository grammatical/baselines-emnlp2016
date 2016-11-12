#!/usr/bin/python

import re
import sys
import operator
import subprocess
import argparse
import os

from joblib import Parallel, delayed

from diff_finder import edited_tokens
from detokenize import detokenize_nltk


MOSES_TOK = "%s/scripts/tokenizer/tokenizer.perl 2> /dev/null"
MOSES_DETOK = "%s/scripts/tokenizer/detokenizer.perl 2> /dev/null"
DEBUG = False


def main():
    global MOSES_TOK, MOSES_DETOK, DEBUG

    args = parse_options()
    MOSES_TOK = "%s/scripts/tokenizer/tokenizer.perl -threads %i 2> /dev/null" % (args.moses, args.jobs)
    MOSES_DETOK = "%s/scripts/tokenizer/detokenizer.perl -threads %i 2> /dev/null" % (args.moses, args.jobs)
    DEBUG = args.debug

    moses_sentences = tokenize_file(args.m2_file)

    jobs = []
    for entry, idx in each_m2_entry_with_index(args.m2_file):
        jobs.append(delayed(convert_m2_tok)(entry, moses_sentences[idx]))

    results = Parallel(n_jobs=args.jobs)(jobs)
    for entry in results:
        print entry


def convert_m2_tok(entry, moses_sentence):
    in_sent = entry['text']
    out_sent = normalize_negations(moses_sentence)

    debug(entry)
    debug(in_sent, "\n", out_sent, "\n")

    output = "S %s\n" % out_sent

    if in_sent == out_sent:
        for mistake in entry['mistakes']:
            output += format_mistake(mistake) + "\n"
        return output

    diffs = edited_tokens(in_sent.split(' '), out_sent.split(' '))
    maps = mapping(diffs, entry['mistakes'])

    debug(diffs, "\n")
    debug(maps, "\n")

    idx = 0
    for mistake in entry['mistakes']:
        nrm_mistake = normalize_mistake(mistake, in_sent)
        output += format_mistake(nrm_mistake, maps[idx][2], maps[idx][3]) + "\n"
        idx += 1

    return output

def normalize_negations(text):
    return re.sub(r' ([a-z]+) n ', r' \1n ', text)

def mapping(diffs, mistakes):
    diff_maps = diff_mapping(diffs)
    mistake_maps = mistake_mapping(mistakes)

    all_maps = sorted(mistake_maps + diff_maps, key=operator.itemgetter(0,1))
    debug(all_maps)

    maps = []
    i_shift = 0
    j_shift = 0
    shift = 0

    for i, j, k, l in all_maps:
        if k and l:
            i_shift = (k - i)
            j_shift = (l - j)
            shift += j_shift - i_shift
        else:
            maps.append((i, j, i+shift, j+shift))
    return maps

def diff_mapping(diffs):
    maps = []
    i_shift = 0
    j_shift = 0

    for old_edit, new_edit, i, j in diffs:
        if old_edit == '':
            len_diff = len(new_edit.split(' '))
        elif new_edit == '':
            len_diff = -len(old_edit.split(' '))
        else:
            len_diff = len(new_edit.split(' ')) - len(old_edit.split(' '))

        maps.append((i, j, i+i_shift, j+j_shift+len_diff))
        i_shift += len_diff
        j_shift += len_diff

    return maps

def mistake_mapping(mistakes):
    return [(m['start_pos'], m['end_pos'], None, None) for m in mistakes]


def tokenize_file(file_name):
    debug("Detokenize/tokenize with Moses")
    cmd = "cat %s | grep '^S ' | cut -c3- | %s | %s" % (file_name, MOSES_DETOK, MOSES_TOK)
    output = subprocess.check_output(cmd, shell=True)
    return output.strip().split('\n')

def format_mistake(mis, start_pos=None, end_pos=None):
    if not start_pos:
        start_pos = mis['start_pos']
    if not end_pos:
        end_pos = mis['end_pos']

    corr = tokenize_corr(mis['correction'])

    return "A %i %i|||%s|||%s|||%s|||%s|||%s" % (start_pos, end_pos,
                                                 mis['category'], corr, mis['required'],
                                                 mis['comment'], mis['annotator_id'])
def tokenize_corr(corr):
    if not corr:
        return ''
    if re.match(r"^[a-z]+$", corr, re.IGNORECASE):
        return tokenize_puncts(corr)
    corr = detokenize_nltk(tokenize_puncts(corr))
    proc = subprocess.Popen(MOSES_TOK, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    return proc.communicate(input=corr.strip())[0].strip()


def normalize_mistake(mistake, sent):
    mis = mistake.copy()
    start, end = mis['start_pos'], mis['end_pos']
    toks = sent.split(' ')

    if end < len(toks) and start+1 == end:
        tok = toks[start:end][0]
        next_tok = toks[start+1:end+1][0]
        if next_tok == "n't" and not tok.endswith('n'):
            mis['correction'] += 'n'

    return mis

def tokenize_puncts(text):
    return re.sub(r'([a-z]*)\s*([;:,.?!]+)\s*([a-z]*)', r'\1 \2 \3', text).strip()

def each_m2_entry_with_index(m2_fname):
    idx = 0
    for entry in each_m2_entry(m2_fname):
        yield entry, idx
        idx += 1

def each_m2_entry(m2_fname):
    m2_file = open(m2_fname)
    sentence = {}

    for line in m2_file:
        if line.startswith('S '):
            text = line.strip()[2:]
            sentence = {'text': text, 'mistakes': []}

        elif line.startswith('A '):
            mistake = {'line': line.strip()}

            mistake['offsets'], \
            mistake['category'], \
            mistake['correction'], \
            mistake['required'], \
            mistake['comment'], \
            mistake['annotator_id'] = line.strip()[2:].split('|||')

            mistake['start_pos'], mistake['end_pos'] = \
                [int(pos) for pos in mistake['offsets'].split()]

            sentence['mistakes'].append(mistake)

        elif not line.strip():
            yield sentence
            sentence = {}
    if sentence:
        yield sentence

    m2_file.close()

def debug(*args):
    if DEBUG:
        for arg in args:
            print >>sys.stderr, arg,
        print >>sys.stderr

def parse_options():
    parser = argparse.ArgumentParser(
        description="Converts M2 file with NLTK tokenization to Moses tokenization.")
    parser.add_argument("m2_file", help="M2 file with NLTK tokenization")
    parser.add_argument("-m", "--moses", help="Path to Moses directory", required=True)
    parser.add_argument("-d", "--debug", help="Print debug messages", action='store_true')
    parser.add_argument("-j", "--jobs", help="Number of parallel jobs", type=int, default=16)
    return parser.parse_args()

if __name__ == "__main__":
    main()
