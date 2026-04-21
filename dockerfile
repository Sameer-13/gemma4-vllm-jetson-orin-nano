FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        wget \
        curl \
        ca-certificates \
        bzip2 \
        git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

# Install Miniconda (aarch64 for Jetson)
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm /tmp/miniconda.sh && \
    /opt/conda/bin/conda clean -afy

ENV PATH=/opt/conda/bin:$PATH

# Accept conda Terms of Service for default channels
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Configure conda channels and update
RUN conda config --add channels conda-forge && \
    conda config --set channel_priority strict && \
    conda update -n base -c defaults conda -y

# Create the vllm-env environment from environment.yml
RUN conda env create -f environment.yml

# Initialize conda for bash and auto-activate environment
RUN /opt/conda/bin/conda init bash && \
    echo "conda activate vllm-env" >> ~/.bashrc

# Expose vLLM OpenAI API port
EXPOSE 8000