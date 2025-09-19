FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy:
# - requirements with dependency Python libraries to install
# - Scripts related to MCP server
# - Script with AI agent
COPY app .

# Install ps
RUN apt-get update && \
    apt-get install -y procps && \
    # Remove apt-get package index files to free up space. After deleting this we might not be able to use apt-get install
    # and we will need to use apt-get update again.
    rm -rf /var/lib/apt/lists/*

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt