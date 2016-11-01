#!/usr/bin/python
# -*- encoding: utf-8 -*-

import os
import sys
from math import log, exp
from kenlm import LanguageModel

lm = None
lm_prob = None
model = None


def main():
    parse_args()
    model = LanguageModel(lm)

    for line in sys.stdin:
        s, t, weights, align, rest = line.strip().split(' ||| ')

        if s == t:
            weights += ' 1'
        else:
            s_score, t_score = model.score(s), model.score(t)
            s_len, t_len = s.count(' ') + 1, t.count(' ') + 1

            weights += " %.6f" % lm_prob(s_score, t_score, s_len, t_len)

        print ' ||| '.join([s, t, weights, align, rest])

def lm_prob_arithmetic(s_score, t_score, s_len, t_len):
    return exp(t_score + log(s_len) - s_score - log(t_len))
    #return (t_score * s_len) / (s_score * t_len)

def lm_prob_geometric(s_score, t_score, s_len, t_len):
    return exp(t_score/float(t_len) - s_score/float(s_len))
    #return ((-t_score) ** (1./t_len)) / ((-s_score) ** (1./s_len))

def lm_prob_raw(s_score, t_score, s_len, t_len):
    return exp(t_score - s_score)


def parse_args():
    global lm_prob
    global lm

    if '-h' in sys.argv or '--help' in sys.argv:
        print "Adds LM-based feature to phrase table."
        print "usage: zcat phrase-table.gz | ./add_lm_prob.py [-a|-g] | gz"
        exit(0)

    if '-g' in sys.argv:
        lm_prob = lm_prob_geometric
    if '-a' in sys.argv:
        lm_prob = lm_prob_arithmetic
    else:
        lm_prob = lm_prob_raw

    if '-lm' in sys.argv:
        idx = sys.argv.index('-lm') + 1
        lm = sys.argv[idx]

if __name__ == '__main__':
    main()
