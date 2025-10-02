# As a base image use another image prepared by us, used for semantic search (Python with pymilvus and sentence-transformers)
FROM ${acr_url}/${semantic_search_image_name}

# Set working directory
WORKDIR /app

# Copy the script with MCP server
COPY . .

# Install ps (just for debugging, not needed for running the app)
# RUN apt-get update && \
#     apt-get install -y procps && \
#     # Remove apt-get package index files to free up space. After deleting this we might not be able to use apt-get install
#     # and we will need to use apt-get update again.
#     rm -rf /var/lib/apt/lists/*

# Install dependencies
RUN pip install --no-cache-dir \
        fastmcp==2.10.0