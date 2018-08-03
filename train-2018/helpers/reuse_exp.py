#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import argparse
import glob
import shutil

REMOVE_FILES = {
    'gleu': [
        'full.*',
        'release/test.*',
        'release/work.err-cor/tuning.*',
        '*/work.err-cor/binmodel.err-cor/moses*.ini',
        '*/work.err-cor/model.err-cor/moses.ini',
        'release/eval.gleu.*.mert*',
        'release/jfleg*.mert*', 'release/test2014gleu.*.mert*', '*/log.txt',
        'config.yml'
    ],
    'basic': [
        'cross.??/work.err-cor/tuning.*',
        '*/work.err-cor/binmodel.err-cor/moses*.ini',
        '*/work.err-cor/model.err-cor/moses.ini', 'release/eval.*',
        'release/test201*', 'release/10gec*', 'release/jfleg*',
        'release/off201*', '*/log.txt', 'config.yml'
    ],
    'old': [
        'cross.??/work.err-cor/tuning.*',
        '*/work.err-cor/binmodel.err-cor/moses*.ini',
        '*/work.err-cor/model.err-cor/moses.ini', 'release/eval.*',
        'release/test-final-2013.*', 'release/off-2014.*', '*/log.txt',
        'config.yml'
    ]
}


def main():
    args = parse_user_args()

    if args.version not in REMOVE_FILES.keys():
        print "Unrecognized directory structure: {}".format(args.version)
        exit(1)

    if not os.path.exists(args.source):
        print "Source directory does not exist!"
        exit(1)

    if args.clean:
        args.target = args.source
    else:
        if not args.target:
            print "Target directory not specified!"
            exit(1)
        if os.path.exists(args.target):
            print "Target directory already exists!"
            exit(1)

        print "Copying experiment..."
        shutil.copytree(args.source, args.target)

    print "Removing unwanted files..."
    for rm_patt in REMOVE_FILES[args.version]:
        rm_path = os.path.join(args.target, rm_patt)
        print rm_path
        for rm_file in glob.glob(rm_path):
            if not os.path.exists(rm_file):
                continue
            if os.path.isdir(rm_file):
                try:
                    shutil.rmtree(rm_file)
                except:
                    print "Error: {}".foramt(sys.exc_info()[0])
            else:
                os.remove(rm_file)

    print "Done!"


def parse_user_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="source directory")
    parser.add_argument("target", nargs="?", help="target directory")
    parser.add_argument(
        "-c",
        "--clean",
        action='store_true',
        help="only remove unwanted files from directory")
    parser.add_argument(
        "-v",
        "--version",
        default='basic',
        help="directory structure version: basis, old")
    return parser.parse_args()


if __name__ == '__main__':
    main()
