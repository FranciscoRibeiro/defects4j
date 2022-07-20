#!/bin/sh

#This script computes the relevant tests from the loaded classes of all projects in Defects4J

#Bugs are executed in parallel, so variables/functions need to be exported for sub shells to have them in scope
set -a 

GET_RELEVANT_TESTS="framework/util/get_relevant_tests.pl"
MAIN_OUT_DIR="framework/projects"

get_relevant_tests_of_loaded_classes () {
	local proj="$1"
	local bug="$2"
	local out="$MAIN_OUT_DIR/$proj/relevant_tests_of_loaded_classes"
	mkdir -p "$out"
	$GET_RELEVANT_TESTS -p "$proj" -b "$bug" -o "$out" --loaded > logs/"$proj/$bug.txt" 2>&1
}

INPUTS=()
for proj in $(defects4j pids)
do
	mkdir -p logs/"$proj"
	for bug in $(defects4j bids -p "$proj")
	do
		INPUTS+=("$proj $bug")
	done
done

printf "%s\n" "${INPUTS[@]}" | parallel -j 1 -C' ' get_relevant_tests_of_loaded_classes {1} {2}
