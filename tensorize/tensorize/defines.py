import logging

# ID of the dataflow pipeline run
RUN_NAME = 'ky-test'
# Type of the data to be tensorized
FIELD_TYPE = 'categorical'
# BigQuery dataset where the data will be drawn from
DATASET = 'ukbb7089_r10data'
# Runner type - set to 'DirectRunner' for local development
RUNNER = 'DataflowRunner'
# Requirements file derived from the Python environment via 'pip freeze > requirements.txt'
# Used by Dataflow to pip install the necessary packages
REQUIREMENTS_FILE = '<repo_root>/env/requirements_ml4cvd_dataflow.txt'
SETUP_FILE = '<repo_root>/tensorize/setup.py'
# Logging level - set to DEBUG for more verbosity
LOG_LEVEL = logging.INFO


OUTPUT_FOLDER = 'tensors_' + DATASET + '_' + FIELD_TYPE
GCS_BUCKET = 'ml4cvd'
GCS_BLOB_PATH = 'dataflow_experiment/output_2_12/' + OUTPUT_FOLDER

TENSOR_EXT = 'hd5'

JOIN_CHAR = '_'
CONCAT_CHAR = '-'
HD5_GROUP_CHAR = '/'
