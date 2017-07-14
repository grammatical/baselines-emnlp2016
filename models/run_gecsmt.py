#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import yaml
import re

MOSES = "/data/smt/mosesdecoder"
LAZY = "/data/smt/lazy"
SCRIPTS = "/work/gec/repos/baselines-emnlp2016/train/scripts"
THREADS = 16


def main():
    args = parse_user_args()

    LM, WC, use_sparse = parse_config_ini(args.config)

    TOK = "{}/scripts/tokenizer/tokenizer.perl".format(args.moses)
    DETOK = "{}/scripts/tokenizer/detokenizer.perl".format(args.moses)

    TC = "{}/case_graph.perl --lm {} --decode {}/bin/decode" \
        .format(args.scripts, LM, args.lazy)

    # set up working directory
    if not os.path.exists(args.workdir):
        os.makedirs(args.workdir)
    base = os.path.splitext(os.path.basename(args.input))[0]
    prefix = os.path.join(args.workdir, base)

    # get text to be corrected
    if args.m2:
        run_cmd("grep '^S' {f} | cut -c3- > {pfx}.in" \
            .format(f=args.input, pfx=prefix))
    else:
        run_cmd("cp {f} {pfx}.in".format(f=args.input, pfx=prefix))

    # tokenize and truecase
    run_cmd("{scripts}/m2_tok/detokenize.py < {pfx}.in " \
            " | {tok} -threads {th} | {tc} > {pfx}.in.tok"
        .format(pfx=prefix, scripts=args.scripts, tok=TOK, th=args.threads, tc=TC))

    # models with sparse features assume WC factored input
    if use_sparse:
        run_cmd("mv {pfx}.in.tok {pfx}.in.tok.nowc".format(pfx=prefix))
        run_cmd("perl {scripts}/anottext.pl -f {wc}" \
                " < {pfx}.in.tok.nowc > {pfx}.in.tok" \
            .format(scripts=args.scripts, wc=WC, pfx=prefix))

    # run Moses
    run_cmd("{moses}/bin/moses -f {ini}" \
            " --alignment-output-file {pfx}.out.tok.aln -threads {th} -fd '|'" \
            " < {pfx}.in.tok > {pfx}.out.tok" \
        .format(moses=args.moses, ini=args.config, pfx=prefix, th=args.threads))

    # restore casing and tokenization
    run_cmd("cat {pfx}.out.tok" \
            " | {scripts}/impose_case.perl {pfx}.in {pfx}.out.tok.aln" \
            " | {moses}/scripts/tokenizer/deescape-special-chars.perl" \
            " | {scripts}/impose_tok.perl {pfx}.in > {pfx}.out" \
        .format(pfx=prefix, scripts=args.scripts, moses=args.moses))

    if args.output:
        run_cmd("cp {pfx}.out {out}".format(pfx=prefix, out=args.output))

    # evaluate if possible
    if args.m2:
        run_cmd("{scripts}/m2scorer_fork {pfx}.out {f} > {pfx}.eval" \
            .format(scripts=args.scripts, pfx=prefix, f=args.input))
        with open("{}.eval".format(prefix)) as eval_io:
            print eval_io.read().strip()


def run_cmd(cmd):
    print >> sys.stderr, "Run:", cmd
    os.popen(cmd)


def parse_config_ini(config):
    with open(config) as config_io:
        ini = config_io.readlines()
        ini = "".join(l for l in ini if not l.startswith("#"))

    if "name=LM1" in ini:
        lmpath = re.search(r'name=LM1 .*path=(.*) order=', ini).group(1)
        print "Found LM: {}".format(lmpath)
    if "name=Generation0" in ini:
        wcpath = re.search(r'Generation name=Generation0 .* path=(.*)',
                           ini).group(1)
        print "Found WC: {}".format(wcpath)

    if not lmpath:
        print "No LM found!"
        exit(1)
    if not wcpath:
        print "No WC found!"
        exit(1)

    sparse = "[weight-file]" in ini
    if sparse:
        print "Found sparse features"
    return lmpath, wcpath, sparse


def parse_user_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--config", help="Moses INI file", required=True)
    parser.add_argument("-i", "--input", help="Input file", required=True)
    parser.add_argument("-o", "--output", help="Output file")
    parser.add_argument(
        "-w", "--workdir", help="Working directory", default=".")
    parser.add_argument(
        "--m2", help="Assume input in M2 format", action="store_true")

    parser.add_argument("--moses", help="Path to Moses decoder", default=MOSES)
    parser.add_argument("--lazy", help="Path to lazy decoder", default=LAZY)
    parser.add_argument(
        "--scripts",
        help="Path to baselines-emnlp2016/train/scripts",
        default=SCRIPTS)
    parser.add_argument(
        "-t", "--threads", help="Number of threads", type=int, default=THREADS)
    return parser.parse_args()


if __name__ == '__main__':
    main()
