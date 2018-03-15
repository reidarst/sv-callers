rule delly:
    input:
        fasta = get_fasta(),
        fai = get_faidx()[0],
        tumor_bam = "{path}/{tumor}" + get_filext("bam"),
        tumor_bai = "{path}/{tumor}" + get_filext("bam_idx"),
        normal_bam = "{path}/{normal}" + get_filext("bam"),
        normal_bai = "{path}/{normal}" + get_filext("bam_idx")
    output:
        "{path}/{tumor}--{normal}/" + get_outdir("delly") +
        "/{rule}-{sv_type}.vcf.gz"
    conda:
        "../environment.yaml"
    threads:
        get_nthreads("delly")
    resources:
        mem_mb = get_memory("delly"),
        tmp_mb = get_tmpspace("delly")
    shell:
        """
        set -x
        OUTDIR="$(dirname "{output}")"

        # fetch sample ID from a BAM file
        function get_samp_id() {{
            echo "$(samtools view -H ${{1}} | \
                   perl -lne 'print ${{1}} if /\sLB:(\S+)/' | \
                   head -n 1)"
        }}

        # run dummy or real job
        if [ "{config[echo_run]}" -eq "1" ]; then
            echo "{input}" > "{output}"
        else
            # use OpenMP for threaded jobs
            export OMP_NUM_THREADS={threads}
            #export OMP_PROC_BIND=true
            #export OMP_PLACES=threads

            # somatic SV calling
            PREFIX="${{OUTDIR}}/delly-{wildcards.sv_type}"
            TSV="${{OUTDIR}}/sample_pairs.tsv"
            delly call \
                -t "{wildcards.sv_type}" \
                -g "{input.fasta}" \
                -o "${{PREFIX}}.bcf" \
                -q 1 `# min.paired-end mapping quality` \
                -s 9 `# insert size cutoff, DELs only` \
                "{input.tumor_bam}" "{input.normal_bam}" &&
            # somatic pre-filtering
            #   create sample list
            TID=$(get_samp_id "{input.tumor_bam}")
            CID=$(get_samp_id "{input.normal_bam}")
            printf "${{TID}}\ttumor\n${{CID}}\tcontrol\n" > ${{TSV}} &&
            delly filter \
                -f somatic \
                -s "${{TSV}}" \
                -o "${{PREFIX}}.pre.bcf" \
                "${{PREFIX}}.bcf" &&
            # convert BCF to compressed VCF file
            bcftools convert \
                -O z `# compressed VCF format` \
                -o "${{PREFIX}}.vcf.gz" \
                "${{PREFIX}}.pre.bcf"
        fi
        """

rule delly_merge:
    input:
        ["{path}/{tumor}--{normal}/" + get_outdir("delly") + "/delly-" +
         sv + ".vcf.gz" for sv in config["callers"]["delly"]["sv_types"]]
    output:
        "{path}/{tumor}--{normal}/" + get_outdir("delly") + "/delly.vcf"
    shell:
        """
        set -x

        # run dummy or real job
        if [ "{config[echo_run]}" -eq "1" ]; then
            cat {input} > "{output}"
        else
            bcftools merge \
               -O z \
               -o "{output}" \
               {input}
       fi
       """
