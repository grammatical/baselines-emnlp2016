#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import argparse

SKIP = ['.log', '.yml', '~']


def main():
    args = parse_user_args()
    TEST_SETS = args.test_sets.strip().split(',')

    suffixes = ['.mert.avg.txt']
    if args.all:
        suffixes += ['.mert.{}.txt'.format(i + 1) for i in range(4)]

    print "%", args.test_sets

    for folder in args.directory:
        if any(folder.endswith(e) for e in SKIP):
            continue
        print folder,

        for suffix in suffixes:
            for test_set in TEST_SETS:
                path = os.path.join(
                    folder, args.subdir, 'eval.' + args.metric + '.' + test_set + suffix)
                if args.verbose:
                    print >>sys.stderr, path
                if not os.path.exists(path):
                    # print "File {} does not exist".format(path)
                    continue
                with open(path) as f:
                    if args.metric == "m2":
                        p, r, f = [float(line.strip().split()[-1]) * 100.0
                                   for line in f if not line.startswith("#")]
                        print "\t && {:.2f} & {:.2f} & {:.2f} ".format(p, r, f),
                    else:
                        f = [float(line.strip().split("'")[1])
                             for line in f if line.startswith("[[")][0]
                        print "\t && n/a & n/a & {:.4f} ".format(f),

            print r'\\'


def parse_user_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs='+')
    parser.add_argument("--metric", default='m2')
    parser.add_argument("--subdir", default='release')
    parser.add_argument(
        "--test-sets", default='jflegdevm2,jflegtestm2,test2013,test2014')
    parser.add_argument("-a", "--all", action='store_true')
    parser.add_argument("-v", "--verbose", action='store_true')
    parser.add_argument("-g", "--gleu", action='store_true')
    args = parser.parse_args()
    if args.gleu:
        args.metric = 'gleu'
        args.test_sets = 'test2014gleu,jflegdev,jflegtest'
    return args


if __name__ == '__main__':
    main()
