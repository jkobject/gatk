version 1.0

workflow GvsValidateVat {
    input {
        String query_project_id
        String default_dataset
        String vat_table_name
    }

    String fq_vat_table = "~{query_project_id}.~{default_dataset}.~{vat_table_name}"

    call GetBQTableLastModifiedDatetime {
        input:
            query_project = query_project_id,
            fq_table = fq_vat_table
    }

    call EnsureVatTableHasVariants {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SpotCheckForExpectedTranscripts {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaOnlyOneRowPerNullTranscript {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaNullTranscriptsExist {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaNoNullRequiredFields {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaPrimaryKey {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaEnsemblTranscripts {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SchemaNonzeroAcAn {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SubpopulationMax {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SubpopulationAlleleCount {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call SubpopulationAlleleNumber {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    call ClinvarSignificance {
        input:
            query_project_id = query_project_id,
            fq_vat_table = fq_vat_table,
            last_modified_timestamp = GetBQTableLastModifiedDatetime.last_modified_timestamp
    }

    output {
        Array[Map[String, String]] validation_results = [
            EnsureVatTableHasVariants.result,
            SpotCheckForExpectedTranscripts.result,
            SchemaOnlyOneRowPerNullTranscript.result,
            SchemaNullTranscriptsExist.result,
            SchemaNoNullRequiredFields.result,
            SchemaPrimaryKey.result,
            SchemaEnsemblTranscripts.result,
            SchemaNonzeroAcAn.result,
            SubpopulationMax.result,
            SubpopulationAlleleCount.result,
            SubpopulationAlleleNumber.result,
            ClinvarSignificance.result
        ]
    }
}

task GetBQTableLastModifiedDatetime {
    # because this is being used to determine if the data has changed, never use call cache
    meta {
        volatile: true
    }

    input {
        String query_project
        String fq_table
    }


    # ------------------------------------------------
    # try to get the last modified date for the table in question; fail if something comes back from BigQuery
    # that isn't in the right format (e.g. an error)
    command <<<
        set -e

        gcloud config set project ~{query_project}

        echo "project_id = ~{query_project}" > ~/.bigqueryrc

        # bq needs the project name to be separate by a colon
        DATASET_TABLE_COLON=$(echo ~{fq_table} | sed 's/\./:/')

        LASTMODIFIED=$(bq --location=US --project_id=~{query_project} --format=json show ${DATASET_TABLE_COLON} | python3 -c "import sys, json; print(json.load(sys.stdin)['lastModifiedTime']);")
        if [[ $LASTMODIFIED =~ ^[0-9]+$ ]]; then
            echo $LASTMODIFIED
        else
            exit 1
        fi
    >>>

    output {
        String last_modified_timestamp = read_string(stdout())
    }

    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "3 GB"
        disks: "local-disk 10 HDD"
        preemptible: 3
        cpu: 1
    }

}

task EnsureVatTableHasVariants {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }

    command <<<
        set -e
        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT COUNT (DISTINCT vid) AS count FROM ~{fq_vat_table}' > bq_variant_count.csv

        NUMVARS=$(python3 -c "csvObj=open('bq_variant_count.csv','r');csvContents=csvObj.read();print(csvContents.split('\n')[1]);")

        # if the result of the bq call and the csv parsing is a series of digits, then check that it isn't 0
        if [[ $NUMVARS =~ ^[0-9]+$ ]]; then
            if [[ $NUMVARS = "0" ]]; then
                echo "FAIL: The VAT table ~{fq_vat_table} has no variants in it." > validation_results.txt
            else
                echo "PASS: The VAT table ~{fq_vat_table} has $NUMVARS variants in it." > validation_results.txt
            fi
        # otherwise, something is off, so return the output from the bq query call
        else
            echo "Something went wrong. The attempt to count the variants returned: " $(cat bq_variant_count.csv) > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"EnsureVatTableHasVariants": read_string('validation_results.txt')}
    }
}


task SpotCheckForExpectedTranscripts {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            contig,
            position,
            vid,
            gene_symbol,
            variant_consequence
        FROM
            ~{fq_vat_table},
            UNNEST(consequence) AS variant_consequence
        WHERE
            contig = "chr19" AND
            position >= 35740407 AND
            position <= 35740469 AND
            variant_consequence NOT IN ("downstream_gene_variant","upstream_gene_variant") AND
            gene_symbol NOT IN ("IGFLR1","AD000671.2")' > bq_query_output.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_query_output.csv)

        # if the result of the query has any rows, that means there were unexpected transcripts at the
        # specified location, so report those back in the output
        if [[ $NUMRESULTS = "0" ]]; then
            echo "PASS: The VAT table ~{fq_vat_table} only has the expected transcripts at the tested location ('IGFLR1' and 'AD000671.2' in chromosome 19, between positions 35,740,407 - 35,740,469)." > validation_results.txt
        else
           echo "FAIL: The VAT table ~{fq_vat_table} had unexpected transcripts at the tested location: [csv output follows] " > validation_results.txt
            cat bq_query_output.csv >> validation_results.txt
        fi
    >>>

    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }

    output {
        Map[String, String] result = {"SpotCheckForExpectedTranscripts": read_string('validation_results.txt')}

    }
}

task SchemaNoNullRequiredFields {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # No non-nullable fields contain null values

    command <<<
        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        # non-nullable fields: vid, contig, position, ref_allele, alt_allele, gvs_all_ac, gvs_all_an, gvs_all_af, variant_type, genomic_location

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv
        'SELECT
            contig,
            position,
            vid,
            concat(
              case(vid is null) when true then 'vid ' else '' end,
              case(contig is null) when true then 'contig ' else '' end,
              case(position is null) when true then 'position ' else '' end,
              case(ref_allele is null) when true then 'ref_allele ' else '' end,
              case(alt_allele is null) when true then 'alt_allele ' else '' end,
              case(gvs_all_ac is null) when true then 'gvs_all_ac ' else '' end,
              case(gvs_all_an is null) when true then 'gvs_all_an ' else '' end,
              case(gvs_all_af is null) when true then 'gvs_all_af ' else '' end,
              case(variant_type is null) when true then 'variant_type ' else '' end,
              case(genomic_location is null) when true then 'genomic_location ' else '' end
           ) AS null_fields
        FROM
            ~{fq_vat_table}
        WHERE
            vid IS NULL OR
            contig IS NULL OR
            position IS NULL OR
            ref_allele IS NULL OR
            alt_allele IS NULL OR
            gvs_all_ac IS NULL OR
            gvs_all_an IS NULL OR
            gvs_all_af IS NULL OR
            variant_type IS NULL OR
            genomic_location IS NULL' > bq_null_required_output.csv


            # get number of lines in bq query output
            NUMRESULTS=$(awk 'END{print NR}' bq_null_required_output.csv)

            # if the result of the query has any rows, that means there were unexpected null values in required fields, so report those back in the output
            if [[ $NUMRESULTS = "0" ]]; then
                echo "PASS: The VAT table ~{fq_vat_table} has no null values in required fields"  > validation_results.txt
            else
                echo "FAIL: The VAT table ~{fq_vat_table} had null values in required fields: [csv output follows] " > validation_results.txt
                cat bq_null_required_output.csv >> validation_results.txt
            fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaNoNullRequiredFields": read_string('validation_results.txt')}
    }
}

task SchemaOnlyOneRowPerNullTranscript {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            vid,
            COUNT(vid) AS num_rows
        FROM
            ~{fq_vat_table}
        WHERE
            transcript_source is NULL AND
            transcript is NULL
        GROUP BY vid
        HAVING num_rows > 1' > bq_variant_count.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_variant_count.csv)

        # if the result of the query has any rows, that means there were vids with null transcripts and multiple
        # rows in the VAT, which should not be the case
        if [[ $NUMRESULTS = "0" ]]; then
            echo "PASS: The VAT table ~{fq_vat_table} only has 1 row per vid with a null transcript" > validation_results.txt
        else
            echo "FAIL: The VAT table ~{fq_vat_table} had at least one vid with a null transcript and more than one row: [csv output follows] " > validation_results.txt
            cat bq_variant_count.csv >> validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaOnlyOneRowPerNullTranscript": read_string('validation_results.txt')}
    }
}

task SchemaPrimaryKey {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # Each key combination (vid+transcript) is unique--confirms that primary key is enforced.

    command <<<
        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv
        'SELECT
            vid,
            transcript,
            COUNT(vid) AS num_vids,
            COUNT(transcript) AS num_transcripts
        FROM
            ~{fq_vat_table}
        GROUP BY vid, transcript
        HAVING num_vids > 1 OR num_transcripts > 1' > bq_primary_key.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_primary_key.csv)

        # if the result of the query has any rows, that means not all key combinations (vid+transcript) are unique, so report those back in the output
        if [[ $NUMRESULTS = "0" ]]; then
          echo "PASS: The VAT table ~{fq_vat_table} has all unique key combinations (vid+transcript)"  > validation_results.txt
        else
          echo "FAIL: The VAT table ~{fq_vat_table} had repeating key combinations (vid+transcript): [csv output follows] " > validation_results.txt
        cat bq_primary_key.csv >> validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaPrimaryKey": read_string('validation_results.txt')}
    }
}

task SchemaEnsemblTranscripts {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # Every transcript_source is Ensembl or null

    command <<<
        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            contig,
            position,
            vid,
            transcript,
            transcript_source
        FROM
            ~{fq_vat_table}
        WHERE
            transcript IS NOT NULL AND
            transcript_source != "Ensembl"' > bq_transcript_output.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_transcript_output.csv)

        # if the result of the query has any rows, that means there were unexpected transcripts (not from Ensembl), so report those back in the output
        if [[ $NUMRESULTS = "0" ]]; then
            echo "PASS: The VAT table ~{fq_vat_table} only has the expected Ensembl transcripts"  > validation_results.txt
        else
            echo "FAIL: The VAT table ~{fq_vat_table} had unexpected transcripts (not from Ensembl): [csv output follows] " > validation_results.txt
            cat bq_transcript_output.csv >> validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaEnsemblTranscripts": read_string('validation_results.txt')}
    }
}

task SchemaNonzeroAcAn {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # No row has AC of zero or AN of zero.

    command <<<
        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            contig,
            position,
            vid,
            gvs_all_ac,
            gvs_all_an
        FROM
            ~{fq_vat_table}
        WHERE
            gvs_all_ac IS NULL OR
            gvs_all_ac = 0 OR
            gvs_all_an IS NULL OR
            gvs_all_an = 0' > bq_ac_an_output.csv


        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_ac_an_output.csv)

        # if the result of the query has any rows, that means there were unexpected rows with either an AC of zero or AN of zero, so report those back in the output
        if [[ $NUMRESULTS = "0" ]]; then
            echo "PASS: The VAT table ~{fq_vat_table} only has no rows with AC of zero or AN of zero"  > validation_results.txt
        else
            echo "FAIL: The VAT table ~{fq_vat_table} had unexpected rows with AC of zero or AN of zero: [csv output follows] " > validation_results.txt
            cat bq_ac_an_output.csv >> validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaNonzeroAcAn": read_string('validation_results.txt')}
    }
}

task SchemaNullTranscriptsExist {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            vid
        FROM
            ~{fq_vat_table}
        WHERE
            transcript_source is NULL AND
            transcript is NULL' > bq_variant_count.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_variant_count.csv)

        # if the result of the query has any rows, that means there were null transcripts as expected
        if [[ $NUMRESULTS != "0" ]]; then
           echo "PASS: The VAT table ~{fq_vat_table} has at least one null transcript" > validation_results.txt
        else
           echo "FAIL: The VAT table ~{fq_vat_table} has no null transcripts" > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SchemaNullTranscriptsExist": read_string('validation_results.txt')}
    }
}

task SubpopulationMax {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # gvs_max_af is actually the max

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        # gvs subpopulations:  [ "afr", "amr", "eas", "eur", "mid", "oth", "sas"]

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            vid
        FROM
            ~{fq_vat_table}
        WHERE
            gvs_max_af < gvs_afr_af OR
            gvs_max_af < gvs_amr_af OR
            gvs_max_af < gvs_eas_af OR
            gvs_max_af < gvs_eur_af OR
            gvs_max_af < gvs_mid_af OR
            gvs_max_af < gvs_oth_af OR
            gvs_max_af < gvs_sas_af' > bq_query_output.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_query_output.csv)

        # if the result of the query has any rows, that means gvs_max_af is not in fact the max af
        if [[ $NUMRESULTS = "0" ]]; then
          echo "PASS: The VAT table ~{fq_vat_table} has a correct calculation for subpopulation" > validation_results.txt
        else
          echo "FAIL: The VAT table ~{fq_vat_table} has an incorrect calculation for subpopulation" > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SubpopulationMax": read_string('validation_results.txt')}
    }
}

task SubpopulationAlleleCount {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # sum of subpop ACs equal the gvs_all ACs

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        # gvs subpopulations:  [ "afr", "amr", "eas", "eur", "mid", "oth", "sas"]

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
            vid
        FROM
            ~{fq_vat_table}
        WHERE
            gvs_all_ac != gvs_afr_ac + gvs_amr_ac + gvs_eas_ac + gvs_eur_ac + gvs_mid_ac + gvs_oth_ac + gvs_sas_ac'  > bq_query_output.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_query_output.csv)

        # if the result of the query has any rows, that means gvs_all_ac has not been calculated correctly
        if [[ $NUMRESULTS = "0" ]]; then
            echo "PASS: The VAT table ~{fq_vat_table} has a correct calculation for AC and the AC of subpopulations" > validation_results.txt
            else
            echo "FAIL: The VAT table ~{fq_vat_table} has an incorrect calculation for AC and the AC of subpopulations" > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SubpopulationAlleleCount": read_string('validation_results.txt')}
    }
}

task SubpopulationAlleleNumber {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # sum of subpop ACs equal the gvs_all ACs

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        # gvs subpopulations:  [ "afr", "amr", "eas", "eur", "mid", "oth", "sas"]

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
        vid
        FROM
        ~{fq_vat_table}
        WHERE
        gvs_all_an != gvs_afr_an + gvs_amr_an + gvs_eas_an + gvs_eur_an + gvs_mid_an + gvs_oth_an + gvs_sas_an' > bq_an_output.csv

        # get number of lines in bq query output
        NUMRESULTS=$(awk 'END{print NR}' bq_an_output.csv)

        # if the result of the query has any rows, that means gvs_all_an has not been calculated correctly
        if [[ $NUMRESULTS = "0" ]]; then
          echo "PASS: The VAT table ~{fq_vat_table} has a correct calculation for AN and the AN of subpopulations" > validation_results.txt
        else
          echo "FAIL: The VAT table ~{fq_vat_table} has an incorrect calculation for AN and the AN of subpopulations" > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"SubpopulationAlleleNumber": read_string('validation_results.txt')}
    }
}

task ClinvarSignificance {
    input {
        String query_project_id
        String fq_vat_table
        String last_modified_timestamp
    }
    # check that all clinvar values are accounted for

    command <<<
        set -e

        echo "project_id = ~{query_project_id}" > ~/.bigqueryrc

        # clinvar significance values:  ["benign",
        #                                 "likely benign",
        #                                 "uncertain significance",
        #                                 "likely pathogenic",
        #                                 "pathogenic",
        #                                 "drug response",
        #                                 "association",
        #                                 "risk factor",
        #                                 "protective",
        #                                 "affects",
        #                                 "conflicting data from submitters",
        #                                 "other",
        #                                 "not provided"]

        bq query --nouse_legacy_sql --project_id=~{query_project_id} --format=csv 'SELECT
          distinct(unnested_clinvar_classification)
          FROM
        ~{fq_vat_table}, UNNEST(clinvar_classification) AS unnested_clinvar_classification' > bq_clinvar_classes.csv

        INCLUVALUES=$(awk -v RS='^$' 'END{print  !(index($0,"benign") && \
         index($0,"likely benign") && index($0,"uncertain significance") && \
         index($0,"likely pathogenic") && index($0,"pathogenic") && \
         index($0,"drug response") && index($0,"association") && \
         index($0,"risk factor") && index($0,"protective") && \
         index($0,"affects") && index($0,"conflicting data from submitters") && \
         index($0,"other") && \
         index($0,"not provided"))}'  bq_clinvar_classes.csv)

        NUMRESULTS=$( wc -l bq_clinvar_classes.csv | awk '{print $1;}' ) # we expect this to be 13+

        # if the result of the query has any rows, that means gvs_all_an has not been calculated correctly
        if [[ $NUMRESULTS -ge 13 && $INCLUVALUES = "0" ]]; then
          echo "PASS: The VAT table ~{fq_vat_table} has the correct values for clinvar classification" > validation_results.txt
        else
          echo "FAIL: The VAT table ~{fq_vat_table} has an incorrect values for clinvar classification" > validation_results.txt
        fi
    >>>
    # ------------------------------------------------
    # Runtime settings:
    runtime {
        docker: "gcr.io/google.com/cloudsdktool/cloud-sdk:305.0.0"
        memory: "1 GB"
        preemptible: 3
        cpu: "1"
        disks: "local-disk 100 HDD"
    }
    # ------------------------------------------------
    # Output: {"Name of validation rule": "PASS/FAIL plus additional validation results"}
    output {
        Map[String, String] result = {"ClinvarSignificance": read_string('validation_results.txt')}
    }
}


## TODO It would be great to spot check a few well known variants / genes