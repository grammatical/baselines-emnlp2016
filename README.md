Phrase-based Machine Translation is State-of-the-Art for Automatic Grammatical Error Correction
===============================================================================================

This repository will contain baseline models, training scripts, and
instructions on how to reproduce our results for our state-of-art grammar
correction system from M. Junczys-Dowmunt, R. Grundkiewicz: [_Phrase-based
Machine Translation is State-of-the-Art for Automatic Grammatical Error
Correction_](http://www.aclweb.org/anthology/D/D16/D16-1161.pdf), EMNLP 2016.


Baseline models
---------------

Install [Moses decoder](https://github.com/moses-smt/mosesdecoder). It has to
be compiled with support for [compact phrase tables](http://www.statmt.org/moses/?n=Advanced.RuleTables#ntoc3)
and 9-gram kenLM language models, e.g.:

    /usr/bin/bjam -j16 --with-cmph=/usr/local/lib --max-kenlm-order=9

Download [training data](odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/data.tgz) and
[baseline models](odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/models.tgz).

Adjust absolute paths in `moses.*.ini` file.

Run _moses_, e.g.:

    echo "then a new problem comes out ." | /path/to/mosesdecoder/bin/moses -f moses.dense.ini

The input file contains one sentence per line and each sentence has to follow
the NLTK tokenization scheme used in [the NUCLE Corpus](http://www.comp.nus.edu.sg/~nlp/corpora.html).


Training scripts
----------------

To train the baseline models you will need to install:

* Perl
* Python 2.7
* NLTK and NLTK data for English tokenizer
* parallel GNU
* [Moses](https://github.com/moses-smt/mosesdecoder)
* [Lazy](https://github.com/kpu/lazy)
* [SRILM](http://www.speech.sri.com/projects/srilm/download.html)

Download [training data](odkrywka.wmi.amu.edu.pl/static/data/baselines-emnlp2016/data.tgz) and
[the NUCLE Corpus](http://www.comp.nus.edu.sg/~nlp/conll14st.html#nucle32) with
official test sets of the CoNLL Shared Tasks in 2013 and 2014, and adjust all
paths in `config.*.yml` file.

Run training scripts, e.g.:

    ./run_cross.perl -f config.dense.yml -d model.dense

Use the produced `moses.ini` file to run the system:

    /path/to/mosesdecoder/bin/moses -f /path/to/workdir/release/work.err-cor/binmodel.err-cor/moses.mert.avg.ini < input.txt


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
