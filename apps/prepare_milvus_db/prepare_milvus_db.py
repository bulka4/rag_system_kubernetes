"""
In this script we prepare sample data (documents with their vector embeddings) in the Milvus db which will be used by the 
MCP tool for semantic search.


Here we are creating a collection with the following fields:
- id:           Unique entity ID
- embedding:    Text embedding vector
- text:         Text for which the embedding was created

We create the IVF index on the embedding field.

We save in the collection a few example docs.
"""

from pymilvus import connections, FieldSchema, CollectionSchema, DataType, Collection, utility
from sentence_transformers import SentenceTransformer
import os

# ----- Parameters ------

# nlist - Number of clusters to partition the collection of vectors into.
# docs - Documents to add to the Milvus db with their embeddings (embeddings will be created in this script).
# embedder - Model to use for creating embeddings.
# milvus_host - IP address or DNS name of the Milvus db where we store documents used for semantic search.
# milvus_collection - Name of the collection in the Milvus db with documents used for semantic search.
# embedding_field_name - Name of the field in the Collection which holds vector embeddings.
# text_field_name - Name of the field in the Collection which holds document text.
nlist = 128
docs = [
    "Apache Spark is a distributed data processing engine.",
    "MLflow is a platform to manage machine learning lifecycle.",
    "Slack is a messaging tool for teams."
]
embedder = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

milvus_host = os.getenv('MILVUS_HOST') or 'localhost'
milvus_collection = os.getenv('MILVUS_COLLECTION_NAME') or 'my_docs'
embedding_field_name = os.getenv('EMBEDDING_FIELD_NAME') or 'embedding'
text_field_name = os.getenv('TEXT_FIELD_NAME') or 'text'




# ----- Connect to Milvus -----
connections.connect("default", host=milvus_host, port="19530")

# ----- Collection setup -----
if utility.has_collection(milvus_collection):
    utility.drop_collection(milvus_collection)

fields = [
    FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
    FieldSchema(name=embedding_field_name, dtype=DataType.FLOAT_VECTOR, dim=384),
    FieldSchema(name=text_field_name, dtype=DataType.VARCHAR, max_length=1000)
]
schema = CollectionSchema(fields, description="Document embeddings")
collection = Collection(name=milvus_collection, schema=schema)

# ----- Create index -----
collection.create_index(
    field_name=embedding_field_name,
    index_params={"index_type": "IVF_FLAT", "metric_type": "COSINE", "params": {"nlist": nlist}}
)

# ----- Add docs -----
embeddings = embedder.encode(docs).tolist()
entities = [
    embeddings
    ,docs
]
# Insert entities into a collection
collection.insert(entities)
# Save data in a persistent storage on a disk
collection.flush()

print("✅ Database prepared with sample docs")
