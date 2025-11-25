# Dockerfile for testAckHandler Lambda function
FROM public.ecr.aws/lambda/provided:al2023

# Copy the compiled binary
COPY bootstrap ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "bootstrap" ]

