#!/bin/bash

#   This script generates a series of QSub submissions for read mapping.
#   The Burrows-Wheeler Aligner (BWA) and the Portable Batch System (PBS)
#   are required to use this script.

set -o pipefail

#   What are the dependencies for Read_Mapping?
declare -a Read_Mapping_Dependencies=(bwa)

#   A function to parse BWA settings
function ParseBWASettings() {
	local POSITIONALS='' # Create a string of positional arguments for BWA mem
	if [[ "${RESCUE}" == true ]]; then POSITIONALS="${POSITIONALS}"'-P '; fi # Add paired to the positionals
	if [[ "${INTERLEAVED}" == true ]]; then POSITIONALS="${POSITIONALS}"'-p '; fi # Add interleaved to the positionals
	if [[ "${SECONDARY}" == true ]]; then POSITIONALS='-a'; else SECONDARY=''; fi # Add secondary to the positionals
	if [[ "${APPEND}" == true ]]; then POSITIONALS="${POSITIONALS}"'-C '; fi # Add append to the positionals
	if [[ "${HARD}" == true ]]; then POSITIONALS="${POSITIONALS}"'-H '; fi # Add hard to the positionals
	if [[ "${SPLIT}" == true ]]; then POSITIONALS="${POSITIONALS}"'-M '; fi # Add split to the positionals
	if [[ "${VERBOSITY}" == 'disabled' ]]; then VERBOSITY=0; elif [[ "${VERBOSITY}" == 'errors' ]]; then VERBOSITY=1; elif [[ "${VERBOSITY}" == 'warnings' ]]; then VERBOSITY=2; elif [[ "${VERBOSITY}" == 'all' ]]; then VERBOSITY=3; elif [[ "${VERBOSITY}" == 'debug' ]]; then VERBOSITY=4; else echo "Failed to recognize verbosity level, exiting..."; exit 1; fi # Set the verbosity level
	MEM_SETTINGS=$(echo "-t ${THREADS} -k ${SEED} -w ${WIDTH} -d ${DROPOFF} -r ${RE_SEED} -A ${MATCH} -B ${MISMATCH} -O ${GAP} -E ${EXTENSION} -L ${CLIP} -U ${UNPAIRED} -T ${RM_THRESHOLD} -v ${VERBOSITY} ${POSITIONALS}") # Assemble our settings
    echo "${MEM_SETTINGS}" # Return our settings
}

#   Export the function
export -f ParseBWASettings

#   A function to see if our referenced FASTA is indexed
function checkIndex() {
    local reference="$1" # What is our reference FASTA file?
    if ! [[ -f "${reference}" ]]; then echo "Cannot find reference genome, exiting..." >&2; exit 1; fi # Make sure it exists
    if ! [[ -r "${reference}" ]]; then echo "Reference genome does not have read permissions, exiting..." >&2; exit 1; fi # Make sure we can read it
    local referenceDirectory=$(dirname "${reference}") # Get the directory for the reference directory
    local referenceName=$(basename "${reference}") # Get the basename of the reference
    if [[ ! $(ls "${referenceDirectory}" | grep "${referenceName}.amb" ) || ! $( ls "${referenceDirectory}" | grep "${referenceName}.ann") || ! $( ls "${referenceDirectory}" | grep "${referenceName}.bwt") || ! $( ls "${referenceDirectory}" | grep "${referenceName}.pac") || ! $( ls "${referenceDirectory}" | grep "${referenceName}.sa") ]]; then return 1; fi # Check that we have all the index files, if we don't then return 1 (not exit 1) so that we can index them
    if [[ ! -r "${referenceDirectory}"/"${referenceName}.amb" || ! -r "${referenceDirectory}"/"${referenceName}.ann" || ! -r "${referenceDirectory}"/"${referenceName}.bwt" || ! -r "${referenceDirectory}"/"${referenceName}.pac" ||! -r "${referenceDirectory}"/"${referenceName}.sa" ]]; then echo "Reference index files do not have read permissions, exiting..." >&2; exit 1; fi # Make sure we can read the index files
}

#   Export the function
export -f checkIndex

#   A function to index the FASTA and exit
function indexReference() {
    local reference="$1" # What is our reference FASTA file?
    local referenceDirectory=$(dirname "${reference}") # Get the directory for the reference directory
    if ! [[ -w "${referenceDirectory}" ]]; then echo "Cannot create reference index because you do not have write permissions for ${referenceDirectory}" >&2; exit 1; fi # Make sure we can create the index files
    echo "Indexing reference, will quit upon completion..." >&2
    (set -x; bwa index "${reference}") # Index our reference FASTA file
    echo "Please re-run sequence_handling to map reads" >&2
    exit 10 # Exit the script with a unique exit status
}

#   Export the function
export -f indexReference

#   A function to create our read group ID for BWA
function createReadGroupID() {
    local sample="$1" # What is our sample name?
    local project="$2" # What is the name of the project?
    local platform="$3" # What platform did we sequence on?
    local readGroupID="@RG\tID:${sample}\tLB:${project}_${sample}\tPL:${platform}\tSM:${sample}" # Assemble our read group ID
    echo "${readGroupID}" # Return our read group ID
}

#   Export the function
export -f createReadGroupID

#   Run read mapping for paired-end samples
function Read_Mapping_Paired() {
    local sampleName="$1" # What is the name of our sample?
    local forwardSample="$2" # Where is the forward sample?
    local reverseSample="$3" # Where is the reverse sample?
    local project="$4" # What is the name of our project?
    local platform="$5" # What platform did we sequence on?
    local outDirectory="$6"/Read_Mapping # Where is our outdirectory?
    local reference="$7" # Where is our reference FASTA file?
    mkdir -p "${outDirectory}" # Make our outdirectory
    local memSettings=$(ParseBWASettings) # Assemble our settings for BWA mem
    local readGroupID=$(createReadGroupID "${sampleName}" "${project}" "${platform}") # Assemble our read group ID
    (set -x; bwa mem "${memSettings}" -v 2 -R "${readGroupID}" "${reference}" "${forwardSample}" "${reverseSample}" > "${outDirectory}"/"${sampleName}".sam)
}

#   Export the function
export -f Read_Mapping_Paired

#   Run read mapping for single-end samples
function Read_Mapping_Singles() {
    local sampleName="$1" # What is the name of our sample?
    local sampleFile="$2" # Where is our sample?
    local project="$3" # What is the name of our project?
    local platform="$4" # What platform did we sequence on?
    local outDirectory="$5"/Read_Mapping # Where is our outdirectory?
    local reference="$6" # Where is our reference FASTA file?
    local memSettings=$(ParseBWASettings) # Assemble our settings for BWA mem
    local readGroupID=$(createReadGroupID "${sampleName}" "${project}" "${platform}") # Assemble our read group ID
    #mkdir -p "${outDirectory}" # Make our outdirectory
    bwa mem "${memSettings}" -v 2 -R "${readGroupID}" "${reference}" "${sampleFile}" > "${outDirectory}"/"${sampleName}".sam)
}

export -f Read_Mapping_Singles

function Read_Mapping_Parallel() {
    local singles_trimmed="$1"
    local single_samples="$2" # array of single samples
    local out_dir="$3"
    #   Check if out directory exists, if not make it
    mkdir -p "${outDirectory}"
    #   Create an array of single end sample names
    single_names=($(parallel basename {} "${singles_trimmed}" ::: "${single_samples[@]}"))
    #   Map reads in parallel
    Read_Mapping_Singles "${"

}
