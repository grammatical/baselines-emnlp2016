Phrase-based Machine Translation is State-of-the-Art for Automatic Grammatical Error Correction
===============================================================================================

This repository contains baseline models, training scripts, and
instructions on how to reproduce our results for our state-of-art grammar
correction system from M. Junczys-Dowmunt, R. Grundkiewicz: [_Phrase-based
Machine Translation is State-of-the-Art for Automatic Grammatical Error
Correction_](http://www.aclweb.org/anthology/D/D16/D16-1161.pdf), EMNLP 2016.


Citation
--------

    @InProceedings{junczysdowmunt-grundkiewicz:2016:EMNLP2016,
      author    = {Junczys-Dowmunt, Marcin  and  Grundkiewicz, Roman},
      title     = {Phrase-based Machine Translation is State-of-the-Art for
                   Automatic Grammatical Error Correction},
      booktitle = {Proceedings of the 2016 Conference on Empirical Methods in
                   Natural Language Processing},
      month     = {November},
      year      = {2016},
      address   = {Austin, Texas},
      publisher = {Association for Computational Linguistics},
      pages     = {1546--1556},
      url       = {https://aclweb.org/anthology/D16-1161}
    }


Training scripts
----------------

To reproduce our systems from scratch, you need to have installed the following:

* Perl
* Python 2.7
* NLTK and NLTK data for English tokenizer
* parallel GNU
* [Moses](https://github.com/moses-smt/mosesdecoder)
* [Lazy](https://github.com/kpu/lazy)
* [SRILM](http://www.speech.sri.com/projects/srilm/download.html)

You also need the following data:

* [NUCLE Corpus](http://www.comp.nus.edu.sg/~nlp/conll14st.html#nucle32) with official test sets from the CoNLL 2013 and 2014 Shared Tasks
* [Lang-8 NAIST](http://odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/lang8.tgz) (63M)
* [Wikipedia language model](http://odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/wikilm.tgz) (22G)
* [Common Crawl language model](http://odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/cclm.tgz) (26G)

Adjust all paths in `config.*.yml` file from this folder, and then run training scripts, e.g.:

    ./run_cross.perl -f config.dense.yml -d model.dense

The produced `moses.ini` file can be used to run the trained model:

    /path/to/mosesdecoder/bin/moses -f /path/to/workdir/release/work.err-cor/binmodel.err-cor/moses.mert.avg.ini < input.txt
