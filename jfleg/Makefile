THREADS = 8

# dirs, scripts and commands
MOSES = /path/to/mosesdecoder
EMNLP = /path/to/baselines-emnlp2016
JFLEG = /path/to/jfleg

# allowed values: test, dev
PREFIX = test
DATA = $(JFLEG)/$(PREFIX)/$(PREFIX)

# copy all moses.*.ini files to this folder
MODELS = $(wildcard moses.*.ini)
OUTPUTS = $(patsubst moses.%.ini,$(PREFIX).%.out,$(MODELS))
EVALS = $(patsubst moses.%.ini,$(PREFIX).%.gleu,$(MODELS))
WDIFFS = $(patsubst moses.%.ini,$(PREFIX).%.wdiff,$(MODELS))

.SECONDARY:


all: $(EVALS)

$(PREFIX).%.gleu: $(PREFIX).%.out
	python $(JFLEG)/eval/gleu.py --ref $(DATA).ref? --src $(DATA).src --hyp $< > $@

$(PREFIX).%.out: $(PREFIX).in moses.%.ini
	$(EMNLP)/models/run_gecsmt.py -f moses.$*.ini -w dir.$(PREFIX).$* -t $(THREADS) -i $< -o $@

$(PREFIX).in: $(DATA).src
	cp $< $@


wdiffs: $(WDIFFS)

$(PREFIX).%.wdiff: $(PREFIX).in $(PREFIX).%.out
	wdiff $^ > $@


clean:
	rm -f *.in *.out *.gleu *.wdiff
