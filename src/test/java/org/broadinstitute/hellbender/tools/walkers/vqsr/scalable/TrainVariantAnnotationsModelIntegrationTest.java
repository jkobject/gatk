package org.broadinstitute.hellbender.tools.walkers.vqsr.scalable;

import com.google.common.collect.Lists;
import org.apache.commons.lang3.tuple.Pair;
import org.broadinstitute.hellbender.CommandLineProgramTest;
import org.broadinstitute.hellbender.cmdline.StandardArgumentDefinitions;
import org.broadinstitute.hellbender.testutils.ArgumentsBuilder;
import org.broadinstitute.hellbender.tools.walkers.vqsr.scalable.data.VariantType;
import org.testng.Assert;
import org.testng.annotations.DataProvider;
import org.testng.annotations.Test;

import java.io.File;
import java.util.Arrays;
import java.util.List;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * See documentation for {@link ExtractVariantAnnotationsIntegrationTest} for information about how inputs and
 * expected outputs used there are related to those used here and in {@link ScoreVariantAnnotationsIntegrationTest}.
 */
public final class TrainVariantAnnotationsModelIntegrationTest extends CommandLineProgramTest {

    // If true, update the expected outputs in tests that assert an exact match vs. prior output,
    // instead of actually running the tests. Can be used with "./gradlew test -Dtest.single=TrainVariantAnnotationsIntegrationTest"
    // to update all of the exact-match tests at once. After you do this, you should look at the
    // diffs in the new expected outputs in git to confirm that they are consistent with expectations.
    public static final boolean UPDATE_EXACT_MATCH_EXPECTED_OUTPUTS = false;

    /**
     * Make sure that someone didn't leave the UPDATE_EXACT_MATCH_EXPECTED_OUTPUTS toggle turned on.
     */
    @Test
    public void assertThatExpectedOutputUpdateToggleIsDisabled() {
        Assert.assertFalse(UPDATE_EXACT_MATCH_EXPECTED_OUTPUTS, "The toggle to update expected outputs should not be left enabled.");
    }

    private static final File TEST_FILES_DIR = new File(largeFileTestDir,
            "org/broadinstitute/hellbender/tools/walkers/vqsr/scalable/train");
    private static final File INPUT_FROM_EXTRACT_EXPECTED_TEST_FILES_DIR = new File(largeFileTestDir,
            "org/broadinstitute/hellbender/tools/walkers/vqsr/scalable/extract/expected");
    private static final File EXPECTED_TEST_FILES_DIR = new File(TEST_FILES_DIR, "expected");

    private static final File ISOLATION_FOREST_PYTHON_SCRIPT = new File(packageMainResourcesDir,
            "tools/walkers/vqsr/scalable/isolation-forest.py");
    private static final File ISOLATION_FOREST_HYPERPARAMETERS_JSON = new File(TEST_FILES_DIR,
            "isolation-forest-hyperparameters.json");

    // Supplier and functions for creating and adding various arguments to an ArgumentsBuilder.
    private static final Supplier<ArgumentsBuilder> BASE_ARGS_BUILDER_SUPPLIER = ArgumentsBuilder::new;

    private static final BiFunction<ArgumentsBuilder, File, ArgumentsBuilder> ADD_ANNOTATIONS_HDF5 = (argsBuilder, annotationsHDF5) -> {
        argsBuilder.add(TrainVariantAnnotationsModel.ANNOTATIONS_HDF5_LONG_NAME, annotationsHDF5);
        return argsBuilder;
    };
    private static final BiFunction<ArgumentsBuilder, File, ArgumentsBuilder> ADD_UNLABELED_ANNOTATIONS_HDF5 = (argsBuilder, unlabeledAnnotationsHDF5) -> {
        argsBuilder.add(TrainVariantAnnotationsModel.UNLABELED_ANNOTATIONS_HDF5_LONG_NAME, unlabeledAnnotationsHDF5);
        return argsBuilder;
    };
    private static final BiFunction<ArgumentsBuilder, Double, ArgumentsBuilder> ADD_TRUTH_SENSITIVITY_THRESHOLD = (argsBuilder, truthSensitivityThreshold) -> {
        argsBuilder.add(TrainVariantAnnotationsModel.TRUTH_SENSITIVITY_THRESHOLD_LONG_NAME, truthSensitivityThreshold);
        return argsBuilder;
    };
    private static final Function<ArgumentsBuilder, ArgumentsBuilder> ADD_SNP_MODE = argsBuilder -> {
        argsBuilder.add(LabeledVariantAnnotationsWalker.MODE_LONG_NAME, VariantType.SNP);
        return argsBuilder;
    };
    private static final Function<ArgumentsBuilder, ArgumentsBuilder> ADD_INDEL_MODE = argsBuilder -> {
        argsBuilder.add(LabeledVariantAnnotationsWalker.MODE_LONG_NAME, VariantType.INDEL);
        return argsBuilder;
    };
    private static final Function<ArgumentsBuilder, ArgumentsBuilder> ADD_ISOLATION_FOREST_PYTHON_SCRIPT = argsBuilder -> {
        argsBuilder.add(TrainVariantAnnotationsModel.PYTHON_SCRIPT_LONG_NAME, ISOLATION_FOREST_PYTHON_SCRIPT);
        return argsBuilder;
    };
    private static final Function<ArgumentsBuilder, ArgumentsBuilder> ADD_ISOLATION_FOREST_HYPERPARAMETERS_JSON = argsBuilder -> {
        argsBuilder.add(TrainVariantAnnotationsModel.HYPERPARAMETERS_JSON_LONG_NAME, ISOLATION_FOREST_HYPERPARAMETERS_JSON);
        return argsBuilder;
    };

    /**
     * Exact-match tests for (non-exhaustive) configurations given by the Cartesian product of the following options:
     *  1) non-allele-specific vs. allele-specific
     *  2) SNP-only vs. SNP+INDEL (for both of these options, we use extracted annotations that contain both SNP and INDEL variants as input)
     *  3) positive (training with {TAG}.annot.hdf5) vs. positive-unlabeled (training with {TAG}.annot.hdf5 and {TAG}.unlabeled.annot.hdf5)
     *  4) Java Bayesian Gaussian Mixture Model (BGMM) backend vs. python sklearn IsolationForest backend
     *  TODO the BGMM has been reduced to a stub for this initial PR; subsequent PRs will cover the backend code and reconnect the stub
     *  TODO warm-start BGMM?
     */
    @DataProvider(name = "dataValidInputs")
    public Object[][] dataValidInputs() {
        final List<List<Pair<String, Function<ArgumentsBuilder, ArgumentsBuilder>>>> testConfigurations = Lists.cartesianProduct(
                Arrays.asList(
                        Pair.of("extract.nonAS.snpIndel.posUn.train", Function.identity()),
                        Pair.of("extract.nonAS.snpIndel.posUn.train", Function.identity()),
                        Pair.of("extract.AS.snpIndel.posUn.train", Function.identity()),
                        Pair.of("extract.AS.snpIndel.posUn.train", Function.identity())),
                Arrays.asList(
                        Pair.of("snp", ADD_SNP_MODE),
                        Pair.of("snpIndel", ADD_SNP_MODE.andThen(ADD_INDEL_MODE))),
                Arrays.asList(              // we will consume the tag and add appropriate arguments for positive and positive-negative training below
                        Pair.of("pos", Function.identity()),
                        Pair.of("posNeg", Function.identity())),
                Arrays.asList(
//                        Pair.of("BGMM", Function.identity()),
                        Pair.of("IF", ADD_ISOLATION_FOREST_PYTHON_SCRIPT.andThen(ADD_ISOLATION_FOREST_HYPERPARAMETERS_JSON))));

        return testConfigurations.stream()
                .map(tagAndAddFunctionPairs -> new Object[]{
                        tagAndAddFunctionPairs.stream().map(Pair::getLeft).collect(Collectors.joining(".")), // e.g., extract.nonAS.snpIndel.posUn.train.snp.pos.IF
                        tagAndAddFunctionPairs.stream().map(Pair::getRight)                                              // creates the corresponding ArgumentsBuilder
                                .reduce(Function.identity(), Function::andThen)                                          //  by stringing together functions that add the
                                .apply(BASE_ARGS_BUILDER_SUPPLIER.get())})                                               //  appropriate arguments
                .toArray(Object[][]::new);
    }

    @Test(dataProvider = "dataValidInputs")
    public void testValidInputs(final String tag,
                                final ArgumentsBuilder argsBuilder) {
        final File outputDir = UPDATE_EXACT_MATCH_EXPECTED_OUTPUTS ? EXPECTED_TEST_FILES_DIR : createTempDir("train");
        final String outputPrefix = String.format("%s/%s", outputDir, tag);
        argsBuilder.addOutput(outputPrefix);

        final String extractTag = tag.split(".train")[0];
        final File positiveAnnotationsHDF5 = new File(INPUT_FROM_EXTRACT_EXPECTED_TEST_FILES_DIR, String.format("%s.annot.hdf5", extractTag));
        final double truthSensitivityThreshold = 0.9;
        final Function<ArgumentsBuilder, ArgumentsBuilder> addPositiveAnnotations = ab ->
                ADD_ANNOTATIONS_HDF5.apply(ab, positiveAnnotationsHDF5);
        if (tag.contains("posNeg")) {
            final File unlabeledAnnotationsHDF5 = new File(INPUT_FROM_EXTRACT_EXPECTED_TEST_FILES_DIR, String.format("%s.unlabeled.annot.hdf5", extractTag));
            final Function<ArgumentsBuilder, ArgumentsBuilder> addUnlabeledAnnotations = ab ->
                    ADD_UNLABELED_ANNOTATIONS_HDF5.apply(ab, unlabeledAnnotationsHDF5);
            final Function<ArgumentsBuilder, ArgumentsBuilder> addTruthSensitivityThreshold = ab ->
                    ADD_TRUTH_SENSITIVITY_THRESHOLD.apply(ab, truthSensitivityThreshold);
            addPositiveAnnotations.andThen(addUnlabeledAnnotations).andThen(addTruthSensitivityThreshold).apply(argsBuilder);
        } else {
            addPositiveAnnotations.apply(argsBuilder);
        }

        argsBuilder.add(StandardArgumentDefinitions.VERBOSITY_NAME, "INFO");
        runCommandLine(argsBuilder);

        if (!UPDATE_EXACT_MATCH_EXPECTED_OUTPUTS) {
            assertOutputs(tag, outputPrefix);
        }
    }

    // test using nonAS.snp.positive for SNP-only training = using nonAS.both.positive for SNP-only training

    // exception test annotation-name validation using AS.snp.positive and nonAS.snp.positiveUnlabeled
    // exception test no-data validation using nonAS.snp.positive and nonAS.both.positiveUnlabeled for SNP+INDEL training
    // exception test no-data validation using nonAS.snp.positive for INDEL training
    // exception test unlabeled provided and no threshold specified

    private static void assertOutputs(final String tag,
                                      final String outputPrefix) {
        if (tag.contains("train.snp")) {
            assertVariantTypeOutputs(tag, outputPrefix, "snp");
            assertNotVariantTypeOutputs(outputPrefix, "indel");
        } else if (tag.contains("train.snpIndel")) {
            assertVariantTypeOutputs(tag, outputPrefix, "snp");
            assertVariantTypeOutputs(tag, outputPrefix, "indel");
        } else {
            Assert.fail("Unknown variant-type tag.");
        }
    }

    private static void assertVariantTypeOutputs(final String tag,
                                                 final String outputPrefix,
                                                 final String variantType) {
        final String tagAndVariantType = String.format("%s.%s", tag, variantType);
        final String outputPrefixAndVariantType = String.format("%s.%s", outputPrefix, variantType);

        SystemCommandUtilsTest.runSystemCommand(String.format("h5diff %s/%s.trainingScores.hdf5 %s.trainingScores.hdf5",
                EXPECTED_TEST_FILES_DIR, tagAndVariantType, outputPrefixAndVariantType));
        SystemCommandUtilsTest.runSystemCommand(String.format("h5diff %s/%s.truthScores.hdf5 %s.truthScores.hdf5",
                EXPECTED_TEST_FILES_DIR, tagAndVariantType, outputPrefixAndVariantType));

        assertScorerOutputs(tagAndVariantType, outputPrefixAndVariantType, false);

        if (tag.contains("posNeg")) {
            SystemCommandUtilsTest.runSystemCommand(String.format("h5diff %s/%s.unlabeledScores.hdf5 %s.unlabeledScores.hdf5", EXPECTED_TEST_FILES_DIR, tagAndVariantType, outputPrefixAndVariantType));
            assertScorerOutputs(tagAndVariantType, outputPrefixAndVariantType, true);
        } else {
            Assert.assertFalse(new File(outputPrefixAndVariantType, ".unlabeledScores.hdf5").exists());
            Assert.assertFalse(new File(outputPrefixAndVariantType, ".negative.scorer.ser").exists());
            Assert.assertFalse(new File(outputPrefixAndVariantType, ".negative.scorer.pkl").exists());
        }
    }

    private static void assertNotVariantTypeOutputs(final String outputPrefix,
                                                    final String variantType) {
        final String outputPrefixAndVariantType = String.format("%s.%s", outputPrefix, variantType);
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".trainingScores.hdf5").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".truthScores.hdf5").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".unlabeledScores.hdf5").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".scorer.ser").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".scorer.pkl").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".negative.scorer.ser").exists());
        Assert.assertFalse(new File(outputPrefixAndVariantType, ".negative.scorer.pkl").exists());
    }

    private static void assertScorerOutputs(final String tagAndVariantType,
                                            final String outputPrefixAndVariantType,
                                            final boolean isNegative) {
        final String positiveOrNegativeTag = isNegative ? ".negative" : "";
        if (tagAndVariantType.contains("BGMM")) {
            SystemCommandUtilsTest.runSystemCommand(String.format("diff %s/%s.scorer.ser %s.scorer.ser", EXPECTED_TEST_FILES_DIR,
                    tagAndVariantType + positiveOrNegativeTag, outputPrefixAndVariantType + positiveOrNegativeTag));
            Assert.assertFalse(new File(outputPrefixAndVariantType, ".scorer.pkl").exists());
        } else if (tagAndVariantType.contains("IF")) {
            SystemCommandUtilsTest.runSystemCommand(String.format("diff %s/%s.scorer.pkl %s.scorer.pkl", EXPECTED_TEST_FILES_DIR,
                    tagAndVariantType + positiveOrNegativeTag, outputPrefixAndVariantType + positiveOrNegativeTag));
            Assert.assertFalse(new File(outputPrefixAndVariantType, ".scorer.ser").exists());
        } else {
            Assert.fail("Unknown model-backend tag.");
        }
    }
}