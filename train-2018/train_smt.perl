#!/usr/bin/perl

use strict;
use Getopt::Long;
use File::Spec;
use Parallel::ForkManager;
use POSIX;
use YAML::XS 'LoadFile';
use File::Basename;

my $SUCCESS = 0;
my $PID     = $$;
$SIG{TERM}  = $SIG{INT} = $SIG{QUIT} = sub { die; };

my $args = join( ' ', @ARGV );

###############################################################################

my $WORK_DIR;
my $CORPUS      = "train";
my $CREATE_LM   = "";
my $NGRAM_ORDER = 5;
my @FILTER;

my $LEVENSHTEIN = undef;
my $EDITOPS     = undef;
my $CHAROPS     = undef;
my $LM          = undef;
my $OSM         = undef;
my $ESM         = undef;
my $WCLM        = undef;
my $POSLM       = undef;
my $NPLM        = undef;
my $BINPLM      = undef;
my $NMT         = undef;
my $WC          = undef;
my $POS         = undef;
my $LMRATIO     = undef;
my $PTAUGMENT   = undef;

my $FACTOR_DELIMITER = '|';
my $HMM              = 1;

my $MOSESDIR   = undef;
my $BINDIR     = undef;
my $SCRIPTSDIR = undef;

my $CORES  = 16;
my $MCORES = 8;
my $LOG    = 0;
my $HELP   = 0;

GetOptions(
    "w|work-dir=s" => \$WORK_DIR,

    "c|corpus=s"      => \$CORPUS,
    "l|lm-data=s"     => \$CREATE_LM,
    "n|ngram-order=i" => \$NGRAM_ORDER,

    "levenshtein"     => \$LEVENSHTEIN,
    "editops"         => \$EDITOPS,
    "charops"         => \$CHAROPS,
    "lm=s"            => \$LM,
    "osm"             => \$OSM,
    "esm"             => \$ESM,
    "wclm=s"          => \$WCLM,
    "poslm=s"         => \$POSLM,
    "nplm=s"          => \$NPLM,
    "binplm=s"        => \$BINPLM,
    "nmt=s"           => \$NMT,
    "wc=s"            => \$WC,
    "pos=s"           => \$POS,
    "lmratio"         => \$LMRATIO,
    "ptaugment"       => \$PTAUGMENT,

    "filter=s"        => \@FILTER,
    "delimiter=s"     => \$FACTOR_DELIMITER,
    "hmm!"            => \$HMM,

    "moses-dir=s"     => \$MOSESDIR,
    "bin-dir=s"       => \$BINDIR,
    "scripts-dir=s"   => \$SCRIPTSDIR,

    "j|jobs=i"        => \$CORES,
    "log=s"           => \$LOG,
    "h|help"          => \$HELP,
);

###############################################################################

die "Specify a path to the Moses decoder.\n"
    if ( not $MOSESDIR or not -e $MOSESDIR );
die "Specify a path to Moses external bin directory.\n"
    if ( not $BINDIR or not -e $BINDIR );
die "Specify a path to root directory.\n"
    if ( not $SCRIPTSDIR or not -e $SCRIPTSDIR );

if ($HELP) {
    print "No help message, see the code :P\n";
    exit(0);
}

#############################################################################
# Start

$WORK_DIR = "work_dir.err-cor" if ( not $WORK_DIR );
$WORK_DIR = File::Spec->rel2abs($WORK_DIR);

if ($LOG) {
    open( LOG, ">$LOG" ) or die("Could not create log file '$LOG'\n");
}

message("Executed on " . `hostname` . " in dir " . `pwd` . " with command:");
message("perl $0 $args");

if ( not -e $WORK_DIR ) {
    execute("mkdir -p $WORK_DIR");
    -e $WORK_DIR or die "Could not create working directory $WORK_DIR\n";
}

###############################################################################
# Set up data sets

my $CORPUS_SRC = setup_data( "source training set", "$CORPUS.err", "$WORK_DIR/training.err-cor.err" );
my $CORPUS_TRG = setup_data( "target training set", "$CORPUS.cor", "$WORK_DIR/training.err-cor.cor" );

message("Running data integrity checks");

die "Aborting!" if ( not compare_counts( $CORPUS_SRC, $CORPUS_TRG ) );

###############################################################################
# Set up paths

$CORPUS = "$WORK_DIR/training.err-cor";

my $MODEL_DIR    = "$WORK_DIR/model.err-cor";
my $LM_DIR       = "$WORK_DIR/lm";
my $BINMODEL_DIR = "$WORK_DIR/binmodel.err-cor";

execute("mkdir -p $LM_DIR")       if not -e $LM_DIR;
execute("mkdir -p $BINMODEL_DIR") if not -e $BINMODEL_DIR;

###############################################################################
# Create language model from target language data

execute("echo alibi > $BINMODEL_DIR/lm.cor.kenlm")
    if ( not -e "$BINMODEL_DIR/lm.cor.kenlm" );
execute("echo alibi > $BINMODEL_DIR/lm.cls.cor.kenlm")
    if ( not -e "$BINMODEL_DIR/lm.cls.cor.kenlm" );

my $lmpid = fork();
if ( $lmpid == 0 ) {
    if ( not -e "$BINMODEL_DIR/lm.cor.kenlm" or -s "$BINMODEL_DIR/lm.cor.kenlm" == 6 ) {
        message("Creating language model");

        my $LM_DATA = $CORPUS_TRG;
        if ( $CREATE_LM and -e $CREATE_LM ) {
            $LM_DATA = $CREATE_LM;
        }

        execute("$MOSESDIR/bin/lmplz -S 10G -o $NGRAM_ORDER --text $LM_DATA | gzip > $LM_DIR/lm.cor.arpa.gz")
            unless -e "$LM_DIR/lm.cor.arpa.gz";
        execute("$MOSESDIR/bin/build_binary -s -i trie $LM_DIR/lm.cor.arpa.gz $BINMODEL_DIR/lm.cor.kenlm");
        message("Finished creating language model");
    }
    exit 0;
}

###############################################################################
# Train settings

my @PHRASEFACTORS   = ("0-0");
my $PHRASE_TABLE    = "$MODEL_DIR/phrase-table";
my @PT_TEST         = ("$MODEL_DIR/moses.ini");

push( @PT_TEST, "$PHRASE_TABLE.0-0.gz" );

my $FACTOROPTS
    = " --translation-factors 0-0"
    . " --alignment-factors 0-0"
    . " --force-factored-filenames"
    . " --reordering-factors 0-0";

###############################################################################
# Train a model

if (@FILTER) {
    push( @PT_TEST, "$PHRASE_TABLE.0-0.gz.unfiltered" );
}

my $osmpid;
my $esmpid;

if ( not all_exist(@PT_TEST) ) {
    my $TRAIN_MODEL_COMMAND
        = "perl $MOSESDIR/scripts/training/train-model.perl"
        . " --root-dir $WORK_DIR"
        . " --model-dir $MODEL_DIR"
        . " --corpus $CORPUS"
        . " --f err --e cor"
        . " --lm 0:$NGRAM_ORDER:$BINMODEL_DIR/lm.cor.kenlm:8"
        . " --external-bin-dir $BINDIR"
        . " --alignment=grow-diag-final"
        . " --mgiza"
        . " --mgiza-cpus $MCORES"
        . " --cores $CORES"
        . " --sort-buffer-size=5G"
        . " --sort-parallel=$CORES"
        . " --temp-dir $WORK_DIR"
        . " --parallel"
        . " --sort-compress gzip"
        . " $FACTOROPTS";

    $TRAIN_MODEL_COMMAND .= " --hmm-align" if ($HMM);
    $TRAIN_MODEL_COMMAND .= " --lm $LM"    if ($LM);
    $TRAIN_MODEL_COMMAND .= " --lm $WCLM"  if ($WCLM);
    $TRAIN_MODEL_COMMAND .= " --lm $POSLM" if ($POSLM);

    message("Creating translation model");
    my $TFACTOR = $PHRASEFACTORS[0];

    my @STEPS = (
        [   "1",
            [   "$WORK_DIR/corpus/err-cor-int-train.snt",
                "$WORK_DIR/corpus/cor-err-int-train.snt"
            ]
        ],
        [   "2",
            [   "$WORK_DIR/giza.err-cor/err-cor.A3.final.gz",
                "$WORK_DIR/giza.cor-err/cor-err.A3.final.gz"
            ]
        ],
        [ "3",
            [   "$MODEL_DIR/aligned.grow-diag-final"
            ]
        ],
        [   "4",
            [   "$MODEL_DIR/lex.$TFACTOR.e2f",
                "$MODEL_DIR/lex.$TFACTOR.f2e"
            ]
        ],
        [   "5",
            [   "$MODEL_DIR/extract.$TFACTOR.sorted.gz",
                "$MODEL_DIR/extract.$TFACTOR.inv.sorted.gz"
            ]
        ],
        [ "6", ["$PHRASE_TABLE.$TFACTOR.gz"] ]
    );

    push( @STEPS, [ "8,9", ["$MODEL_DIR/moses.ini"] ] );

    if ($HMM) {
        $STEPS[1] = [
            "2",
            [   "$WORK_DIR/giza.err-cor/err-cor.Ahmm.5.gz",
                "$WORK_DIR/giza.cor-err/cor-err.Ahmm.5.gz"
            ]
        ];
    }

    foreach my $STEP_CHECK (@STEPS) {
        my ( $STEP, $CHECK ) = @$STEP_CHECK;
        if ( -e "$PHRASE_TABLE.$TFACTOR.gz" and $STEP < 6 ) {
            print "Phrase table exists, skipping step $STEP\n";
        } else {
            moses_steps( $TRAIN_MODEL_COMMAND, $STEP, $CHECK );
        }
    }

    if ( $OSM and -s "$MODEL_DIR/aligned.grow-diag-final" ) {
        $osmpid = fork();
        if ( $osmpid == 0 ) {
            if ( not -e "$BINMODEL_DIR/osm.kenlm" ) {
                message("Creating OSM");

                my $OSM_DATA_E = $CORPUS_TRG;
                my $OSM_DATA_F = $CORPUS_SRC;

                my $OSM_DIR = "$WORK_DIR/osm.err-cor";

                my $osmcmd
                    = "$MOSESDIR/scripts/OSM/OSM-Train.perl"
                    . " --corpus-e $OSM_DATA_E --corpus-f $OSM_DATA_F"
                    . " --alignment $MODEL_DIR/aligned.grow-diag-final"
                    . " --moses-src-dir $MOSESDIR"
                    . " --out-dir $OSM_DIR";
                execute($osmcmd) if not -e "$OSM_DIR/operationLM.bin";

                execute("mv $OSM_DIR/operationLM.bin $BINMODEL_DIR/osm.kenlm");
                message("Finished OSM");
            }
            exit 0;
        }
    }

    if ($ESM) {
        $esmpid = fork();
        if ( $esmpid == 0 ) {
            if ( not -e "$BINMODEL_DIR/esm.kenlm" ) {
                message("Creating ESM");

                my $ESM_DIR = "$WORK_DIR/esm.err-cor";
                execute("mkdir -p $ESM_DIR");
                my $esmcmd
                    = "$MOSESDIR/bin/ESMSequences"
                    . " --source $CORPUS_SRC --target $CORPUS_TRG"
                    . " --alignment $MODEL_DIR/aligned.grow-diag-final"
                    . " > $ESM_DIR/esmCorpus.txt";

                execute($esmcmd) if not -e "$ESM_DIR/esmCorpus.txt";

                execute("$MOSESDIR/bin/lmplz -o 5 --prune 0 0 1 --text $ESM_DIR/esmCorpus.txt | pigz > $ESM_DIR/esmLM.arpa.gz")
                    if not -e "$ESM_DIR/esmLM.arpa.gz";
                execute("$MOSESDIR/bin/build_binary trie $ESM_DIR/esmLM.arpa.gz $ESM_DIR/esmLM.kenlm")
                    if not -e "$ESM_DIR/esmLM.kenlm";

                execute("mv $ESM_DIR/esmLM.kenlm $BINMODEL_DIR/esm.kenlm");
                message("Finished ESM");
            }
            exit 0;
        }
    }

    if (@FILTER) {
        if ( not -e "$PHRASE_TABLE.$TFACTOR.gz.unfiltered" ) {
            message( "Filtering phrase table with file ", join( " ", @FILTER ) );
            `mv $PHRASE_TABLE.$TFACTOR.gz $PHRASE_TABLE.$TFACTOR.gz.unfiltered`;
            my $script = "perl $SCRIPTSDIR/filter_pt.perl " . join( " ", @FILTER );
            execute("zcat $PHRASE_TABLE.$TFACTOR.gz.unfiltered | parallel --block 100M --pipe -k -j $CORES $script | pigz > $PHRASE_TABLE.$TFACTOR.gz");
        }
    }

    if ($LMRATIO) {
        if ( not -e "$PHRASE_TABLE.$TFACTOR.gz.baclm" ) {
            message("Adding lm ratio phrase table");

            `mv $PHRASE_TABLE.$TFACTOR.gz $PHRASE_TABLE.$TFACTOR.gz.baclm`;
            my $script = "python $SCRIPTSDIR/add_lm_prob.py -lm " . substr( $LM, 4, -2 );
            `zcat $PHRASE_TABLE.$TFACTOR.gz.baclm | parallel --pipe -k -j $CORES --block 100M $script | pigz > $PHRASE_TABLE.$TFACTOR.gz`;
        }
    }

    message("Finished creating translation model");

}

###############################################################################
# Binarize the model

my $FORKS    = 1;
my $BINCORES = int( $CORES / $FORKS + 0.5 );
my @COMMANDS;
for my $FACTORS (@PHRASEFACTORS) {
    my $text_phrase_table = "$PHRASE_TABLE.$FACTORS.gz";

    my $nscores = 4;
    $nscores += 1 if ($LMRATIO);
    $nscores += 1 if ($PTAUGMENT);

    if ( not -e "$BINMODEL_DIR/phrase-table.$FACTORS.minphr" ) {
        my $command
            = "$MOSESDIR/bin/processPhraseTableMin"
            . " -in $text_phrase_table"
            . " -nscores $nscores"
            . " -out $BINMODEL_DIR/phrase-table.$FACTORS"
            . " -threads $BINCORES";

        push( @COMMANDS, $command );
    }
}

my $BINPM = new Parallel::ForkManager($FORKS);
for my $command (@COMMANDS) {
    $BINPM->start() and next;
    message("Binarizing phrase/rule table");
    execute($command);
    message("Finished binarizing");
    $BINPM->finish();
}
$BINPM->wait_all_children();

###############################################################################
# Adjust moses.ini to work with files in $BINMODEL_DIR

my $INI = "moses.ini";
if ( not -e "$BINMODEL_DIR/$INI" ) {
    message("Adjusting $INI");
    open( INI1, "<", "$MODEL_DIR/$INI" )    or die "Cannot open $MODEL_DIR/$INI for reading\n";
    open( INI2, ">", "$BINMODEL_DIR/$INI" ) or die "Cannot open $BINMODEL_DIR/$INI for writing\n";

    while (<INI1>) {
        if ($WCLM and $POSLM) {
            if (/0 T 0/) {
                print INI2 "0 T 0\n0 G 0\n0 G 1\n";
                next;
            }
        }
        elsif ($WCLM or $POSLM) {
            if (/0 T 0/) {
                print INI2 "0 T 0\n0 G 0\n";
                next;
            }
        }

        if (/\[distortion-limit\]/) {
            print INI2 "[distortion-limit]\n";
            print INI2 "1\n";
            my $skip = <INI1>;
            next;
        }

        if (/\[feature\]/) {
            print INI2 "[feature]\n";
            if ($OSM) {
                print INI2 "OpSequenceModel path=$BINMODEL_DIR/osm.kenlm input-factor=0 output-factor=0 support-features=no num-features=1\n";
            }
            if ($ESM) {
                print INI2 "EditSequenceModel path=$BINMODEL_DIR/esm.kenlm input-factor=0 output-factor=0 num-features=1\n";
            }
            if ($LEVENSHTEIN and $EDITOPS) {
                print INI2 "EditOps scores=ldis\n";
            }
            else {
                if ($LEVENSHTEIN) {
                    print INI2 "EditOps name=LevDis0 scores=l\n";
                }
                if ($EDITOPS) {
                    print INI2 "EditOps scores=dis\n";
                }
            }
            if ($CHAROPS) {
                print INI2 "EditOps name=CharOps0 chars=1 scores=dis\n";
            }
            if ($WCLM) {
                print INI2 "Generation name=Generation0 num-features=0 input-factor=0 output-factor=1 path=$WC\n";
            }
            if ($POSLM) {
                if ($WCLM) {
                    print INI2 "Generation name=Generation1 num-features=0 input-factor=0 output-factor=2 path=$POS\n";
                }
                else {
                    print INI2 "Generation name=Generation0 num-features=0 input-factor=0 output-factor=1 path=$POS\n";
                }
            }
            if ($NPLM) {
                print INI2 "NeuralLM name=NLM0 factor=0 order=5 path=$NPLM\n";
            }
            if ($BINPLM) {
                my $nplmdir = dirname($BINPLM);
                print INI2 "BilingualNPLM name=BNLM0 order=5 source_window=4 path=$BINPLM source_vocab=$nplmdir/vocab.source target_vocab=$nplmdir/vocab.target\n";
            }
            if ($NMT) {
                print INI2 "NeuralScoreFeature name=NMT0 mode=rescore config-path=$NMT state-length=1\n";

            }
            next;
        }

        if (/\[weight\]/) {
            print INI2 "[weight]\n";
            if ($OSM) {
                print INI2 "OpSequenceModel0= 0.5\n";
            }
            if ($ESM) {
                print INI2 "EditSequenceModel0= 0.5\n";
            }
            if ($LEVENSHTEIN and $EDITOPS) {
                print INI2 "EditOps0= 0.2 0.2 0.2 0.2\n";
            }
            else {
                if ($LEVENSHTEIN) {
                    print INI2 "LevDis0= 0.2\n";
                }
                if ($EDITOPS) {
                    print INI2 "EditOps0= 0.2 0.2 0.2\n";
                }
            }
            if ($CHAROPS) {
                print INI2 "CharOps0= 0.2 0.2 0.2\n";
            }
            if ($NPLM) {
                print INI2 "NLM0= 0.2\n";
            }
            if ($BINPLM) {
                print INI2 "BNLM0= 0.2\n";
            }
            if ($NMT) {
                print INI2 "NMT0= 0.5\n";
            }

            next;
        }

        if ( /PhraseDictionaryMemory/ and not /glue-grammar/ ) {
            s/PhraseDictionaryMemory/PhraseDictionaryCompact/;
            s/\/model\.err-cor\/phrase-table\.0-0\.gz/\/binmodel.err-cor\/phrase-table.0-0.minphr/;

            if ($LMRATIO) {
                s/num-features=(\d+)/"num-features=" . ($1 + 1)/e;
            }
            if ($PTAUGMENT) {
                s/num-features=(\d+)/"num-features=" . ($1 + 1)/e;
            }
        }

        if (/TranslationModel0=/) {
            if ($LMRATIO) {
                s/0\.2/0.2 0.2/;
            }
            if ($PTAUGMENT) {
                s/0\.2/0.2 0.2/;
            }
        }

        if (/Distortion/) {
            next;
        }

        s/UnknownWordPenalty0= 1/UnknownWordPenalty0= 0/;

        print INI2 $_;
    }

    print INI2 "\n";
    print INI2 "[search-algorithm]\n";
    print INI2 "1\n";

    close(INI2);
    close(INI1);
    message("Finished adjusting $INI");
}

waitpid( $lmpid,  0 );
waitpid( $osmpid, 0 ) if ($OSM);
waitpid( $esmpid, 0 ) if ($ESM);

###############################################################################
# End

$SUCCESS = 1;

END {
    if ( not $HELP and $PID == $$ ) {
        message("Training process " . ( $SUCCESS ? "finished" : "aborted" ) );
    }
}

###############################################################################
# Helper functions

sub all_exist {
    my @TEST     = @_;
    my $COMPLETE = 1;
    for my $t (@TEST) {
        $COMPLETE = 0 if ( not -e $t );
    }
    return $COMPLETE;
}

sub message {
    my $message     = shift;
    my $time        = POSIX::strftime( "%m/%d/%Y %H:%M:%S", localtime() );
    my $log_message = $time . "\t$message\n";
    print STDERR $log_message;
    if ($LOG) {
        print LOG $log_message;
    }
}

sub execute {
    my $command = shift;
    message("Executing:\t$command");
    my $ret = system($command);
    if ( $ret != 0 ) {
        message("Command '$command' finished with return status $ret");
        message("Aborting and killing parent process");
        kill( 2, $PID );
        die;
    }
}

sub setup_data {
    my $description = shift;
    my $input       = shift;
    my $output      = shift;

    my $path = File::Spec->rel2abs($input);
    if ( not -e $path ) {
        die "Cannot find $description: $path\n";
    }
    if ( not -e $output ) {
        execute("ln -f -s $path $output");
    }
    return $output;
}

sub compare_counts {
    my ( $file1, $file2 ) = @_;

    message("Counting lines of '$file1'");
    my $count1 = `wc -l $file1` + 0;
    message("Counted $count1 lines");

    message("Counting lines of '$file2'");
    my $count2 = `wc -l $file2` + 0;
    message("Counted $count2 lines");

    if ( $count1 != $count2 ) {
        message("Number of lines differs!");
    }

    return $count1 == $count2;
}

sub moses_steps {
    my ( $COMMAND, $STEPS, $CHECK ) = @_;
    my @CHECK_FILES = @$CHECK;

    my $EXIST1 = 1;
    foreach my $file (@CHECK_FILES) {
        if ( not $file or not -e $file or ( $file =~ /.gz/ && ( -s $file <= 20 ) ) ) {
            # file does not exist (or is a .gz with size 20)
            $EXIST1 = 0;
            last;
        }
    }
    if ($EXIST1) {
        my $outcomes = join( ", ", @CHECK_FILES );
        message("All outcomes ($outcomes) already exist, skipping steps $STEPS.");
        return;
    }

    execute("$COMMAND --do-steps $STEPS");

    foreach my $file (@CHECK_FILES) {
        if ( -e $file && ( $file !~ /.gz/ || ( -s $file > 20 ) ) ) {
            # file exists (or is a .gz with size more than 20)
            chomp( my $SIZE = `du -sh $file` );
            message("Outcome '$file' exists and has file size $SIZE.");
        }
        else {
            message("Moses steps $STEPS finished, but outcome '$file' is missing.");
            message("Aborting!");
            exit(1);
        }
    }
    message("Moses steps $STEPS finished.");
}
