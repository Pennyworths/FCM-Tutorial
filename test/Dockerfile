FROM python:3.11-alpine

WORKDIR /app

# Copy test script
COPY e2e_test.py /app/e2e_test.py

# Make script executable
RUN chmod +x /app/e2e_test.py

# Set entrypoint
ENTRYPOINT ["python3", "/app/e2e_test.py"]
