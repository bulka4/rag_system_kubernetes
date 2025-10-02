# This is a general image used as a base one for 'MCP Server' and 'Prepare Milvus db' images.

FROM python:3.11-slim

# Install dependencies:
# pymilvus - For interacting with Milvus - vector db
# sentence-transformers - For loading HuggingFace models for sentence embedding
RUN pip install --no-cache-dir \
        pymilvus==2.6.0 \
        sentence-transformers==5.0.0