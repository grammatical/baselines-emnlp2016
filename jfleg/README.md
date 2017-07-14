Phrase-based Machine Translation is State-of-the-Art for Automatic Grammatical Error Correction
===============================================================================================

This repository will contain baseline models, training scripts, and
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


Results on JFLEG data set
-------------------------

This folder contains outputs from our systems described in the paper for [JFLEG
data set](https://github.com/keisks/jfleg).  The results are reported in GLEU
metric. The outputs are produced with SMT systems tuned on M^2 as they have
been described in the paper.

| System | JFLEG dev | JFLEG test |
| :--- | --- | --- |
| Best dense | 0.467356 | 0.503200 |
| +CCLM | 0.458919 | 0.503674 |
| Best sparse | 0.456573 | 0.492342 |
| +CCLM | 0.453775 | 0.500863 |
| Best dense (np) | 0.479190 | 0.515052 |
| +CCLM | 0.475558 | 0.515415 |
| Best sparse (np) | 0.468146 | 0.509849 |
| +CCLM | 0.465852 | 0.510161 |

Systems marked as (np) use non-public training data and should be compared to
the results presented in Table 5. The translation models were trained with
additional non-public parallel data from the Lang8 website.  We do not consider
these outputs as referential and would prefer if future publications do not
reference these results due to the difficulty of comparison.


System outputs
--------------

    .
    ├── dev.dense+cclm.out
    ├── dev.dense+wikilm.out
    ├── dev.sparse+cclm.out
    ├── dev.sparse+wikilm.out
    ├── Makefile
    ├── nonpublic
    │   ├── dev.dense+cclm+nonpub.out
    │   ├── dev.dense+wikilm+nonpub.out
    │   ├── dev.sparse+cclm+nonpub.out
    │   ├── dev.sparse+wikilm+nonpub.out
    │   ├── test.dense+cclm+nonpub.out
    │   ├── test.dense+wikilm+nonpub.out
    │   ├── test.sparse+cclm+nonpub.out
    │   └── test.sparse+wikilm+nonpub.out
    ├── test.dense+cclm.out
    ├── test.dense+wikilm.out
    ├── test.sparse+cclm.out
    └── test.sparse+wikilm.out

