FROM python:3.11-slim

# (debugging testing) Copy app files to the root folder
# COPY . .

# Set working directory
WORKDIR /app

# Copy scripts with:
# - AI agent (LangGraph)
# - Ray Serve app
COPY . .

# (debugging testing) Convert app into a package
# RUN touch /app/__init__.py

# (debugging testing) Set up the PYTHONPATH=/app so the '/app' is added to the sys.path in Python scripts. Thanks to this we will be able to run
# 'import ray_serve_app' from any Python script in the image. Ray Service performs this import in order to start our Ray Serve app.
# ENV PYTHONPATH=/app

# (debugging testing) Install ps
RUN apt-get update && \
    apt-get install -y procps && \
    # Remove apt-get package index files to free up space. After deleting this we might not be able to use apt-get install
    # and we will need to use apt-get update again.
    rm -rf /var/lib/apt/lists/*

# Install wget. It is needed for readiness / liveness probes when deploying this app using RayService CRD on Kubernetes.
RUN apt-get update && apt-get install -y wget

# Install dependencies
RUN pip install --no-cache-dir \
        langgraph==0.6.5 \
        transformers==4.55.0 \
        torch==2.7.1 \
        ray[serve]==2.49.2 \
        fastapi==0.115.14 \
        fastmcp==2.10.0