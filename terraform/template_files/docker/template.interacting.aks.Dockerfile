FROM ubuntu:22.04

# ========== Define build-time variables ==========

# Names of images we will build and push to ACR which will be used when deploying RAG resources on AKS. Those are images for:
# - MCP Server
# - Preparing Milvus db (sample documents with their vector embeddings)
# - Ray Serve app with RAG LangGraph workflow
ARG MCP_SERVER_IMAGE_NAME=${mcp_server_image_name}
ARG PREPARE_MILVUS_DB_IMAGE_NAME=${prepare_milvus_db_image_name}
ARG RAY_SERVE_APP_IMAGE_NAME=${ray_serve_app_image_name}
ARG SEMANTIC_SEARCH_IMAGE_NAME=${semantic_search_image_name}
# This prevents prompting user for input for example when using apt-get.
ENV DEBIAN_FRONTEND=noninteractive


# Tell Docker to use bash for the rest of the Dockerfile
SHELL ["/bin/bash", "-c"]

WORKDIR /root




# ============ Install Helm, Azure CLI and kubectl =============

# Install Helm
RUN apt-get update && \
    apt-get -y install curl && \
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


# Install Azure CLI and save credentials to AKS in the ~/.kube/config (kubeconfig) file
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash && \

    # Login to Azure using CLI using the created Service Principal which has proper permissions for using 'az aks get-credentials'
    # and 'az acr build'.
    az login --service-principal \
      --username ${acr_sp_id} \
      --password ${acr_sp_password} \
      --tenant ${tenant_id} && \

    az account set --subscription ${subscription_id} && \

    # Save credentials to AKS in the ~/.kube/config (kubeconfig) file. That will enable us using kubectl to interact with AKS.
    az aks get-credentials \
      --resource-group ${rg_name} \
      --name ${aks_name}


# Install kubectl for interacting with AKS
RUN apt-get install -y apt-transport-https ca-certificates && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \

    # Add the GPG key and APT repository URL to the kubernetes.list. That url will be used to pull Kubernetes packages (like kubectl)
    <<EOF cat >> /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /
EOF

RUN apt-get update && \
    apt-get install -y kubectl && \
    apt-mark hold kubectl




# ========== Install other useful tools =============
# Install: nano
RUN apt-get install nano




# ============ Create and save a bash script for building and pushing to ACR images needed for RAG workflow =============

# Those images will be used when deploying RAG workflow resources on AKS. Those are images for:
# - MCP Server
# - Preparing Milvus db (smaple documents with their vector embeddings)
# - Ray Serve app serving the LangGraph RAG workflow

# Copy Dockerfiles and other files needed for building images
COPY apps /root/apps

# Save the script for building image and pushing it to ACR.
RUN <<EOF cat > /root/apps/build_and_push.sh
az acr build \
  --registry ${acr_name} \
  --resource-group ${rg_name} \
  --image $SEMANTIC_SEARCH_IMAGE_NAME \
  --file /root/apps/docker_images/semantic.search.Dockerfile \
  /root/apps/docker_images

az acr build \
  --registry ${acr_name} \
  --resource-group ${rg_name} \
  --image $MCP_SERVER_IMAGE_NAME \
  /root/apps/mcp_server

az acr build \
  --registry ${acr_name} \
  --resource-group ${rg_name} \
  --image $PREPARE_MILVUS_DB_IMAGE_NAME \
  /root/apps/prepare_milvus_db

az acr build \
  --registry ${acr_name} \
  --resource-group ${rg_name} \
  --image $RAY_SERVE_APP_IMAGE_NAME \
  /root/apps/ray_serve_app
EOF

RUN \
    # Remove the '\r' sign from the script
    sed -i 's/\r$//' /root/apps/build_and_push.sh && \
    # Make the script executable
    chmod +x /root/apps/build_and_push.sh




# ============ Copy the folder with Helm charts for deploying all the resources needed for RAG workflow ==============
COPY helm_charts /root/helm_charts




# Run the script for building and pushing images to ACR and start a bash session
# CMD ["bash", "-c", "/root/apps/build_and_push.sh && /bin/bash"]