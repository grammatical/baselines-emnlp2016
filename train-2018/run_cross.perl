#!/usr/bin/perl

use strict;
use Getopt::Long;
use Parallel::ForkManager;
use File::Spec;
use File::Basename;
use YAML::XS 'LoadFile';

my $PID = $$;
$SIG{TERM} = $SIG{INT} = $SIG{QUIT} = sub { die; };

###############################################################################
# Load configuration file

my $CONFIG_FILE = undef;
my $DIR         = undef;
my $CONTINUE    = 0;
my $SKIP_EVAL   = 0;

GetOptions(
    "f|config=s"   => \$CONFIG_FILE,
    "d|work-dir=s" => \$DIR,
    "c|continue"   => \$CONTINUE
);

die "Specify configuration file with -f/--config option.\n"
    unless $CONFIG_FILE;
my $CONFIG = LoadFile($CONFIG_FILE);

###############################################################################
# Set up options

# experiment
$DIR = $CONFIG->{experiment}->{dir} unless $DIR;
my $CROSS   = $CONFIG->{experiment}->{cross};
my $N       = $CONFIG->{experiment}->{n} || 4;
my $JOBS    = $CONFIG->{experiment}->{jobs} || 4;
my $THREADS = $CONFIG->{experiment}->{threads} || 16;

die "Specify the working directory\n" unless $DIR;

# features
my $LM          = $CONFIG->{features}->{lm};
my $WCLM        = $CONFIG->{features}->{wclm};
my $POSLM       = $CONFIG->{features}->{poslm};
my $NPLM        = $CONFIG->{features}->{nplm};
my $BINPLM      = $CONFIG->{features}->{binplm};
my $OSM         = $CONFIG->{features}->{osm};
my $ESM         = $CONFIG->{features}->{esm};
my $LEVENSHTEIN = $CONFIG->{features}->{levenshtein};
my $EDITOPS     = $CONFIG->{features}->{editops};
my $CHAROPS     = $CONFIG->{features}->{charops};
my $SPARSE      = $CONFIG->{features}->{sparse};
my $AVGSPARSE   = $CONFIG->{features}->{avgsparse};
my $SPARSEOPT
    = "CorrectionPattern factor=0 context=1 context-factor=1\nCorrectionPattern factor=1";
my $WCINPUT     = !!$SPARSE;
my $NMT         = $CONFIG->{features}->{nmt};

# data
my $DATA         = $CONFIG->{data}->{dev_orig};
my %TESTS_M2     = %{$CONFIG->{data}->{tests_m2}};
my %TESTS_GLEU   = %{$CONFIG->{data}->{tests_gleu}};
my $MORE         = $CONFIG->{data}->{train_txt};
my $MORE_RELEASE = undef;
my $PTAUGMENT    = $CONFIG->{data}->{augmented_pt};

die "Specify the annotated training data\n"
    if ( not $DATA or not -e $DATA );

my $PATH_TC     = $CONFIG->{data}->{tc};
my $PATH_BPE    = $CONFIG->{data}->{bpe};

my $PATH_LM     = $CONFIG->{data}->{lm_path};
my $PATH_WCLM   = $CONFIG->{data}->{wclm_path};
my $PATH_POSLM  = $CONFIG->{data}->{poslm_path};
my $PATH_WC     = $CONFIG->{data}->{wc_path};
my $PATH_POS    = $CONFIG->{data}->{pos_path};
my $PATH_NPLM   = $CONFIG->{data}->{nplm_path};
my $PATH_BINPLM = $CONFIG->{data}->{binplm_path};
my $PATH_NMT    = $CONFIG->{data}->{nmt_path};

# tuning
# default metric is 'm2'
my $METRIC      = $CONFIG->{tuning}->{metric} || 'm2';
my $BLEU        = $METRIC eq 'bleu';
my $GLEU        = $METRIC eq 'gleu';
my $M2          = $METRIC eq 'm2';
# default algorithm is 'mert'
my $ALGORITHM   = $CONFIG->{tuning}->{algorithm};
my $PRO         = $ALGORITHM eq 'pro';
my $PROSTART    = $ALGORITHM eq 'prostart';
my $KBMIRASTART = $ALGORITHM eq 'kbmirastart';
my $BMIRA       = $ALGORITHM eq 'bmira';
my $REMERT      = $CONFIG->{tuning}->{remert} || 2;
my $MER_ADJUST  = 0.15;
my $MAXIT       = $CONFIG->{tuning}->{max_it} || 5;
my $MERT_JOBS   = $CONFIG->{tuning}->{jobs} || $JOBS;

my $NMT_PIPE    = $CONFIG->{tuning}->{nmt_pipeline};
my $NMT_CMD     = $CONFIG->{tuning}->{nmt_cmd};

# constants
my $BETA             = 0.5;
my $FACTOR_DELIMITER = '|';

# paths
my $ROOT         = $CONFIG->{root};
my $SCRIPTS      = "$ROOT/scripts";
my $MOSESDIR     = $CONFIG->{dir}->{moses};
my $MOSESDECODER = "$MOSESDIR/bin/moses";
my $PARALLEL     = "parallel --no-notice --pipe -k -j 8 --block 1M perl";
my $SUBWORD      = $CONFIG->{dir}->{subword_nmt};
my $M2SCORER     = $CONFIG->{dir}->{m2scorer};

# pre- and postprocessing commands
my $TRUECASE
    = "$PARALLEL $MOSESDIR/scripts/recaser/truecase.perl --model $PATH_TC";
my $DETRUECASE  = "$MOSESDIR/scripts/recaser/detruecase.perl";
my $CLEAN       = "perl -pe 's/^\\s+|\\s+\$//g; \$_ = \"\$_\\n\"'";
my $ESCAPE      = "$MOSESDIR/scripts/tokenizer/escape-special-chars.perl";
my $DEESCAPE    = "$MOSESDIR/scripts/tokenizer/deescape-special-chars.perl";
my $BPE         = "$SUBWORD/subword_nmt/apply_bpe.py -c $PATH_BPE";
my $DEBPE       = "sed 's/@@ //g'";
my $PREPROC     = "$TRUECASE | $ESCAPE | $BPE";
my $POSTPROC    = "$DEBPE | $DEESCAPE | $DETRUECASE";

die "Set up the root directory\n"           if ( not $ROOT     or not -e $ROOT );
die "Set up the path to Moses\n"            if ( not $MOSESDIR or not -e $MOSESDIR );
die "Set up the path to truecaser model\n"  if ( not $PATH_TC  or not -e $PATH_TC );
die "Set up the path to BPE codes\n"        if ( not $PATH_BPE or not -e $PATH_BPE );

my $WC_FACT = "";
$WC_FACT = " | perl $SCRIPTS/anottext.pl -f $PATH_WC" if $WCINPUT;

###############################################################################
# Set options for train_smt.pl

my $TRAIN_OPTIONS = " --delimiter '$FACTOR_DELIMITER' --jobs $THREADS";

$TRAIN_OPTIONS .= " --moses-dir $MOSESDIR";
$TRAIN_OPTIONS .= " --bin-dir " . $CONFIG->{dir}->{moses_bin};
$TRAIN_OPTIONS .= " --scripts-dir $SCRIPTS";

$TRAIN_OPTIONS .= " --levenshtein"          if ($LEVENSHTEIN);
$TRAIN_OPTIONS .= " --editops"              if ($EDITOPS);
$TRAIN_OPTIONS .= " --charops"              if ($CHAROPS);
$TRAIN_OPTIONS .= " --lm $PATH_LM"          if ($LM);
$TRAIN_OPTIONS .= " --wclm $PATH_WCLM"      if ($WCLM);
$TRAIN_OPTIONS .= " --wc $PATH_WC"          if ($WCLM);
$TRAIN_OPTIONS .= " --poslm $PATH_POSLM"    if ($POSLM);
$TRAIN_OPTIONS .= " --pos $PATH_POS"        if ($POSLM);
$TRAIN_OPTIONS .= " --nplm $PATH_NPLM"      if ($NPLM);
$TRAIN_OPTIONS .= " --binplm $PATH_BINPLM"  if ($BINPLM);
$TRAIN_OPTIONS .= " --osm"                  if ($OSM);
$TRAIN_OPTIONS .= " --esm"                  if ($ESM);
$TRAIN_OPTIONS .= " --nmt $PATH_NMT"        if ($NMT);

$TRAIN_OPTIONS .= " --ptaugment"            if ($PTAUGMENT);

###############################################################################
# Create working directory

$DIR = File::Spec->rel2abs($DIR);
`mkdir -p $DIR`;

# Copy configuration file
`cp $CONFIG_FILE $DIR/config.yml`;

###############################################################################
# Prepare data

my $NUMREFS = 1;
if ($CROSS) {
    message('Preparing CV data set');
    unless ( -s "$DIR/full.txt" ) {
        execute("cat $DATA | $SCRIPTS/make_parallel.perl > $DIR/full.txt");
    }

    unless ( -s "$DIR/full.esc.m2" ) {
        execute("cat $DATA | sed 's/|||/abcSEPabc/g' | $ESCAPE | sed 's/abcSEPabc/|||/g' > $DIR/full.esc.m2");
    }
}
else {
    $NUMREFS = int(`head -n1 $DATA | grep -Po "\t" | wc -l`);
    message("Preparing tuning set with $NUMREFS ref(s)");

    unless ( -s "$DIR/full.txt" ) {
        execute("cp $DATA $DIR/full.txt");
    }
    unless ( -s "$DIR/full.esc.txt" ) {
        `cut -f1 $DIR/full.txt | $ESCAPE > $DIR/full.esc.src`;
        foreach my $i ( 2 .. $NUMREFS + 1 ) {
            my $i0 = $i - 2;
            `cut -f$i $DIR/full.txt | $ESCAPE > $DIR/full.esc.ref$i0`;
        }
        `paste $DIR/full.esc.src $DIR/full.esc.ref? > $DIR/full.esc.txt`;
    }
}

if ($CROSS) {
    message("Splitting training data set into $N-chunks");
    unless ( -s "$DIR/part.00" and -s "$DIR/part." . sprintf( "%02d", $N ) ) {
        my $lines = int( `wc -l $DIR/full.txt` / $N ) + 1;
        message("Lines per part: $lines");
        `split -a 2 -d -l $lines $DIR/full.txt $DIR/part.`;
    }

    message("Preprocessing training data chunks");
    foreach my $j ( 0 .. $N - 1 ) {
        my $j0 = sprintf( "%02d", $j );
        `cut -f1 $DIR/part.$j0 | $PREPROC > $DIR/part.$j0.lc.err` unless ( -e "$DIR/part.$j0.lc.err" );
        `cut -f2 $DIR/part.$j0 | $PREPROC > $DIR/part.$j0.lc.cor` unless ( -e "$DIR/part.$j0.lc.cor" );
    }

    my $pm = new Parallel::ForkManager($JOBS);

    foreach my $i ( 0 .. $N - 1 ) {
        $pm->start() and next;

        message("Preparing data for chunk $i");
        my $i0 = sprintf( "%02d", $i );
        my $curr = "$DIR/cross.$i0";

        exit(0) if ( -s "$curr/work.err-cor/binmodel.err-cor/moses.ini" );

        `mkdir -p $curr`;
        unless ( -s "$curr/train.lc.txt" ) {
            `> $curr/train.lc.txt`;    # Clear once;

            foreach my $j ( 0 .. $N - 1 ) {
                my $j0 = sprintf( "%02d", $j );
                if ( $j != $i ) {
                    `paste $DIR/part.$j0.lc.err $DIR/part.$j0.lc.cor >> $curr/train.lc.txt`;
                }
                else {
                    `cp $DIR/part.$j0.lc.err $curr/test.lc.err` unless ( -e "$curr/test.lc.err" );
                    `cp $DIR/part.$j0.lc.cor $curr/test.lc.cor` unless ( -e "$curr/test.lc.cor" );

                    `cat $curr/test.lc.err | $DEBPE | $SCRIPTS/ann_from_txt.perl $DIR/full.esc.m2 > $curr/test.lc.m2`
                        unless ( -e "$curr/test.lc.m2" );
                }
            }

            if ( not -e "$curr/train.lc.err" or not -e "$curr/train.lc.cor") {
                message("Adding more training data for chunk $i: $MORE");
                `cat $MORE >> $curr/train.lc.txt` if ( -s $MORE );

                execute("cut -f1 $curr/train.lc.txt | $CLEAN > $curr/train.lc.err");
                execute("cut -f2 $curr/train.lc.txt | $CLEAN > $curr/train.lc.cor");
            }
        }

        if ( not -s "$curr/work.err-cor/binmodel.err-cor/moses.ini" ) {
            message("Running translation model training for chunk $i");

            my $train_cross
                = "$ROOT/train_smt.perl $TRAIN_OPTIONS"
                . " --filter $curr/test.lc.err"
                . " --lm-data $curr/train.lc.cor"
                . " -w $curr/work.err-cor"
                . " -c $curr/train.lc"
                . " --log $curr/log.txt";
            execute($train_cross);

            if ($SPARSE) {
                my $abscurr = File::Spec->rel2abs($curr);
                add_sparse("$abscurr/work.err-cor/binmodel.err-cor/moses.ini");
            }
        }

        $pm->finish();
    }
    $pm->wait_all_children();
}

###############################################################################
# Prepare release

message("Preparing release models");
my $RDIR = "$DIR/release";
`mkdir -p $RDIR`;

if ( not -e "$RDIR/train.lc.err" or not -e "$RDIR/train.lc.cor" ) {
    if ( $CROSS ) {
        `cat $DIR/part.*.lc.err > $RDIR/train.lc.err`;
        `cat $DIR/part.*.lc.cor > $RDIR/train.lc.cor`;
        `paste $RDIR/train.lc.err $RDIR/train.lc.cor > $RDIR/train.lc.txt`;
    }

    $MORE_RELEASE = $MORE;
    message("Adding more training data for release: $MORE_RELEASE");
    `cat $MORE_RELEASE >> $RDIR/train.lc.txt` if ( -s $MORE_RELEASE );

    `cut -f1 $RDIR/train.lc.txt | $CLEAN > $RDIR/train.lc.err`;
    `cut -f2 $RDIR/train.lc.txt | $CLEAN > $RDIR/train.lc.cor`;
}

if (not $CROSS) {
    if ( not -e "$RDIR/test.lc.txt" or not -e "$RDIR/test.lc.err" ) {
        `cut -f1 $DIR/full.txt | $PREPROC > $RDIR/test.lc.err`;
        `cp $DIR/full.esc.txt $RDIR/test.lc.txt`;

    }
}

###############################################################################
# Prepare test sets

my $FILTER = "";

my $tst = new Parallel::ForkManager($JOBS);
foreach my $testset ( keys %TESTS_M2 ) {
    my $testfile = $TESTS_M2{$testset};
    $tst->start() and next;

    if ( not -s $testfile ) {
        message("Specified test set $testset = $testfile is not found!");
        exit(1);
    }
    prepare_test_set( $testset, $testfile, $RDIR );
    $FILTER .= " --filter $RDIR/$testset.lc.err";
    $tst->finish();
}

foreach my $testset ( keys %TESTS_GLEU ) {
    my $testfile = $TESTS_GLEU{$testset};
    $tst->start() and next;

    if ( not -s $testfile ) {
        message("Specified test set $testset = $testfile is not found!");
        exit(1);
    }
    prepare_test_set( $testset, $testfile, $RDIR, 'gleu' );
    $FILTER .= " --filter $RDIR/$testset.lc.err";
    $tst->finish();
}
$tst->wait_all_children();

###############################################################################
# Training release

if ( not -s "$RDIR/work.err-cor/binmodel.err-cor/moses.ini" ) {
    message("Running translation model training for release");

    my $train_release
        = "$ROOT/train_smt.perl $TRAIN_OPTIONS"
        . $FILTER
        . " -w $RDIR/work.err-cor -c $RDIR/train.lc"
        . " --log $RDIR/log.txt";
    execute($train_release);

    if ($SPARSE and not $CROSS) {
        my $abs = File::Spec->rel2abs($RDIR);
        `cp $abs/work.err-cor/binmodel.err-cor/moses.ini $abs/work.err-cor/binmodel.err-cor/moses.ini.nosparse`;
        add_sparse("$abs/work.err-cor/binmodel.err-cor/moses.ini");
    }
}

###############################################################################
# Evaluate with standard weights

unless ($NMT) {
    my $evl = new Parallel::ForkManager($JOBS);
    foreach my $testset ( keys %TESTS_M2 ) {
        $evl->start() and next;
        print translate_test_set(
            $testset, "moses.ini", "nomert", "standard weights"
        ) if ( not -e "$RDIR/eval.m2.$testset.nomert.txt");
        $evl->finish();
    }
    foreach my $testset ( keys %TESTS_GLEU ) {
        $evl->start() and next;

        evaluate("# Evaluation of $testset / raw source",
            "$RDIR/$testset.err",
            "$RDIR/$testset.txt",
            "$RDIR/eval.gleu.$testset.source.txt",
            "gleu"
        ) if ( not -e "$RDIR/eval.gleu.$testset.source.txt" );

        print translate_test_set(
            $testset, "moses.ini", "nomert", "standard weights", "gleu"
        ) if ( not -e "$RDIR/eval.gleu.$testset.nomert.txt");
        $evl->finish();
    }
    $evl->wait_all_children();
}

###############################################################################
# Run MERT

if ($REMERT) {
    if ( $MER_ADJUST and $CROSS ) {
        my $mer = new Parallel::ForkManager($JOBS);
        foreach my $i ( 0 .. $N - 1 ) {
            $mer->start() and next;

            my $i0 = sprintf( "%02d", $i );
            my $abscurr = File::Spec->rel2abs("$DIR/cross.$i0");

            if ( not -s "$abscurr/test.lc.mer.err" or not -s "$abscurr/test.lc.mer.cor" ) {
                message("Adjusting MER in chunk $i0");

                my $mercmd
                    = "$SCRIPTS/greedy_mer.perl --mer $MER_ADJUST"
                    . " --m2in $abscurr/test.lc.m2"
                    . " --errout $abscurr/test.lc.mer.err --corout $abscurr/test.lc.mer.cor"
                    . " --m2out $abscurr/test.lc.mer.m2";
                execute($mercmd);

                execute("cat $abscurr/test.lc.mer.err | $PREPROC > $abscurr/test.lc.mer.err.tmp");
                execute("cat $abscurr/test.lc.mer.cor | $PREPROC > $abscurr/test.lc.mer.cor.tmp");

                execute("mv $abscurr/test.lc.mer.err.tmp $abscurr/test.lc.mer.err");
                execute("mv $abscurr/test.lc.mer.cor.tmp $abscurr/test.lc.mer.cor");
            }
            $mer->finish();
        }
        $mer->wait_all_children();
    }

    my $rm = new Parallel::ForkManager($JOBS);
    foreach my $run ( 1 .. $REMERT ) {
        message("Remerting #$run");

        $rm->start() and next;

        if (not -s "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini"
                or ($SPARSE and not -s "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse")) {

            if ($CROSS) {
                my $pmm = new Parallel::ForkManager($MERT_JOBS);

                foreach my $i ( 0 .. $N - 1 ) {
                    $pmm->start() and next;

                    my $i0 = sprintf( "%02d", $i );
                    my $curr = "$DIR/cross.$i0";

                    message("Optimizing chunk $i parameter weights, run $run");

                    if (not -e "$curr/work.err-cor/binmodel.err-cor/moses.mert.$run.ini") {
                        if (not -e "$curr/work.err-cor/tuning.$run/moses.ini") {
                            `rm -rf $curr/work.err-cor/tuning.$run/*` unless ($CONTINUE);

                            my $abscurr = File::Spec->rel2abs($curr);

                            my $mert_cmd = build_mert_command($abscurr, $run);
                            execute($mert_cmd, 1);
                            failsafe_for_kbmira($abscurr, $run, $mert_cmd) if ($BMIRA);
                        }
                        `cp $curr/work.err-cor/tuning.$run/moses.ini $curr/work.err-cor/binmodel.err-cor/moses.mert.$run.ini`;
                    }
                    $pmm->finish();
                } ### foreach ($0 .. $N-1)
                $pmm->wait_all_children();

                # this script creates moses.mert.*.ini.sparse file
                execute("$SCRIPTS/centroid.perl -d $DIR -i $run");

                my $cmd_reuse = "perl $SCRIPTS/reuse-weights.perl"
                    . " $DIR/cross.00/work.err-cor/binmodel.err-cor/moses.mert.$run.ini"
                    . " < $RDIR/work.err-cor/binmodel.err-cor/moses.ini"
                    . " > $RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini";
                execute($cmd_reuse);

                if ($SPARSE) {
                    `cp $DIR/cross.00/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse $RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse`;
                    add_sparse(
                        "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini",
                        "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse"
                    );
                }
            } ### if ($CROSS)
            else {
                message("Optimizing parameter weights, run $run");

                if (not -e "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini") {
                    if (not -e "$RDIR/work.err-cor/tuning.$run/moses.ini") {
                        `rm -rf $RDIR/work.err-cor/tuning.$run/*` unless ($CONTINUE);

                        my $abscurr = File::Spec->rel2abs($RDIR);

                        my $mert_cmd = build_mert_command($abscurr, $run);
                        execute($mert_cmd);
                        failsafe_for_kbmira($abscurr, $run, $mert_cmd) if ($BMIRA);
                    }
                }
                `cp $RDIR/work.err-cor/tuning.$run/moses.ini $RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini`;

                # this script creates moses.mert.*.ini.sparse file
                #execute("$SCRIPTS/centroid.perl -d $DIR -i $run -s release");

                if ($SPARSE) {
                    my $weights_ini = `grep "\\.sparse-weights" $RDIR/work.err-cor/tuning.$run/moses.ini`;
                    $weights_ini =~ s/^\s+|\s+$//g;

                    `cp $weights_ini $RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse`;
                    add_sparse(
                        "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini",
                        "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.$run.ini.sparse",
                        1
                    );
                }

            } ### else ($CROSS)
        }
        else {
            message("Remert is ready: $RDIR/work.err-cor/binmodel.err-cor/moses.mert.*.ini\n");
        }

        foreach my $testset ( keys %TESTS_M2 ) {
            print translate_test_set(
                $testset,
                "moses.mert.$run.ini", "mert.$run",
                "optimized weights ($METRIC/$run)"
            ) if ( not -e "$RDIR/eval.m2.$testset.mert.$run.txt");
        }
        foreach my $testset ( keys %TESTS_GLEU ) {
            print translate_test_set(
                $testset,
                "moses.mert.$run.ini", "mert.$run",
                "optimized weights ($METRIC/$run)",
                "gleu"
            ) if ( not -e "$RDIR/eval.gleu.$testset.mert.$run.txt");
        }
        $rm->finish();
    }
    $rm->wait_all_children();
    $CONTINUE = 0;
}

###############################################################################
# Average optimized weights

if ( $REMERT > 1 ) {
    my $inis  = join( " ", grep {/moses\.mert\.\d+\.ini/} <$RDIR/work.err-cor/binmodel.err-cor/moses.mert.*.ini> );

    if ( not -e "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.avg.ini" ) {
        `perl $SCRIPTS/centroid2.perl $inis $RDIR/work.err-cor/binmodel.err-cor/moses.mert.avg.ini`;
        if ($SPARSE and $AVGSPARSE) {
            add_sparse(
                "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.avg.ini",
                "$RDIR/work.err-cor/binmodel.err-cor/moses.mert.avg.ini.sparse",
                1
            );
        }
    }

    my $avg = new Parallel::ForkManager($JOBS);
    foreach my $testset ( keys %TESTS_M2 ) {
        $avg->start() and next;
        print translate_test_set(
            $testset,
            "moses.mert.avg.ini", "mert.avg",
            "averaged weights ($METRIC/final)"
        ) if ( not -e "$RDIR/eval.m2.$testset.mert.avg.txt");

        my $evals = join( " ", grep {/eval\.m2\.$testset\.mert\.\d+\.txt/} <$RDIR/eval.m2.*.txt> );
        `perl $SCRIPTS/stats.perl $evals > $RDIR/eval.m2.$testset.avg.stats.txt`;
        print `cat $RDIR/eval.m2.$testset.avg.stats.txt`;
        $avg->finish();
    }
    foreach my $testset ( keys %TESTS_GLEU ) {
        $avg->start() and next;
        print translate_test_set(
            $testset,
            "moses.mert.avg.ini", "mert.avg",
            "averaged weights ($METRIC/final)", "gleu"
        ) if ( not -e "$RDIR/eval.gleu.$testset.mert.avg.txt");

        my $evals = join( " ", grep {/eval\.gleu\.$testset\.mert\.\d+\.txt/} <$RDIR/eval.gleu.*.txt> );
        `perl $SCRIPTS/stats_gleu.perl $evals > $RDIR/eval.gleu.$testset.avg.stats.txt`;
        print `cat $RDIR/eval.gleu.$testset.avg.stats.txt`;
        $avg->finish();
    }
    $avg->wait_all_children();
}

###############################################################################
# MERT functions

sub build_mert_command {
    my $abscurr = shift;
    my $run = shift;

    my $MERT = "perl $MOSESDIR/scripts/training/mert-moses.pl";

    if ($MER_ADJUST and $CROSS) {
        if ($WCINPUT) {
            execute("cat $abscurr/test.lc.mer.err $WC_FACT > $abscurr/test.lc.mer.err.fact");
            $MERT .= " $abscurr/test.lc.mer.err.fact";
        } else {
            $MERT .= " $abscurr/test.lc.mer.err";
        }

        if ($BLEU) {
            $MERT .= " $abscurr/test.lc.mer.cor";
        } elsif ($GLEU) {
            execute("paste $abscurr/test.lc.mer.err $abscurr/test.lc.mer.cor > $abscurr/test.lc.mer.txt");
            $MERT .= " $abscurr/test.lc.mer.txt";
        } else {
            $MERT .= " $abscurr/test.lc.mer.m2";
        }
    }
    else {
        if ($WCINPUT) {
            execute("cat $abscurr/test.lc.err $WC_FACT > $abscurr/test.lc.err.fact");
            $MERT .= " $abscurr/test.lc.err.fact";
        } else {
            $MERT .= " $abscurr/test.lc.err";
        }

        if ($BLEU) {
            $MERT .= " $abscurr/test.lc.cor";
        } elsif ($GLEU) {
            $MERT .= " $abscurr/test.lc.txt";
        } else {
            $MERT .= " $abscurr/test.lc.m2";
        }
    }

    my $scorer = "M2SCORER";
    my $config = "truecase:false,beta:$BETA,max_unchanged_words:2,case:false";

    if ($BLEU) {
        message("Optimizing with BLEU");
        $scorer   = "BLEU";
        $config = "case:false";
    }
    elsif ($GLEU) {
        message("Optimizing with GLEU");
        $scorer   = "GLEU";
        $config = "lowercase:true,numrefs:$NUMREFS,smooth:1";
    }
    else {
        message("Optimizing with M2");
    }

    $MERT
        .= " $MOSESDECODER $abscurr/work.err-cor/binmodel.err-cor/moses.ini"
        . " --working-dir=$abscurr/work.err-cor/tuning.$run"
        . " --mertdir=$MOSESDIR/bin"
        . " --mertargs \"--sctype $scorer --scconfig $config\""
        . " --extractorargs \"--filter \\\"sed -ur -e 's/^( *)(.)/\\1\\u\\2/' -e 's/@@ //g'\\\"\""
        . " --no-filter-phrase-table"
        . " --nbest=100"
        . " --threads $THREADS --decoder-flags \"-threads $THREADS -fd '$FACTOR_DELIMITER'\""
        . " --maximum-iterations $MAXIT";

    if ($NMT_PIPE) {
        $MERT .= " --postprocess-nbest-translations \"$NMT_CMD\"";
    }

    if ($CONTINUE and -e "$abscurr/work.err-cor/tuning.$run/finished_step.txt") {
        $MERT .= " --continue";
    }

    if ($PRO) {
        $MERT .= " --pairwise-ranked --return-best-dev";
    }
    elsif ($BMIRA) {
        $MERT .= " --batch-mira --return-best-dev";
        if($M2) {
           $MERT .= " --batch-mira-args \"--sctype $scorer --scconfig $config --model-bg -D 0.001\"";
        } else {
           $MERT .= " --batch-mira-args \"--sctype $scorer --scconfig $config\"";
        }
    }
    elsif ($PROSTART) {
        $MERT .= " --pro-starting-point --return-best-dev";
    }
    elsif ($KBMIRASTART) {
        $MERT .= " --kbmira-starting-point --return-best-dev"
            . " --batch-mira-args \"--sctype $scorer --scconfig $config\"";
    }

    return $MERT;
}

# Failsafe for insane kbmira behaviour, resets last two iterations, restarts computations
sub failsafe_for_kbmira {
    my $abscurr = shift;
    my $run = shift;
    my $mert_cmd = shift;

    message("Failsafe for kBMira $abscurr/.../tuning.$run");
    my $finished_step = int(`cat $abscurr/work.err-cor/tuning.$run/finished_step.txt`);
    message("  finished step: $finished_step");

    my $repeat = 0;
    while ( $finished_step < $MAXIT and $repeat < 3 ) {
        my $prev1 = $finished_step;
        my $prev2 = $finished_step - 1;
        $finished_step = $finished_step - 2;

        my $BAC = "$abscurr/work.err-cor/tuning.$run/failed." . time();
        `mkdir -p $BAC`;
        `mv $abscurr/work.err-cor/tuning.$run/run$prev1.* $BAC/.`;
        `mv $abscurr/work.err-cor/tuning.$run/run$prev2.* $BAC/.`;
        `mv $abscurr/work.err-cor/tuning.$run/moses.ini $BAC/.`;
        `cp $BAC/run$prev2.sparse-weights $abscurr/work.err-cor/tuning.$run/.`;
        `echo $finished_step > $abscurr/work.err-cor/tuning.$run/finished_step.txt`;

        execute("$mert_cmd --continue", 1);

        $finished_step = int(`cat $abscurr/work.err-cor/tuning.$run/finished_step.txt`);
        $repeat++;
    }
}


###############################################################################
# Helper functions

sub prepare_test_set {
    my $name    = shift;
    my $data    = shift;
    my $dir     = shift;
    my $metric  = shift;

    message("Preparing test set: $name");

    if ( $metric eq 'gleu' ) {
        `cp $data $dir/$name.txt` unless (-e "$dir/$name.txt");
    } else {
        `cp $data $dir/$name.m2` unless (-e "$dir/$name.m2");
        `cat $data | $SCRIPTS/make_parallel.perl > $dir/$name.txt`
            unless (-e "$dir/$name.txt");
    }
    `cut -f1 $dir/$name.txt | tee $dir/$name.err | $PREPROC > $dir/$name.lc.err`
        if ( not -s "$dir/$name.lc.err" );
    `cut -f2 $dir/$name.txt | tee $dir/$name.cor | $PREPROC > $dir/$name.lc.cor`
        if ( not -s "$dir/$name.lc.cor" );
}

sub add_sparse {
    my $ini        = shift;
    my $weightFile = shift;
    my $overwrite  = shift;

    message("Adding sparse features to $ini");

    open( INI, "<", $ini ) or die "Could not open $ini\n";
    my @lines = <INI>;
    close(INI);

    open( INI, ">", $ini ) or die "Could not open $ini\n";
    my $c = 0;
    foreach my $line (@lines) {
        print INI $line;
        if ( not $overwrite and $WCINPUT and $line =~ /\[input-factors\]/ ) {
            $lines[ $c + 1 ] = "0\n1\n";
        }

        if ( not $overwrite and $line =~ /\[feature\]/ ) {
            if ($SPARSE) {
                print INI join( "\n", split( /\\n/, $SPARSEOPT ) ), "\n";
            }
        }

        # remove old weight file if already exists
        if ( $overwrite and $line =~ /\[weight-file\]/ ) {
            $lines[ $c + 1 ] = "$weightFile\n";
        }

        $c++;
    }

    if (not $overwrite and $weightFile) {
        print INI "\n[weight-file]\n";
        print INI "$weightFile\n\n";
    }

    close(INI);
}

sub translate_test_set {
    my $name        = shift;
    my $ini         = shift;
    my $infix       = shift;
    my $description = shift;
    my $metric      = shift // 'm2';

    message("Evaluating $name with $description");

    if ( not -s "$RDIR/$name.trans.$infix" ) {
        my $cmd_translate
            = "cat $RDIR/$name.lc.err"
            . " $WC_FACT"
            . " | $MOSESDECODER -f $RDIR/work.err-cor/binmodel.err-cor/$ini -fd '$FACTOR_DELIMITER' -threads $THREADS"
            . " > $RDIR/$name.trans.$infix";
        execute($cmd_translate);
    }
    if ($NMT_PIPE) {
        `mv $RDIR/$name.trans.$infix $RDIR/$name.trans.$infix.smt`;
        if ($name eq 'test2014') {
            execute("cat $RDIR/$name.trans.$infix.smt | python $SCRIPTS/split_long_sents.py -f $RDIR/$name.trans.$infix.merge | $NMT_CMD > $RDIR/$name.trans.$infix.tmp");
            execute("cat $RDIR/$name.trans.$infix.tmp | python $SCRIPTS/merge_long_sents.py -f $RDIR/$name.trans.$infix.merge > $RDIR/$name.trans.$infix");
            `rm -f $RDIR/$name.trans.$infix.merge $RDIR/$name.trans.$infix.tmp`;
        } else {
            execute("$NMT_CMD < $RDIR/$name.trans.$infix.smt > $RDIR/$name.trans.$infix");
        }
    }
    execute("cat $RDIR/$name.trans.$infix | $POSTPROC > $RDIR/$name.trans.$infix.cased");

    my $reffile = ($metric eq 'gleu') ? "$RDIR/$name.txt" : "$RDIR/$name.m2";
    evaluate(
        "# Evaluation of $name: $description ($ini)",
        "$RDIR/$name.trans.$infix.cased",
        $reffile,
        "$RDIR/eval.$metric.$name.$infix.txt",
        $metric
    );
}

sub evaluate {
    if ($SKIP_EVAL) {
        return;
    }

    my $description = shift;
    my $hyp_file    = shift;
    my $ref_file    = shift;
    my $evl_file    = shift;
    my $metric      = shift;

    # score with M2 metric
    my $hyp_lines = 0 + `wc -l $hyp_file`;
    my $ref_lines  = 0 + `grep -c "^S " $ref_file`;
    my $cmd
        = "python $M2SCORER/scripts/m2scorer.py"
        . " --beta $BETA"
        . " --max_unchanged_words 2"
        . " $hyp_file"
        . " $ref_file";

    # score with GLEU metric
    if ($metric eq 'gleu') {
        $ref_lines  = 0 + `wc -l $ref_file`;
        $cmd
            = "python $SCRIPTS/gleu_srcrefs.py"
            . " --hyp $hyp_file"
            . " --srcrefs $ref_file";
    }

    message("Evaluating '$description':\t$cmd");
    if ( $hyp_lines != $ref_lines ) {
        die("Evaluation stopped! Different number of lines: $hyp_lines != $ref_lines");
    }

    `echo "$description" > $evl_file`;
    `$cmd >> $evl_file`;
}

sub execute {
    my $command = shift;
    my $safe = shift // 0;

    message("Running command: $command");
    my $status = system($command);

    if ( $status != 0 ) {
        message("Command: $command\n\tfinished with non-zero status $status");
        if ( $safe != 1 ) {
            kill( 2, $PID );
            die;
        }
    }
}

sub message {
    my $message     = shift;
    my $time        = POSIX::strftime( "%m/%d/%Y %H:%M:%S", localtime() );
    my $log_message = $time . "\t$message\n";
    print STDERR $log_message;
}
