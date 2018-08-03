#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import glob
import shutil

REMOVE_FILES = {
    'tune': [
        'config.yml',
        '*/log.txt',
        '*/work.err-cor/tuning.*',
        '*/work.err-cor/*model.err-cor/moses.*ini',
        '*/work.err-cor/*model.err-cor/moses.*ini*',
        'release/*mert.*',
        'release/*.stats.*',
        'release/*.nomert',
    ],
    'train': [
        '*/work.err-cor/training.*',
        '*/work.err-cor/giza.*',
        '*/work.err-cor/corpus',
        '*/work.err-cor/osm.err-cor',
        '*/work.err-cor/model.err-cor/lex.*',
        '*/work.err-cor/model.err-cor/aligned.*',
        '*/work.err-cor/model.err-cor/extract.*',
    ],
    'hard': [
        'full*.txt',
        'nucle.m2.mosestok',
        'part.*',
        '*/train.*',
    ]
}


def main():
    args = parse_user_args()

    if args.noop:
        print "Test run mode, no files removed!"

    for target in args.targets:
        if not os.path.exists(target):
            print "Target directory does not exist!"
            exit(1)

        print "Removing files from '{}'...".format(target)
        for rm_patt in REMOVE_FILES[args.mode]:
            rm_path = os.path.join(target, rm_patt)
            print rm_path
            for rm_file in glob.glob(rm_path):
                if not os.path.exists(rm_file):
                    continue
                if args.noop:
                    continue
                if os.path.isdir(rm_file):
                    shutil.rmtree(rm_file)
                else:
                    os.remove(rm_file)

    print "Done!"


def parse_user_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("targets", nargs="+", help="target directories")
    parser.add_argument("-m", "--mode", default='train',
                        help="set of files to be removed: tune,train,hard")
    parser.add_argument("-n", "--noop", action='store_true',
                        help="test verbose mode")
    return parser.parse_args()


if __name__ == '__main__':
    main()
