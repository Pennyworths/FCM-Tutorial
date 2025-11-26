# Dockerfile for all Lambda functions
# This Dockerfile is used for all Go Lambda functions
FROM public.ecr.aws/lambda/provided:al2023

# Copy the compiled binary (must be named bootstrap)
# The entrypoint script looks for /var/runtime/bootstrap, so we need to copy it there
COPY bootstrap /var/runtime/bootstrap

# Also copy to LAMBDA_TASK_ROOT for compatibility
COPY bootstrap ${LAMBDA_TASK_ROOT}/bootstrap

# Copy SQL schema file for init-schema Lambda (if it exists)
# The build script copies init.sql to this directory before building
# This will be available at /var/task/init.sql
# For other Lambdas, build script creates an empty init.sql file
COPY init.sql ${LAMBDA_TASK_ROOT}/init.sql

# Set the CMD to your handler
CMD [ "bootstrap" ]

