version 1.0
import "call_assembly_variants.wdl" as call_variants
import "genotype_markers.wdl" as genotype

workflow CompetitiveGenotyping {
    input {
        File assembly_list
        File dataset_list
        File ref
        File ref_index
        String ref_name
        File fastq_list
    }
    Array[Array[File]] assemblies = read_tsv(assembly_list)
    Array[Array[File]] datasets = read_tsv(dataset_list)

    scatter (assembly in assemblies) {
        call call_variants.CallAssemblyVariants as call_variants {
            input:
            assembly_name=assembly[0],
            contigs1=assembly[1],
            contigs2=assembly[2],
            ref=ref,
            ref_index=ref_index,
            ref_name=ref_name,
            fastq_list=fastq_list
        }
    }

    call merge_variants {
        input:
            small_variants=call_variants.small_variants,
            small_variants_marker_positions=call_variants.small_variants_marker_positions #,
            #sv=call_variants.sv  #TODO
    }

    scatter (dataset in datasets) {
        call genotype.GenotypeMarkers as genotype {
            input:
            dataset_name=dataset[0],
            dataset_fastq=dataset[1],
            variant_fasta=merge_variants.fasta_representation,
            marker_positions=merge_variants.marker_positions
        }
    }

    output {
        Array[File] marker_counts = genotype.marker_counts
    }
}

task merge_variants {
    input {
        Array[File] small_variants
        Array[File] small_variants_marker_positions
        #Array[File] sv #TODO
    }
    command <<<
        PYTHON=/opt/hall-lab/python-2.7.15/bin/python
        FIND_DUPS=/storage1/fs1/ccdg/Active/analysis/ref_grant/assembly_analysis_20200220/multiple_competitive_alignment/find_duplicate_markers.py #TODO
        cat ~{sep=" " small_variants} | paste - - - - | awk -v OFS="\t" -v FS="\t" '{if($2<$4) {print($2, $4, $1, $3)} else{print($4,$2,$3,$1)}}' | sort | awk -v OFS="\n" -v FS="\t" '{print($3,$1,$4,$2)}' > tmp
        $PYTHON $FIND_DUPS -i tmp > variants_merged.fasta
        cat ~{sep=" " small_variants_marker_positions} | sort -u > marker_positions.txt
    >>>
    runtime {
        docker: "apregier/analyze_assemblies@sha256:5cbac56b15b739783c37d2a92261bef138d5bae3e99171557df06d3e39cb485a"
        memory: "64 GB"
    }
    output {
        File fasta_representation="variants_merged.fasta"
        File marker_positions="marker_positions.txt"
    }
}
