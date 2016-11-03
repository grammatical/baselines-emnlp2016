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


System outputs
--------------

This folder contains example outputs from our systems described in the paper for
CoNLL-test2014.


  .
  ├── cclm
  │   ├── baseline+cclm.out
  │   ├── best.dense+cclm.out
  │   └── best.sparse+cclm.out
  ├── nonpublic
  │   ├── cclm+np
  │   │   ├── best.dense.out
  │   │   └── best.sparse.out
  │   └── wikilm+np
  │       ├── best.dense.out
  │       └── best.sparse.out
  └── wikilm
      ├── baseline.out
      ├── best.dense.out
      └── best.sparse.out



Folders `wikilm` and `cclm` contain our official results from Table 4. The outputs
in `wikilm` are the from the restricted setting, in `cclm` for the unrestricted
setting with the large domain-filtered common crawl language model.

The folder `nonpublic` contains outputs from Table 5. The translation models were
trained with additional non-public parallel data from the Lang8 website. We do not
consider these outputs as referential and would prefer if future publications do
not reference these results due to the difficulty of comparison. 
