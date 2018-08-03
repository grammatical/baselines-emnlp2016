Phrase-based Machine Translation is State-of-the-Art for Automatic Grammatical Error Correction
===============================================================================================

This directory contains updated training scripts and instructions that we used
to create SMT systems in our paper: R. Grundkiewicz, M. Junczys-Dowmunt [Near
Human-Level Performance in Grammatical Error Correction with Hybrid Machine
Translation](http://aclweb.org/anthology/N18-2046), NAACL 2018
[[bibtex]](http://aclweb.org/anthology/N18-2046.bib)

Main modifications include switching to NLTK tokenization, using BPE subword
segmentation, and adding GLEU tuning.


Training scripts
----------------

To reproduce the systems, you need to have installed the following tools:

* Perl
* Python 2.7
* parallel GNU
* Moses from [this branch](https://github.com/snukky/mosesdecoder/tree/gleu)
* [BPE segmentation](https://github.com/rsennrich/subword-nmt)
* [M2Scorer](https://github.com/nusnlp/m2scorer)

You will also need the following data:

* [NUCLE Corpus](http://www.comp.nus.edu.sg/~nlp/conll14st.html#nucle32) with
  official test sets from the CoNLL 2013 and 2014 Shared Tasks
* [JFLEG Corpus](https://github.com/keisks/jfleg) for tuning and evaluation on
  GLEU
* Preprocessed [Lang-8 Learner Corpora](http://cl.naist.jp/nldata/lang-8) for
  parallel training data
* Common Crawl LM and WCLM trained on [this
  data](http://data.statmt.org/romang/gec-emnlp16/sim)
* Truecase model trained with Moses scripts
* BPE codes

*Note*: Previously published language models cannot be used with these scripts
as they are trained on data with different tokenization.

Adjust paths in `configs/*.yml`, and then run training scripts, e.g.:

    ./run_cross.perl -f config.yml -d workdir

The produced `moses.ini` file can be used to run the trained model:

    /path/to/mosesdecoder/bin/moses -f <path-to>/release/work.err-cor/binmodel.err-cor/moses.mert.avg.ini < input.txt

