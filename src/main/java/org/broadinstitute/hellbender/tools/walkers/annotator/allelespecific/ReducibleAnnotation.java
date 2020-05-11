package org.broadinstitute.hellbender.tools.walkers.annotator.allelespecific;

import htsjdk.variant.variantcontext.Allele;
import htsjdk.variant.variantcontext.VariantContext;
import htsjdk.variant.vcf.VCFInfoHeaderLine;
import org.broadinstitute.hellbender.engine.ReferenceContext;
import org.broadinstitute.hellbender.tools.walkers.annotator.Annotation;
import org.broadinstitute.hellbender.utils.genotyper.AlleleLikelihoods;
import org.broadinstitute.hellbender.utils.read.GATKRead;
import org.broadinstitute.hellbender.utils.variant.GATKVCFHeaderLines;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

/**
 * An interface for annotations that are calculated using raw data across samples, rather than the median (or median of median) of samples values
 *
 */
public interface ReducibleAnnotation extends Annotation {
    /**
     * Get all the raw key names for this annotation
     * @return a non-empty list
     */
    default List<String> getRawKeyNames() {
        final List<String> allRawKeys = new ArrayList<>();
        allRawKeys.add(getPrimaryRawKey());
        if (hasSecondaryRawKeys()) {
            allRawKeys.addAll(getSecondaryRawKeys());
        }
        return allRawKeys;
    }

    /**
     * Get the string that's used to combine data for this annotation
     * @return never null
     */
    String getPrimaryRawKey();

    /**
     *
     * @return true if annotation has secondary raw keys
     */
    boolean hasSecondaryRawKeys();

    /**
     * Get additional raw key strings that are not the primary key
     * @return  may be null
     */
    List<String> getSecondaryRawKeys();

    /**
     * Generate the raw data necessary to calculate the annotation. Raw data is the final endpoint for gVCFs.
     * @param ref the reference context for this annotation
     * @param vc the variant context to annotate
     * @param likelihoods likelihoods indexed by sample, allele, and read within sample
     */
    Map<String, Object> annotateRawData(final ReferenceContext ref,
                                                        final VariantContext vc,
                                                        final AlleleLikelihoods<GATKRead, Allele> likelihoods);

    /**
     * Combine raw data, typically during the merging of raw data contained in multiple gVCFs as in CombineGVCFs and the
     * preliminary merge for GenotypeGVCFs
     * @param allelesList   The merged allele list across all variants being combined/merged
     * @param listOfRawData The raw data for all the variants being combined/merged
     * @return A key, Object map containing the annotations generated by this combine operation
     */
    @SuppressWarnings({"unchecked"})//FIXME generics here blow up
    Map<String, Object> combineRawData(final List<Allele> allelesList, final List<ReducibleAnnotationData<?>> listOfRawData);

    /**
     * Calculate the final annotation value from the raw data which was generated by either annotateRawData or calculateRawData
     * @param vc -- contains the final set of alleles, possibly subset by GenotypeGVCFs
     * @param originalVC -- used to get all the alleles for all gVCFs
     * @return A key, Object map containing the finalized annotations generated by this operation to be added to the code
     */
    Map<String, Object> finalizeRawData(final VariantContext vc, final VariantContext originalVC);


    /**
     * Returns the descriptions used for the VCF INFO meta field corresponding to the annotations raw key.
     * @return A list of VCFInfoHeaderLines corresponding to the raw keys added by this annotaiton
     */
    default List<VCFInfoHeaderLine> getRawDescriptions() {
        final List<VCFInfoHeaderLine> lines = new ArrayList<>(1);
        for (final String rawKey : getRawKeyNames()) {
            lines.add(GATKVCFHeaderLines.getInfoLine(rawKey));
        }
        return lines;
    }
}