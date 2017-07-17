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
    if args.nbest is not None:
        run_cmd("{moses}/bin/moses -f {ini}" \
                " -n-best-list - {nbest} distinct" \
                " -print-alignment-info-in-n-best " \
                " -labeled-n-best-list false " \
                " -threads {th} -fd '|'" \
                " < {pfx}.in.tok > {pfx}.out.tok.nbest" \
            .format(moses=args.moses, ini=args.config, pfx=prefix,
                    th=args.threads, nbest=args.nbest))

        extract_text_and_alignment(
            "{}.out.tok.nbest".format(prefix), "{}.in".format(prefix),
            "{}.out.tok".format(prefix), "{}.out.tok.aln".format(prefix),
            "{}.in.nbest".format(prefix))

        run_cmd("cp {pfx}.in {pfx}.in.bac".format(pfx=prefix))
        run_cmd("mv {pfx}.in.nbest {pfx}.in".format(pfx=prefix))
    else:
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

    if args.nbest:
        reconstruct_nbest_list("{}.out.tok.nbest".format(prefix),
                               "{}.out".format(prefix),
                               "{}.out.nbest".format(prefix))

        run_cmd("cp {pfx}.out {pfx}.out.bac".format(pfx=prefix))
        run_cmd("mv {pfx}.out.nbest {pfx}.out".format(pfx=prefix))

    if args.output:
        run_cmd("cp {pfx}.out {out}".format(pfx=prefix, out=args.output))

    # evaluate if possible
    if args.m2 and not args.nbest:
        run_cmd("{scripts}/m2scorer_fork {pfx}.out {f} > {pfx}.eval" \
            .format(scripts=args.scripts, pfx=prefix, f=args.input))
        with open("{}.eval".format(prefix)) as eval_io:
            print eval_io.read().strip()


def reconstruct_nbest_list(nbest_in, txt_in, nbest_out):
    txt_io = open(txt_in)
    out_io = open(nbest_out, 'w+')
    with open(nbest_in) as nbest_io:
        for line in nbest_io:
            sent = txt_io.next().strip()
            idx, _, _, score, _ = line.strip().split(" ||| ")
            out_io.write("{i} ||| {t} ||| {s}\n".format(
                i=idx, t=sent, s=score))
    txt_io.close()
    out_io.close()


def extract_text_and_alignment(nbest_file, orig_in, txt_out, aln_out,
                               orig_out):
    txt_io = open(txt_out, 'w+')
    aln_io = open(aln_out, 'w+')
    org1_io = open(orig_in)
    org2_io = open(orig_out, 'w+')
    with open(nbest_file) as nbest_io:
        last_idx = -1
        orig_sent = None
        for line in nbest_io:
            idx, sent, _, _, align = line.strip().split(" ||| ")
            if int(idx) != last_idx:
                orig_sent = org1_io.next()
                last_idx = int(idx)
            txt_io.write(sent.strip() + "\n")
            aln_io.write(align.strip() + "\n")
            org2_io.write(orig_sent)
    txt_io.close()
    aln_io.close()
    org1_io.close()
    org2_io.close()


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
    parser.add_argument("--nbest", help="Generate n-best list", type=int)
    return parser.parse_args()


if __name__ == '__main__':
    main()
