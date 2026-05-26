#!/bin/bash
set -euo pipefail

workflow_path='<software_path>/repos/epi2me_wf-basecalling/'
softwaretool_path='<software_path>/tools/'

# Set input and output dirs
input=`realpath $1`
output=`realpath $2`
sample_name=$3
basecaller_cfg=$4
remora_cfg=$5
email=$6
optional_params=( "${@:7}" )

mkdir -p $output && cd $output
mkdir -p execution

if ! { [ -f 'workflow.running' ] || [ -f 'workflow.done' ] || [ -f 'workflow.failed' ]; }; then
    touch workflow.running


output_execution="${output}/execution"
file="${output_execution}/trace.txt"
# Check if trace.txt exists
if [ -e "${file}" ]; then
    current_suffix=0
    # Get a list of all trace files WITH a suffix
    trace_file_list=$(ls "${output_execution}"/trace*.txt 2> /dev/null)
    # Check if any trace files with a suffix exist
    if [ "$?" -eq 0 ]; then
        # Check for each trace file with a suffix if the suffix is the highest and save that one as the current suffix
        for trace_file in ${trace_file_list}; do
            basename_trace_file=$(basename "${trace_file}")
            if echo "${basename_trace_file}" | grep -qE '[0-9]+'; then
                suffix=$(echo "${basename_trace_file}" | grep -oE '[0-9]+')
            else
                suffix=0
            fi

            if [ "${suffix}" -gt "${current_suffix}" ]; then
                current_suffix=${suffix}
            fi
        done
    fi
    # Increment the suffix
    new_suffix=$((current_suffix + 1))
    # Create the new file name with the incremented suffix
    new_file="${file%.*}_$new_suffix.${file##*.}"
    # Rename the file
    mv "${file}" "${new_file}"
fi

# Add git log information to file.
git --git-dir ${workflow_path}/.git log --pretty=oneline -n 1 > "${output_execution}/repos.version.txt"

sbatch <<EOT
#!/bin/bash
#SBATCH -c 2
#SBATCH --time=72:00:00
#SBATCH --mem=20G
#SBATCH --job-name epi2me_wf-basecalling
#SBATCH --gres=tmpspace:40G
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=$email
#SBATCH --error=execution/slurm_epi2me_wf-basecalling.%j.err
#SBATCH --output=execution/slurm_epi2me_wf-basecalling.%j.out

export NXF_JAVA_HOME='$softwaretool_path/java/jdk'
export NXF_SINGULARITY_CACHEDIR=/hpc/hers_en/edejong2/software/singularity_cache/
export NXF_APPTAINER_CACHEDIR=/hpc/hers_en/edejong2/software/singularity_cache/
export APPTAINER_DISABLE_CACHE=True
export NXF_OFFLINE=True

${softwaretool_path}/nextflow/nextflow run \
${workflow_path}/main.nf \
-c $workflow_path/umcu_hpc.config \
--basecaller_cfg $basecaller_cfg \
--remora_cfg $remora_cfg \
--input $input \
--out_dir $output \
--output_fmt 'bam' \
--sample_name $sample_name \
-resume \
-ansi-log false \
-profile slurm \
${optional_params[@]:-""}

# --ref '/hpc/diaggen/data/databases/ref_genomes/GRCh38_gencode_v22_CTAT_lib_Mar012021/GRCh38_gencode_v22_CTAT_lib_Mar012021.plug-n-play/ctat_genome_lib_build_dir/ref_genome.fa' \

if [ \$? -eq 0 ]; then
    echo "Nextflow done."

#    echo "Zip work directory"
#    find work -type f | egrep "\.(command|exitcode)" | zip -@ -q work.zip

#    echo "Remove work directory"
#    rm -r work

#    echo "Creating md5sum"
#    find -type f -not -iname 'md5sum.txt' -exec md5sum {} \; > md5sum.txt

    echo "epi2me_wf-basecalling workflow completed successfully."
    rm workflow.running
    touch workflow.done

    echo "Change permissions"
    chmod 775 -R $output

    exit 0
else
    echo "Nextflow failed"
    rm workflow.running
    touch workflow.failed

    echo "Change permissions"
    chmod 775 -R $output

    exit 1
fi
EOT
else
echo "Workflow job not submitted, please check $output for 'workflow.status' files."
fi
