# As a base image use another image prepared by us, used for semantic search (Python with pymilvus and sentence-transformers)
FROM aiagentbulka.azurecr.io/semantic-search

# Set working directory
WORKDIR /app

# Copy the script preparing sample data in Milvus db
COPY . .

# Install ps (just for debugging, not needed for running the app)
# RUN apt-get update && \
#     apt-get install -y procps && \
#     # Remove apt-get package index files to free up space. After deleting this we might not be able to use apt-get install
#     # and we will need to use apt-get update again.
#     rm -rf /var/lib/apt/lists/*