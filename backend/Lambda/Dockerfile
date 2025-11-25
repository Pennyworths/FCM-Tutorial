# Dockerfile for all Lambda functions
# This Dockerfile is used for all Go Lambda functions
FROM public.ecr.aws/lambda/provided:al2023

# Copy the compiled binary (must be named bootstrap)
COPY bootstrap ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "bootstrap" ]

