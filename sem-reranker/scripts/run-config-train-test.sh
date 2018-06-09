#!/bin/bash


progName=$(basename "$BASH_SOURCE")

forceOpt=""
featsOpts=""

refCorpusColNo=

function usage {
  echo
  echo "Usage: $progName [options] <config file> <template dir> <ref data dir> <model dir> <work dir>"
  echo
  echo "  <template dir> is a directory containing the template file to use with CRF++"
  echo "  It can contain several files, the one to be used is specified in the config file"
  echo "  config file as: "
  echo "    crfTemplate=<filename>"
  echo "  Remark: <filename> must not contain the path." 
  echo
  echo "  <ref data dir>  is a directory containing  the corpus to use as reference with the"
  echo "   semantic reranker. It can contain several files, the one to be used is specified"
  echo "   in the config file config file as: "
  echo "     corpusFile=<filename>[:lemma]"
  echo "   where the optional [:lemma] part indicates to use option -l with the semantic"
  echo "   reranker. <filename> can for instance be the same as the input training file,"
  echo "   or a tokenized version of Europarl."
  echo "   Remark: token is supposed to be in column 2 and lemma in column 4 for the"
  echo "            input data; a reference file has the token as 2nd column."
  echo "   Remark: <filename> must not contain the path." 
  echo
  echo "  Options:"
  echo "    -h this help"
  echo "    -l <train input dir> learn model from <train input dir>, which must contain"
  echo "       files train.parsemetsv and train.conllu."
  echo "    -a <test input dir> apply model to <test input dir> which must contain"
  echo "       files test.parsemetsv and test.conllu."
#  echo "    -o <options for features> options for the program context-features (quoted)"
  echo "    -f force recomputing features even if already there"
  echo "    -c <CRF directory> for the CRF CV files used for training the reranker, use"
  echo "       the data previously generated in this directory. This is useful for"
  echo "       example when running CV experiments with the reranker. Caution: the"
  echo "       directory is supposed to have been generated with the same CRF parameters"
  echo "       and the same data, of course. Ignored in testing mode."
  echo "       Remark: unless the global model exists in <model dir>, it will be"
  echo "               recomputed (since the directory contains only the CV files)."
  echo
}




#twdoc readFromParamFile $file $name $errMsgPrefix [$separator] [$noWarningIfEmpty] [$returnThisValueIfNotDefined] [$assignToThisNameInstead]
#
# Reads the value of a parameter ``$name`` in a parameters file
# ``$file`` and assigns it to a variable with the same name ``$name``.
#
# Remark: Same idea as something like ``myvar=$(readFromParamFile
# ...)``, but here the function can make the calling script die if
# there is an error.
#
# * $errMsgPrefix: in case of error, prints this before the error message (used to identify the calling script)
# * $separator: separator used in the parameters file between the name and the value. Default: ``=``.
# * $noWarningIfEmpty: by default a warning is printed to STDERR if the parameter exists but has no value. Set this argument to anything but empty not to print any warning.
# * $returnThisValueIfNotDefined: by default an error is raised and the script is stopped if the parameter is not defined. If this argument is defined, its value is simply returned instead.
# * *assignToThisNameInstead: if defined, ``$name`` is the name read from the file but the value is assigned to the variable ``$assignToThisNameInstead``
#
#/twdoc
function readFromParamFile {
    local file="$1"
    local name="$2"
    local errMsgPrefix="$3"
    local sepa="$4"
    local noWarningIfEmpty="$5" # left empty => warning if defined but empty value
    local returnThisValueIfNotDefined="$6" # left empty => error and exit if not defined
    local assignToThisNameInstead="$7" # if defined, $name is the name read from the file but the value is assigned to this name

    if [ -z "$sepa" ]; then
        sepa="="
    fi
    if [ ! -f  "$file" ]; then
	echo "Error: cannot open config file '$file'" 1>&2
	exit 3
    fi
    line=$(grep "^$name$sepa" "$file" | tail -n 1)
    if [ -z "$line" ]; then
        if [ -z "$returnThisValueIfNotDefined" ]; then
            echo "${errMsgPrefix}Error: parameter '$name' not found in parameter file '$file'" 1>&2
            exit 1
        else
            res="$returnThisValueIfNotDefined"
        fi
    else
        res=$(echo "$line" | cut -d "$sepa" -f 2- )
        if [ -z "$noWarningIfEmpty" ] && [ -z "$res" ]; then
            echo "${errMsgPrefix}Warning: parameter '$name' is defined but empty in parameter file '$file'" 1>&2
        fi
    fi
    if [ -z "$assignToThisNameInstead" ]; then
        eval "$name=\"$res\""
    else
        eval "$assignToThisNameInstead=\"$res\""
    fi
}


function absPath {
    d="$1"
    pushd "$d" >/dev/null
    pwd
    popd >/dev/null
}


OPTIND=1
while getopts 'hfl:a:c:' option ; do 
    case $option in
	"h" ) usage
 	      exit 0;;
	"l" ) trainDir="$OPTARG";;
	"a" ) testDir="$OPTARG";;
	"f" ) forceOpt="-f";;
	"c" ) crfDir="$OPTARG";;
 	"?" ) 
	    echo "Error, unknow option." 1>&2
            printHelp=1;;
    esac
done
shift $(($OPTIND - 1))
if [ $# -ne 5 ]; then
    echo "Error: expecting 5 args." 1>&2
    printHelp=1
fi

if [ ! -z "$printHelp" ]; then
    usage 1>&2
    exit 1
fi
configFile="$1"
templateDir="$2"
refDataDir="$3"
modelDir="$4"
workDir="$5"

if [ -z "$trainDir" ] && [ -z "$testDir" ]; then
    echo "Error: at least one of -a or -l must be supplied" 1>&2
    exit 1
fi

if [ ! -f "$configFile" ]; then
    echo "Error: cannot open config file '$configFile'" 1>&2
    exit 2
fi
if [ ! -d "$templateDir" ]; then
    echo "Error: no directory '$templateDir' found" 1>&2
    exit 2
fi
if [ ! -d "$refDataDir" ]; then
    echo "Error: no directory '$refDataDir' found" 1>&2
    exit 2
fi

[ -d "$workDir" ] || mkdir "$workDir"


featsOpts=""
readFromParamFile "$configFile" "refCorpus"
#if [ "$refCorpus" == "EP" ]; then
#    corpusFile="$workDir/ep.tok"
#    featsOpts="$featsOpts -l 0"
#elif [ "$refCorpus" == "MWEDataToken" ]; then
#    corpusFile="$workDir/reference"
#    featsOpts="$featsOpts -l 0"
#elif [ "$refCorpus" == "MWEDataLemma" ]; then
#    corpusFile="$workDir/reference"
#    featsOpts="$featsOpts -l 1"
#else 
#    echo "Error: invalid option '$refCorpus' for parameter 'refCorpus' " 1>&2
#    exit 3
#fi
refCorpusOpt=${refCorpus%:lemma}
if [ "$refCorpusOpt" != "$refCorpus" ]; then 
    refCorpus=$refCorpusOpt
    featsOpts="$featsOpts -l 1"
else
    featsOpts="$featsOpts -l 0"
fi
corpusFile="$refDataDir/$refCorpus"

if [ "$refCorpus" != "NONE" ] && [ ! -f "$corpusFile" ]; then
    echo "Error: no reference data $corpusFile" 1>&2
    exit 6
fi

readFromParamFile "$configFile" "crfTemplate"
readFromParamFile "$configFile" "crfCValue"

readFromParamFile "$configFile" "learnMethod"
wekaParams=$(weka-id-to-parameters.sh "$learnMethod")

readFromParamFile "$configFile" minFreq
readFromParamFile "$configFile" nMostFreq
readFromParamFile "$configFile" halfWindowSize
readFromParamFile "$configFile" normalizeContexts
readFromParamFile "$configFile" simMeasure
readFromParamFile "$configFile" minConfidence
readFromParamFile "$configFile" onlyMean
readFromParamFile "$configFile" windowIncludeWordsINexpr
readFromParamFile "$configFile" windowMultipleOccurrencesPosition
readFromParamFile "$configFile" featConfidence
readFromParamFile "$configFile" featGroups
readFromParamFile "$configFile" featTypes
readFromParamFile "$configFile" featStd


featsOpts="$featsOpts -m $minFreq -n $nMostFreq -w $halfWindowSize -c $normalizeContexts -s $simMeasure -p $minConfidence -o $onlyMean -a $windowIncludeWordsINexpr -b $windowMultipleOccurrencesPosition -C $featConfidence -g $featGroups -t $featTypes -f $featStd"


[ -d "$workDir" ] || mkdir "$workDir"
[ -d "$modelDir" ] || mkdir "$modelDir"

trainDirAbs=$(absPath "$trainDir")
templateDirAbs=$(absPath "$templateDir")
modelDirAbs=$(absPath "$modelDir")


if [ ! -z "$trainDir" ]; then
    if [ ! -f "$trainDir/train.parsemetsv" ] || [ ! -f "$trainDir/train.conllu" ] ; then
	echo "Error: $trainDir does not contain train.parsemetsv and train.conllu" 1>&2
	exit 4
    fi

	if [ -s "$modelDir/crfpp.model" ] && [ -z "$forceOpt" ]; then
	    echo "Warning: CRF model already exist, skipping" 1>&2
	else
	    echo "Step 1: CRF, preparing for CV process"

	    pushd "$workDir" >/dev/null
	    cv-prepdata.sh "$trainDirAbs" train 170128.297316 "--bio"  || exit $?
	    popd >/dev/null

	    echo "  Training global model..."
	    # also train a global model from the whole training set:
	    crf_learn  -c "$crfCValue"  "$templateDir/$crfTemplate"  "$workDir/rnd.bio"  "$modelDir/crfpp.model"  || exit $?

	fi


    if [ "$refCorpus" != "NONE" ]; then
	if [ -s "$modelDir/weka.model" ] && [ -z "$forceOpt" ]; then
	    echo "Warning: sem reranker Weka model already exist, skipping" 1>&2
	else

	    if [ ! -z "$crfDir" ]; then
		if [ ! -d  "$crfDir" ]; then
		    echo "Error: cannot find directory '$crfDir'" 1>&2
		    exit 6
		fi
		echo "Using previous generated data for CRF from $crfDir"
		crfDirAbs=$(absPath "$crfDir")
		pushd "$workDir" >/dev/null
		ln -s "$crfDirAbs/cv-top10-predictions-reranker-training.bio"
		popd >/dev/null
		
	    else
		echo "Step 2: CRF, running CV process to prepare data for semantic reranker"
		pushd "$workDir" >/dev/null
		cv-runexps.sh . "$templateDirAbs/$crfTemplate" "$crfCValue" "-n 10"  || exit $?
		popd >/dev/null

		# concatenate the predictions obtained from CV to use as training for the reranker
		for n in $(seq 0 4); do
		    cat "$workDir/rnd.bio.tst.predict.$n"
		    echo # add empty line
		done >"$workDir/cv-top10-predictions-reranker-training.bio"
	    fi

	    echo "Step 3: semantic reranker"
	    if [ ! -f "$corpusFile" ]; then
		echo "Warning: no corpus file '$corpusFile' found, skipping reranker" 1>&2
	    else
		eval "train-test.sh -l '$workDir/cv-top10-predictions-reranker-training.bio' $forceOpt -o \"$featsOpts\" \"$workDir\" \"$modelDir/weka.model\" \"$corpusFile\" \"$wekaParams\""
	    fi
	    
	fi
    fi
fi

if [ ! -z "$testDir" ]; then
    if [ ! -f "$testDir/test.parsemetsv" ] || [ ! -f "$testDir/test.conllu" ] ; then
	echo "Error: $testDir does not contain test.parsemetsv and test.conllu" 1>&2
	exit 4
    fi
    if [ ! -s "$modelDir/crfpp.model" ]; then
	echo "Error: no CRF++ model found in $modelDir" 1>&2
	exit 5
    fi

    echo "Step 1: converting to internal bio format"
    parseme2bio.pl --ptsv "$testDir/test.parsemetsv" -conll "$testDir/test.conllu" --output "$workDir/test-input.bio" --bio || exit $?

    
    echo "Step 2: Applying CRF model"
    testOpts=""
    if [ "$refCorpus" != "NONE" ]; then
	testOpts="-n 10"
    fi
    eval "crf_test $testOpts -m \"$modelDir/crfpp.model\" -c \"$crfCValue\" -o \"$workDir/crfpp-predict.bio\" \"$workDir/test-input.bio\"" || exit $?


    if [ "$refCorpus" != "NONE" ]; then
	if [ ! -s "$modelDir/weka.model" ]; then
	    echo "Error: no Weka model (semantic reranker) found in $modelDir" 1>&2
	    exit 5
	fi
	echo "Step 3: Applying semantic reranker"
	eval "train-test.sh -a '$workDir/crfpp-predict.bio' $forceOpt -o \"$featsOpts\" \"$workDir\" \"$modelDir/weka.model\" \"$corpusFile\" \"$wekaParams\""
	# final output = output.parsemetsv ready for evaluation
    else
	bio4eval.pl --input "$workDir/crfpp-predict.bio" --output "$workDir/output.parsemetsv"
    fi

    evaluate.py "$testDir/test.parsemetsv" "$workDir/output.parsemetsv" >"$workDir/test-eval.out" || exit $?
    
fi

